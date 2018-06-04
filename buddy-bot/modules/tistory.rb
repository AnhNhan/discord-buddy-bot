
require 'cgi'
require 'tempfile'

require 'aws-sdk'
require 'nokogiri'
require 'httparty'

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
    @@pages_downloaded = pages_downloaded['pages']
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
    next unless !event.user.bot_account?
    data = event.content.scan(/^!tistory\s+<?(.*?)\s*>?\s*$/i)[0]
    if !data
      event.send_message "You need to specify a trivia list name... #{self.random_derp_emoji()}"
      next
    end

    orig_input = url = data[0].downcase
    # event.send_message "You gave me '#{url}'"

    if url !~ /https?:\/\/.*?\.tistory\.com(\/m)?\/\d+$/
      event.send_message "URL is not a specific page, try e.g. <http://gfriendcom.tistory.com/163>"
      next
    end

    if url =~ /tistory\.com\/\d+$/
      parts = url.scan(/\/\/(.*?)\.tistory\.com\/(\d+)$/)[0]
      url = "http://#{parts[0]}.tistory.com/m/#{parts[1]}"
      # event.send_message "Converted to '#{url}'"
    end

    parts = url.scan(/\/\/(.*?)\.tistory\.com\/m\/(\d+)$/)[0]
    page_name = parts[0]
    page_number = parts[1]

    response = HTTParty.get(url)

    if response.code != 200
      event.send_message "Got #{response.code} #{response.message}, headers\n```\n#{response.headers.inspect}\n```\n#{response.body}"
      next
    end

    doc = Nokogiri::HTML(response.body)
    urls = self.parse_page(doc, orig_input, event)

    if !urls.length
      event.send_message "No images found on the site, aborting!"
      next
    end

    title = doc.css('h2.tit_blogview').map{|h2| h2.content}.first
    event.send_message "**#{title}** (#{urls.length} images) - <#{orig_input}>\n#{urls.join("\n")}"
    event.message.delete() unless event.channel.pm?

    BuddyBot::Modules::BuddyFunctionality.log "Downloading #{urls.length} images from `#{title}` <#{orig_input}>", event.bot
    urls.each do |url|
      self.upload_tistory_file(url, page_name, page_number, event)
    end
  end

  # pm(start_with: /!tistory-page\s/i) do |event|
  # end

  pm(start_with: /!tistory-queue-page\s/i) do |event|
    data = event.content.scan(/^!tistory-queue-page\s+([\w-]+)\s*$/i)[0]
    if !data
      event.send_message "You need to specify a trivia list name..."
      next
    end

    url = data[0].downcase
    if @@pages.include? url
      event.send_message "Already got #{url} :yerinlaughingatyou:"
      next
    end
    @@pages << url
    File.open(BuddyBot.path("content/tistory-list.yml"), "w") { |file| file.write(YAML.dump(@@pages)) }
    event.send_message "Added '#{url}' :sowonsalute:"
  end

  # pm(start_with: /!tistory-queue-run\s/i) do |event|
  # end

  # gib html, get urls
  def self.parse_page(doc, input_url, event)
    urls = []
    doc.css('.imageblock > .img_thumb').each do |img|
      uri = URI.parse(img.attribute('src'))
      if !uri.query
        event.send_message "Url '<#{input_url}>' had an invalid image, no query found, please advise <@139342974776639489>"
        next
      end
      params = CGI.parse(uri.query)
      if !params["fname"]
        event.send_message "Url '<#{input_url}>' had an invalid image, no fname found, please advise <@139342974776639489>"
        next
      end
      if params["fname"].length > 1
        event.send_message "Url '<#{input_url}>' had an invalid image, multiple fname found, please advise <@139342974776639489>"
        next
      end
      fname = params["fname"][0]
      orig_url = fname.sub!("tistory.com/image/", "tistory.com/original/")
      urls << orig_url
    end
    return urls
  end

  def self.upload_tistory_file(url, page_name, page_number, event)
    file_id = url.scan(/\/original\/(\w+)$/)[0][0]
    response = HTTParty.get(url)

    if response.code != 200
      BuddyBot::Modules::BuddyFunctionality.log "Got #{response.code} #{response.message}, headers\n```\n#{response.headers.inspect}\n```", event.bot
      return
    end

    params = CGI.parse(response.headers["content-disposition"])
    if !params || !params[" filename"] || params[" filename"].length > 1
      BuddyBot::Modules::BuddyFunctionality.log "Url <#{url}> had malicious content-disposition!\n```\n#{response.headers.inspect}\n```", event.bot
      return
    end
    file_full_name = (params[" filename"] || [ 'Untitled' ])[0].gsub!('"', '')
    file_name = File.basename(file_full_name, ".*")
    file_extension = File.extname(file_full_name)
    file_extension[0] = ""
    s3_filename = self.format_object_name(page_name, page_number, file_name, file_id, file_extension)

    object = @@s3_bucket.object(s3_filename)

    begin
      Tempfile.create('tmpf') do |tempfile|
        tempfile.write response.body
        tempfile.rewind
        result = object.upload_file(tempfile.path)
        if !result
          puts "hi"
          raise 'Upload not successful!'
        end
      end
    rescue Exception => e
      BuddyBot::Modules::BuddyFunctionality.log "Url <#{url}> / `#{s3_filename}` had upload error to S3! #{e}", event.bot
      return
    end
    BuddyBot::Modules::BuddyFunctionality.log "Uploaded <#{url}> / `#{s3_filename}`: <#{object.presigned_url(:get, expires_in: 604800)}>", event.bot
  end

  def self.format_object_name(page_name, page_number, file_name, file_id, file_extension)
    "tistory/#{page_name}/#{page_number}/#{file_name}-#{file_id}.#{file_extension}"
  end
end
