
require 'cgi'

require 'aws-sdk'
require 'nokogiri'
require 'httparty'

require 'discordrb'
require 'yaml'

module BuddyBot::Modules::Tistory
  extend Discordrb::EventContainer

  @@s3 = nil
  @@s3_bucket = nil

  @@s3_bucket_name = nil

  @@pages = []
  @@pages_downloaded = {}

  def self.scan_bot_files()
    pages = YAML.load_file(BuddyBot.path("content/tistory-list.yml"))
    pages_downloaded = YAML.load_file(BuddyBot.path("content/tistory-pages-downloaded.yml"))

    @@pages = pages['pages']
    @@pages_downloaded = pages_downloaded['pages']
  end

  ready do |event|
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

    response = HTTParty.get(url)

    if response.code != 200
      event.send_message "Got #{response.code} #{response.message}, headers\n```\n#{response.headers.inspect}\n```\n#{response.body}"
      next
    end

    # puts response.body
    urls = []
    doc = Nokogiri::HTML(response.body)
    doc.css('.imageblock > .img_thumb').each do |img|
      uri = URI.parse(img.attribute('src'))
      if !uri.query
        event.send_message "Url '<#{url}>' had an invalid image, no query found, please advise <@139342974776639489>"
        next
      end
      params = CGI.parse(uri.query)
      if !params["fname"]
        event.send_message "Url '<#{url}>' had an invalid image, no fname found, please advise <@139342974776639489>"
        next
      end
      if params["fname"].length > 1
        event.send_message "Url '<#{url}>' had an invalid image, multiple fname found, please advise <@139342974776639489>"
        next
      end
      fname = params["fname"][0]
      orig_url = fname.sub!("tistory.com/image/", "tistory.com/original/")
      urls << orig_url
    end

    if !urls.length
      event.send_message "No images found on the site, aborting!"
    end

    event.send_message "**#{doc.css('h2.tit_blogview').map{|h2| h2.content}.first}** (#{urls.length} images) - <#{orig_input}>\n#{urls.join("\n")}"
    event.message.delete() unless event.channel.pm?
  end

  # pm(start_with: /!tistory-page\s/i) do |event|
  # end

  # pm(start_with: /!tistory-queue-page\s/i) do |event|
  #   data = event.content.scan(/^!tistory\s+(.*?)\s*$/i)[0]
  #   if !data
  #     event.send_message "You need to specify a trivia list name... #{self.random_derp_emoji()}"
  #     next
  #   end

  #   url = data[0].downcase
  #   event.send_message 'You gave me "#{url}"'
  #   @@pages << url
  #   File.open(BuddyBot.path("content/tistory-list.yml"), "w") { |file| file.write(YAML.dump({ pages: @@pages })) }
  # end

  # pm(start_with: /!tistory-queue-run\s/i) do |event|
  # end

  # def self.parse_page()
  # end

  # def self.upload_file()
  # end

  # pm(content: "!test-upload") do |event|
  #   event.send_message "Starting..."
  #   file_name = self.format_object_name("test1", "321", "180507 대구 팬싸인회 은하 1", "9946F23F5B10F065210816", "jpg")
  #   object = @@s3_bucket.object(file_name)
  #   object.upload_file(BuddyBot.path("GFRIEND-NAVILLERA-Lyrics.jpg"))
  #   event.send_message "Finished..."
  # end

  def self.format_object_name(page_name, page_number, file_name, file_id, file_extension)
    "tistory/#{page_name}/#{page_number}/#{file_name}-#{file_id}.#{file_extension}"
  end
end
