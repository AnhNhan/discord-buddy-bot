
require 'cgi'
require 'tempfile'

require 'aws-sdk'
require 'nokogiri'
require 'httparty'
require 'image_size'
require 'parallel'

require 'discordrb'
require 'yaml'

require 'modules/buddy-functionality'

module BuddyBot::Modules::Tistory
  extend Discordrb::EventContainer

  @@s3 = nil
  @@s3_bucket = nil

  @@s3_bucket_name = nil

  @@pages = []
  @@pages_downloaded = {}

  @@initialized = false

  def self.scan_bot_files()
    pages = YAML.load_file(BuddyBot.path("content/tistory-list.yml"))
    pages_downloaded = YAML.load_file(BuddyBot.path("content/tistory-pages-downloaded.yml"))

    @@pages = pages
    @@pages_downloaded = pages_downloaded
  end

  def self.log(message, bot)
    BuddyBot::Modules::BuddyFunctionality.log message, bot, Struct.new(:id).new(123456)
  end

  ready do |event|
    if !@@initialized
      self.scan_bot_files()
      @@initialized = true
    end
    puts "Ready to upload to '#{@@s3_bucket_name}'"
  end

  def self.set_s3_bucket_name(name)
    @@s3_bucket_name = name
    @@s3 = Aws::S3::Resource.new()
    @@s3_bucket = @@s3.bucket(@@s3_bucket_name)
  end

  message(start_with: /^!tistory\s/i) do |event|
    next if event.user.bot_account?
    data = event.content.scan(/^!tistory\s+<?(.*?)\s*>?\s*$/i)[0]
    if !data
      event.send_message ":warning: You need to specify a tistory page link... #{BuddyBot::Modules::BuddyFunctionality.random_derp_emoji()}"
      next
    end

    orig_input = url = data[0].downcase

    if url !~ /https?:\/\/.*?\.tistory\.com(\/m)?\/\d+$/
      event.send_message ":warning: URL is not a specific page, try e.g. <http://gfriendcom.tistory.com/163>"
      next
    end

    if url =~ /tistory\.com\/\d+$/
      parts = url.scan(/\/\/(.*?)\.tistory\.com\/(\d+)$/)[0]
      url = "http://#{parts[0]}.tistory.com/m/#{parts[1]}"
    end
    page_name, page_number = url.scan(/\/\/(.*?)\.tistory\.com\/m\/(\d+)$/)[0]

    self.process_page(url, orig_input, page_name, page_number, event, true)
  end

  pm(start_with: /!tistory-queue-page\s/i) do |event|
    data = event.content.scan(/^!tistory-queue-page\s+([\w-]+)\s*$/i)[0]
    if !data
      event.send_message ":warning: You need to specify a trivia list name..."
      next
    end

    url = data[0].downcase
    if @@pages.include? url
      event.send_message "Already got #{url} :yerinlaughingatyou:"
      next
    end
    @@pages << url
    File.open(BuddyBot.path("content/tistory-list.yml"), "w") { |file| file.write(YAML.dump(@@pages)) }
    event.send_message ":information_desk_person: Added '#{url}' :sowonsalute:"
  end

  pm(start_with: /!tistory-queue-run/i) do |event|
    next unless event.user.id == 139342974776639489

    self.log ":information_desk_person: Starting to process the page queue! :sujipraise:", event.bot

    @@pages.each do |page_name|
      self.log ":information_desk_person: Going through `#{page_name}`'s page!", event.bot
      count_done = 0 # all done, successful, failed and 404
      count_404 = 0 # count of only 404
      count_first_404 = 0 # index of first 404 in 404 range, reset with every success
      threshold_404 = 100
      threshold_really_max = 100000

      range = 1..threshold_really_max
      range.each do |page_number|
        if page_number > threshold_404 && count_first_404 > threshold_404
          self.log ":information_desk_person: Finished with `#{page_name}`'s page!", event.bot
          break
        end

        count_done = count_done + 1

        url = "http://#{page_name}.tistory.com/m/#{page_number}"

        if @@pages_downloaded.include?(page_name) &&
          @@pages_downloaded[page_name].include?(page_number.to_s) &&
          @@pages_downloaded[page_name][page_number.to_s]["files"].keys.length == @@pages_downloaded[page_name][page_number.to_s]["expected"]
          # Already replicated
          # TODO: reset count_first_404 ?
          next
        end

        result = self.process_page(url, url, page_name, page_number, event)

        if result.is_a?(Integer)
          if result == 404
            count_404 = count_404 + 1
            if count_first_404 == 0
              count_first_404 = page_number
            end
            if count_404 % 20 == 0
              self.log ":information_desk_person: Had #{count_404} 404s already, #{count_done - count_first_404} was the first in this series for `#{page_name}`'s page!", event.bot
          else
            self.log ":warning: :warning: `#{url}` received a `#{result}`", event.bot
          end
        elsif result.nil?
          # uh...
        elsif result == true
          count_first_404 = 0
        end
      end
    end
  end

  def self.process_page(url, orig_input, page_name, page_number, event, verbose = nil)
    response = HTTParty.get(url)

    if response.code != 200
      if verbose
        self.log ":warning: Got #{response.code} #{response.message}, headers\n```\n#{response.headers.inspect}\n```\n#{response.body}", event.bot
        event.send_message ":warning: Encountered an error while loading the page! `#{response.code} #{response.message}`"
      end
      return response.code
    end

    doc = Nokogiri::HTML(response.body)
    urls = self.parse_page(doc, orig_input, event)

    page_title = doc.css('h2.tit_blogview').map{|h2| h2.content}.first

    if urls.length == 0
      event.send_message ":warning: No images found on the site!" if verbose
      self.log ":warning: Page `#{page_title}` <#{orig_input}> had no images!", event.bot
      return nil
    end

    if verbose
      event.send_message "**#{page_title}** (#{urls.length} images) - <#{orig_input}>\n#{urls.join("\n")}"
      event.message.delete() unless event.channel.pm?
    end

    self.log ":information_desk_person: Downloading #{urls.length} images from `#{page_title}` <#{orig_input}>", event.bot
    download_results = {}
    process_results = Parallel.map(urls, in_processes: 20) do |url|
      self.upload_tistory_file(url, page_name, page_number, page_title, event)
    end
    process_results.each do |result|
      next if result.nil?
      download_results[result["id"]] = result["path"]
    end

    if !@@pages_downloaded.include? page_name
      @@pages_downloaded[page_name] = {}
    end
    if !@@pages_downloaded[page_name].include? page_number
      @@pages_downloaded[page_name][page_number] = {
        "expected" => 0,
        "files" => {},
      }
    end

    orig_expected = @@pages_downloaded[page_name][page_number]["expected"]
    if orig_expected != 0 && orig_expected != urls.length
      self.log ":warning: Page `#{orig_input}` had `#{urls.length}` instead of expected #{@@pages_downloaded[page_name][page_number]["expected"]} images, looks like it got updated", event.bot
    end
    @@pages_downloaded[page_name][page_number]["expected"] = [ urls.length, @@pages_downloaded[page_name][page_number]["expected"] ].max
    download_results.keys.each do |id|
      @@pages_downloaded[page_name][page_number]["files"][id] = download_results[id]
    end
    File.open(BuddyBot.path("content/tistory-pages-downloaded.yml"), "w") { |file| file.write(YAML.dump(@@pages_downloaded)) }

    if orig_expected != 0 && orig_expected != @@pages_downloaded[page_name][page_number]["files"].keys.length
      self.log ":warning: Page `#{page_title}` <#{orig_input}>: Downloaded file count discrepancy, expected **#{@@pages_downloaded[page_name][page_number]["expected"]}** but only **#{@@pages_downloaded[page_name][page_number]["files"].keys.length}** exist, **#{download_results.keys.length}** from just now", event.bot
    end

    self.log ":ballot_box_with_check: Done replicating <#{orig_input}>", event.bot
    return true
  end

  # gib html, get urls
  def self.parse_page(doc, input_url, event)
    urls = []
    doc.css('.imageblock > .img_thumb').each do |img|
      uri = URI.parse(img.attribute('src'))
      if !uri.query
        self.log ":warning: Url '<#{input_url}>' had an invalid image, no query found: `#{img.attribute('src')}`", event.bot
        next
      end
      params = CGI.parse(uri.query)
      if !params["fname"]
        self.log ":warning: Url '<#{input_url}>' had an invalid image, no fname found: `#{img.attribute('src')}`", event.bot
        next
      end
      if params["fname"].length > 1
        self.log ":warning: Url '<#{input_url}>' had an invalid image, multiple fname found: `#{img.attribute('src')}`", event.bot
        next
      end
      fname = params["fname"][0]
      orig_url = fname.sub!("tistory.com/image/", "tistory.com/original/")
      urls << orig_url
    end
    return urls
  end

  def self.upload_tistory_file(url, page_name, page_number, page_title, event)
    file_id = url.scan(/\/original\/(\w+)$/)[0][0]

    if @@pages_downloaded.include?(page_name) && @@pages_downloaded[page_name].include?(page_number) && @@pages_downloaded[page_name][page_number].include?("files") && @@pages_downloaded[page_name][page_number]["files"].include?(file_id)
      # Already replicated
      self.log ":ballot_box_with_check: Already replicated `#{url}` @ `#{@@pages_downloaded[page_name][page_number]["files"][file_id]}`", event.bot
      return nil
    end

    time_start = Time.now # .to_f
    time_split = 0
    response = HTTParty.get(url)

    if response.code != 200
      self.log ":warning: Got #{response.code} #{response.message}, headers\n```\n#{response.headers.inspect}\n```", event.bot
      return
    end

    params = CGI.parse(response.headers["content-disposition"])
    if !params || !params[" filename"] || params[" filename"].length > 1
      self.log ":warning: Url <#{url}> had malicious content-disposition!\n```\n#{response.headers.inspect}\n```", event.bot
      return nil
    end
    file_full_name = (params[" filename"] || [ 'Untitled' ])[0].gsub!('"', '') # filename is wrapped in quotes
    file_name = File.basename(file_full_name, ".*")
    file_extension = File.extname(file_full_name)
    file_extension[0] = "" # still has leading '.'
    s3_filename = self.format_object_name(page_name, page_number, page_title, file_name, file_id, file_extension)

    object = @@s3_bucket.object(s3_filename)

    file_size = 0
    image_w = 0
    image_h = 0

    begin
      Tempfile.create('tmpf') do |tempfile|
        tempfile.write response.body
        tempfile.seek(0)
        time_split = Time.now # .to_f
        file_size = tempfile.size
        image_w, image_h = ImageSize.path(tempfile.path).size
        result = object.upload_file(tempfile)
        if !result
          puts "hi"
          raise 'Upload not successful!'
        end
      end
    rescue Exception => e
      self.log ":warning: Url <#{url}> / `#{s3_filename}` had upload error to S3! #{e}", event.bot
      return nil
    end
    time_end = Time.now # .to_f
    self.log ":ballot_box_with_check: Uploaded <#{url}> / `#{s3_filename}` " +
      "(#{(file_size.to_f / 2 ** 20).round(2)} MB, #{image_w}x#{image_h}, #{(time_split - time_start).round(1)}s " +
      "download + write, #{(time_end - time_split).round(1)}s upload S3): " +
      "#{object.presigned_url(:get, expires_in: 604800)}", event.bot
    result = { "id" => file_id, "path" => s3_filename }
    return result
  end

  def self.format_object_name(page_name, page_number, page_title, file_name, file_id, file_extension)
    "tistory/#{page_name}/#{page_number} - #{page_title}/#{file_name}-#{file_id}.#{file_extension}"
  end
end
