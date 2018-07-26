
require 'cgi'
require 'tempfile'
require 'digest/md5'
require 'stringio'
require 'enumerator'
require 'base64'

require 'aws-sdk'
require 'nokogiri'
require 'httparty'
require 'image_size'
require 'parallel'
require 'm3u8'

require 'discordrb'
require 'yaml'
require 'json'

require 'modules/buddy-functionality'

module BuddyBot::Modules::Tistory
  extend Discordrb::EventContainer

  @@s3 = nil
  @@s3_bucket = nil

  @@s3_bucket_name = nil

  @@pages = []
  @@pages_special = []
  @@pages_downloaded = {}
  @@sendanywhere_downloaded = {}
  @@twitter_list = []
  @@twitter_downloaded = {}

  @@initialized = false

  @@number_of_processes = 50

  @@abort_tistory_queue_in_progress = false
  @@abort_twitter_queue_in_progress = false

  @@twt_consumer_key = nil
  @@twt_consumer_secret = nil
  @@twt_app_bearer = nil

  def self.scan_bot_files()
    @@pages = YAML.load_file(BuddyBot.path("content/tistory-list.yml")) || []
    @@pages_special = YAML.load_file(BuddyBot.path("content/tistory-special-list.yml")) || []
    @@pages_downloaded = YAML.load_file(BuddyBot.path("content/tistory-pages-downloaded.yml")) || {}
    @@sendanywhere_downloaded = YAML.load_file(BuddyBot.path("content/downloaded-sendanywhere.yml")) || {}

    @@twitter_list = YAML.load_file(BuddyBot.path("content/pages-twitter.yml")) || []
    @@twitter_downloaded = YAML.load_file(BuddyBot.path("content/downloaded-twitter.yml")) || {}
  end

  def self.log(message, bot)
    BuddyBot::Modules::BuddyFunctionality.log message, bot, Struct.new(:id).new(123456)
  end

  def self.log_warning(message, bot)
    BuddyBot::Modules::BuddyFunctionality.log message, bot, Struct.new(:id).new(12345678)
  end

  ready do |event|
    if !@@initialized
      self.scan_bot_files()
      @@initialized = true
    end
    self.log ":information_desk_person: Ready to upload to '#{@@s3_bucket_name}'", event.bot

    @@twt_app_bearer = self.twitter_retrieve_app_bearer(@@twt_consumer_key, @@twt_consumer_secret, event.bot)

    # self.process_mobile_page("http://gfriendcom.tistory.com/m/145", "http://gfriendcom.tistory.com/m/145", "gfriendcom", "145", event, true)
    # self.process_tweet("https://twitter.com/Candle4_YB/status/1007759490588934144", event)
    # puts self.process_tweet("https://twitter.com/Mochi_Yellow/status/1007198387693748224", event)
    # puts self.process_tweet("https://twitter.com/mystarmyangel/status/1007664325916438528", event)
    # self.process_tweet("https://twitter.com/gagadoli/status/1007639571150991361", event)
    # self.process_tweet("https://twitter.com/_Simplykpop/status/994782508083539968", event)
  end

  def self.set_s3_bucket_name(name)
    @@s3_bucket_name = name
    @@s3 = Aws::S3::Resource.new()
    @@s3_bucket = @@s3.bucket(@@s3_bucket_name)
  end

  def self.set_twitter_credentials(key, secret)
    @@twt_consumer_key = key
    @@twt_consumer_secret = secret
  end

  # invoke this command if you want to e.g. add new audio clips or memes, but don't want to restart the bot. for now, you also have to invoke e.g. #audio-load manually afterwards.
  message(content: "!crawler-git-sync") do |event|
    next unless event.user.id == 139342974776639489
    event.channel.split_send "Done.\n#{`cd #{BuddyBot.path} && git pull && git add content/tistory-list.yml content/tistory-pages-downloaded.yml content/pages-twitter.yml content/downloaded-twitter.yml content/downloaded-sendanywhere.yml && git commit -m "tistory: update pages" && git push`}"
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

    self.process_mobile_page(url, orig_input, page_name, page_number, event, true)
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
    event.send_message ":information_desk_person: Added '#{url}' :SowonSalute:"
  end

  message(start_with: /!crawler-abort/i) do |event|
    next unless event.user.id == 139342974776639489
    @@abort_tistory_queue_in_progress = true
    @@abort_twitter_queue_in_progress = true
  end

  message(start_with: /!tistory-queue-run/i) do |event|
    next unless event.user.id == 139342974776639489
    @@abort_tistory_queue_in_progress = false

    self.log ":information_desk_person: Starting to process the page queue! :sujipraise:", event.bot
    @@pages_special.each do |page_name|
      self.process_pages(page_name, event) { |page_name, page_number| "http://#{page_name}/m/#{page_number}" }
    end
    @@pages.each do |page_name|
      self.process_pages(page_name, event) { |page_name, page_number| "http://#{page_name}.tistory.com/m/#{page_number}" }
    end

    if @@abort_tistory_queue_in_progress
      @@abort_tistory_queue_in_progress = false
      self.log ":information_desk_person: Aborted Tistory!", event.bot
    end
  end

  def self.process_pages(page_name, event, &build_url)
    if @@abort_tistory_queue_in_progress
      return
    end
    self.log ":information_desk_person: Going through `#{page_name}`'s page!", event.bot
    count_done = 0 # all done, successful, failed and 404
    count_replicated = 0
    count_404 = 0 # count of only 404
    count_first_404 = 0 # index of first 404 in 404 range, reset with every success
    threshold_404 = 100
    threshold_really_max = 100000

    range = 1..threshold_really_max
    range.each do |page_number|
      if page_number > threshold_404 && count_404 > threshold_404 && (page_number - count_first_404) > threshold_404
        self.log ":information_desk_person: Finished with `#{page_name}`'s page, skipped #{count_replicated}x already replicated pages, last successful was ##{count_first_404 - 1} and last checked was ##{page_number - 1}!", event.bot
        break
      end

      count_done = count_done + 1

      url = build_url.call page_name, page_number

      if @@pages_downloaded.include?(page_name) &&
        @@pages_downloaded[page_name].include?(page_number.to_s) &&
        @@pages_downloaded[page_name][page_number.to_s]["files"].keys.length == @@pages_downloaded[page_name][page_number.to_s]["expected"] &&
        @@pages_downloaded[page_name][page_number.to_s].include?("media_files") &&
        @@pages_downloaded[page_name][page_number.to_s].include?("expected_media") &&
        @@pages_downloaded[page_name][page_number.to_s]["media_files"].keys.length == @@pages_downloaded[page_name][page_number.to_s]["expected_media"]
        # Already replicated
        count_replicated = count_replicated + 1
        count_first_404 = 0
        next
      end

      result = self.process_mobile_page(url, url, page_name, page_number.to_s, event)
      if @@abort_tistory_queue_in_progress
        break
      end

      if result.is_a?(Integer)
        if result == 404
          count_404 = count_404 + 1
          if count_first_404 == 0
            count_first_404 = page_number
          end
          if count_404 % 20 == 0
            # self.log ":information_desk_person: Had #{count_404}x 404s already, currently at ##{page_number}, ##{count_first_404} was the first in this series for `#{page_name}`'s page!", event.bot
          end
        else
          self.log_warning ":warning: :warning: `#{url}` received a `#{result}`", event.bot
        end
      elsif result.nil?
        # uh...
      elsif result == true
        count_first_404 = 0
      end
    end
  end

  def self.process_mobile_page(url, orig_input, page_name, page_number, event, verbose = nil)
    if @@abort_tistory_queue_in_progress
      return "abort"
    end
    time_start = Time.now
    response = HTTParty.get(url)

    if response.code != 200
      if verbose
        self.log_warning ":warning: Got #{response.code} #{response.message}, headers\n```\n#{response.headers.inspect}\n```\n#{response.body}", event.bot
        event.send_message ":warning: Encountered an error while loading the page! `#{response.code} #{response.message}`"
      end
      return response.code
    end

    doc = Nokogiri::HTML(response.body)

    page_title = doc.css('h2.tit_blogview').map{|h2| h2.content}.first

    if doc.css('.blog_protected').length > 0
      self.log_warning ":closed_lock_with_key: Page `#{page_title}` <#{orig_input}> is protected!", event.bot
      event.send_message ":closed_lock_with_key: Page `#{page_title}` <#{orig_input}> is protected!" if verbose
      return nil
    end
    urls_images = self.extract_image_uris(doc, orig_input, event)
    media_info = self.extract_media(doc, orig_input, event)

    if urls_images.length == 0 && media_info.length == 0
      event.send_message ":warning: No images / media found on the site!" if verbose
      self.log_warning ":warning: Page `#{page_title}` <#{orig_input}> had no images / media!", event.bot
      return nil
    end

    if verbose
      event.send_message "**#{page_title}** (#{urls_images.length} image(s)) - <#{orig_input}>\n#{urls_images.join("\n")}"
      if media_info.length > 0
        event.send_message "Please note that #{media_info.length} media file(s) have been found, which are tricky to display here!"
      end
      event.message.delete() unless event.channel.pm?
    end

    self.log ":information_desk_person: Downloading #{urls_images.length} images and #{media_info.length} media from `#{page_title}` <#{orig_input}>", event.bot
    download_image_results = {}
    raw_image_download_results = []
    download_image_error_count = 0
    download_image_skip_count = 0
    process_results_images = Parallel.map(urls_images, in_processes: @@number_of_processes) do |url|
      begin
        self.upload_tistory_image_file(url, page_name, page_number, page_title, event)
      rescue Exception => e
        self.log_warning ":warning: #{BuddyBot.emoji(434376562142478367)} Had a big error for `#{url}`, `#{page_name}`, `#{page_number}`, `#{page_title}`: `#{e}`\n```\n#{e.backtrace.join("\n")}\n```", event.bot
        return { "result" => "error", "error" => e }
      end
    end
    download_media_success = []
    download_media_error_count = 0
    download_media_skip_count = 0
    process_results_media = Parallel.map(media_info, in_processes: @@number_of_processes) do |info|
      begin
        case info["type"]
        when "youtube"
          file_id = info["uri"].scan(/([A-z0-9\-_]{11})/)[0][0]
          self.upload_youtube_video(file_id, info["uri"], page_name, page_number, page_title, event)
        when "kakao_player"
          self.upload_kakao_player_video(info["uri"], page_name, page_number, page_title, event)
        when "tistory_parts_list"
          file_id = Digest::MD5.hexdigest(info["uri"])
          self.upload_tistory_parts_video(file_id, info["uri"], page_name, page_number, page_title, event)
        when "weird-gdrive-file"
          self.upload_gdrive_file_video(info["id"], info["id"], page_name, page_number, page_title, event)
        when "sowon_weird_flash_player"
          self.log_warning ":warning: Page <#{orig_input}> had `sowon_weird_flash_player`!", event.bot
          { "result" => "skipped" }
        when "nonexistent"
          { "result" => "skipped" }
        else
          self.log_warning ":warning: No idea how to process `#{info}` (<#{orig_input}>)!", event.bot
          { "result" => "error" }
        end
      rescue Exception => e
        self.log_warning ":warning: #{BuddyBot.emoji(434376562142478367)} Had a big error for `#{url}`, `#{page_name}`, `#{page_number}`, `#{page_title}`: `#{e}`\n```\n#{e.backtrace.join("\n")}\n```", event.bot
        { "result" => "error", "error" => e }
      end
    end
    # self.log ":information_desk_person: Media result: #{process_results_media}", event.bot
    if @@abort_tistory_queue_in_progress
      return "abort"
    end
    process_results_images.each do |result|
      if result.nil? || result["result"].eql?("error")
        download_image_error_count = download_image_error_count + 1
      elsif result["result"].eql? "ok"
        download_image_results[result["id"]] = result["path"]
        raw_image_download_results << result
      elsif result["result"].eql? "skipped"
        download_image_skip_count = download_image_skip_count + 1
      end
    end
    process_results_media.each do |result|
      if result["result"] == "ok"
        download_media_success << result
      elsif result["result"] == "skipped"
        download_media_skip_count = download_media_skip_count + 1
      else
        download_media_error_count = download_media_error_count + 1
      end
    end

    page_number = page_number.to_s

    if !@@pages_downloaded.include? page_name
      @@pages_downloaded[page_name] = {}
    end
    if !@@pages_downloaded[page_name].include? page_number
      @@pages_downloaded[page_name][page_number] = {
        "expected" => 0,
        "expected_media" => 0,
        "files" => {},
        "media_files" => {},
      }
    end

    # migration
    if !@@pages_downloaded[page_name][page_number].include? "media_files"
      @@pages_downloaded[page_name][page_number]["media_files"] = {}
    end

    count_media = self.gib_media_count(doc, orig_input, event)
    orig_expected_media = @@pages_downloaded[page_name][page_number]["expected_media"] || 0

    @@pages_downloaded[page_name][page_number]["expected_media"] = [ orig_expected_media, count_media ].max

    orig_expected = @@pages_downloaded[page_name][page_number]["expected"]
    if orig_expected != 0 && orig_expected != urls_images.length
      self.log_warning ":warning: Page `#{orig_input}` had `#{urls_images.length}` instead of expected #{@@pages_downloaded[page_name][page_number]["expected"]} images, looks like it got updated", event.bot
    end
    @@pages_downloaded[page_name][page_number]["expected"] = [ urls_images.length, @@pages_downloaded[page_name][page_number]["expected"] ].max
    download_image_results.keys.each do |id|
      @@pages_downloaded[page_name][page_number]["files"][id] = download_image_results[id]
    end
    process_results_media.each do |result|
      if result.nil? || result["result"] != "ok"
        next
      end
      @@pages_downloaded[page_name][page_number]["media_files"][result["id"]] = result["path_sample"]
    end
    File.open(BuddyBot.path("content/tistory-pages-downloaded.yml"), "w") { |file| file.write(YAML.dump(@@pages_downloaded)) }

    if orig_expected != 0 && orig_expected != @@pages_downloaded[page_name][page_number]["files"].keys.length
      self.log_warning ":warning: Page `#{page_title}` <#{orig_input}>: Downloaded :frame_photo: count discrepancy, expected **#{@@pages_downloaded[page_name][page_number]["expected"]}** but only **#{@@pages_downloaded[page_name][page_number]["files"].keys.length}** exist, **#{download_results.keys.length}** from just now", event.bot
    end
    if orig_expected_media != 0 && orig_expected_media != @@pages_downloaded[page_name][page_number]["media_files"].keys.length
      self.log_warning ":warning: Page `#{page_title}` <#{orig_input}>: Downloaded :movie_camera: count discrepancy, expected **#{@@pages_downloaded[page_name][page_number]["expected_media"]}** but only **#{@@pages_downloaded[page_name][page_number]["media_files"].keys.length}** exist, **#{download_media_success.length}** from just now", event.bot
    end

    total_image_count = 0
    total_image_size = 0
    total_image_time_upload = 0
    total_image_time_download = 0

    raw_image_download_results.each do |result|
      total_image_count = total_image_count + 1
      total_image_size = total_image_size + result["size"]
      total_image_time_download = total_image_time_download + result["time_download"]
      total_image_time_upload = total_image_time_download + result["time_upload"]
    end

    avg_image_download = 0
    avg_image_upload = 0
    avg_image_size = 0
    if total_image_count > 0
      avg_image_download = (total_image_time_download / total_image_count).round(1)
      avg_image_upload = (total_image_time_upload / total_image_count).round(1)
      avg_image_size = (total_image_size / total_image_count).round(1)
    end

    total_media_count = 0
    total_media_size = 0
    total_media_time_upload = 0
    total_media_time_download = 0

    download_media_success.each do |result|
      total_media_count = total_media_count + result["total_count"] - result["total_support_count"]
      total_media_size = total_media_size + result["total_size"]
      total_media_time_download = total_media_time_download + result["time_download"]
      total_media_time_upload = total_media_time_download + result["time_upload"]
    end

    avg_media_download = 0
    avg_media_upload = 0
    avg_media_size = 0
    if total_media_count > 0
      avg_media_download = (total_media_time_download / total_media_count).round(1)
      avg_media_upload = (total_media_time_upload / total_media_count).round(1)
      avg_media_size = (total_media_size / total_media_count).round(1)
    end

    time_end = Time.now
    self.log ":ballot_box_with_check: Done replicating <#{orig_input}> to `#{self.format_folder(page_name, page_number, page_title)}`, " +
      "uploading #{total_image_count}x images (total #{total_image_size.round(1)}MB, avg #{avg_image_size}MB) with #{download_image_error_count}x errors and " +
      "skipping #{download_image_skip_count}x, took me #{(time_end - time_start).round(1)}s (images and media), " +
      "avg download #{avg_image_download}s and avg upload #{avg_image_upload}", event.bot
    if @@pages_downloaded[page_name][page_number]["expected_media"] > 0
      self.log ":ballot_box_with_check: Found #{@@pages_downloaded[page_name][page_number]["expected_media"]} media files, " +
      "uploading #{total_media_count}x media files (total #{total_media_size.round(1)}MB, avg #{avg_media_size}MB) with #{download_media_error_count}x errors and " +
      "skipping #{download_media_skip_count}x, " +
      "avg download #{avg_media_download}s and avg upload #{avg_media_upload}", event.bot
    end
    return true
  end

  # gib html, get urls
  def self.extract_image_uris(doc, input_url, event)
    urls = []
    doc.css('.imageblock > .img_thumb').each do |img|
      uri = URI.parse(img.attribute('src'))
      if !uri.query
        self.log_warning ":warning: Url '<#{input_url}>' had an invalid image, no query found: `#{img.attribute('src')}`", event.bot
        next
      end
      params = CGI.parse(uri.query)
      if !params["fname"]
        self.log_warning ":warning: Url '<#{input_url}>' had an invalid image, no fname found: `#{img.attribute('src')}`", event.bot
        next
      end
      if params["fname"].length > 1
        self.log_warning ":warning: Url '<#{input_url}>' had an invalid image, multiple fname found: `#{img.attribute('src')}`", event.bot
        next
      end
      fname = params["fname"][0]
      orig_url = fname.sub!("tistory.com/image/", "tistory.com/original/")
      urls << orig_url
    end
    doc.css('.blogview_content img:not(.img_thumb)').each do |img|
      uri = img.attribute('src')
      if uri.nil?
        next
      end
      uri = uri.to_s
      if uri !~ /^http:\/\/cfile\d+\.uf\.tistory\.com\/(original|image)\/\w+/i
        if uri !~ /(\/contents\/emoticon\/|abs\.twimg\.com\/emoji\/)/ # ignore error on emoticons
          self.log_warning ":warning: Url '<#{input_url}>' had an invalid image: `#{img.attribute('src')}`", event.bot
        end
        next
      end
      if uri =~ /\/image\//
        uri = uri.sub!("/image/", "/original/")
      end
      urls << uri
    end
    return urls
  end

  def self.gib_media_count(doc, input_url, event)
    count = 0
    count = doc.css("iframe, embed").length
    doc.css(".blogview_content p").each do |p|
      content = p.content.strip
      next unless content =~ /^#{URI::regexp}$/
      if content.include? "youtu"
        count = count + 1
      end
    end
    return count
  end

  def self.extract_media(doc, input_url, event)
    media = []
    uri_tistory_flashplayers = [
      "http://goo.gl/HEJkR",
      "http://goo.gl/bGi64",
      "http://smarturl.it/sspl",
    ]
    uri_part_kakao_flashplayer = "tv.kakao.com/embed/player/cliplink"
    uri_weird_gdrive_flash_player = "https://www.googledrive.com/host/0B-9MTMyoDRgrWTc4bFN6NVNxQmc"
    uri_sowon_weird_flash_player = "http://951207.com/plugin/CallBack_bootstrapperSrc?nil_profile=tistory&nil_type=copied_post"
    uri_nonexistent_players = [ # any player that we should ignore
      "http://cfile23.uf.tistory.com/media/230A50475842C1E20ED51F",
    ]
    doc.css('embed').each do |embed|
      uri = embed.attribute('src').to_s
      flashvars = (embed.attribute('flashvars') || "").to_s

      if uri_tistory_flashplayers.include? uri
        parsed_vars = CGI.parse(flashvars)
        uri_parts_list = parsed_vars["xml"][0]
        media << { "type" => "tistory_parts_list", "uri" => uri_parts_list }
      elsif uri_nonexistent_players.include? uri
        media << { "type" => "nonexistent", "uri" => uri }
      elsif uri.include? uri_part_kakao_flashplayer
        media << { "type" => "kakao_player", "uri" => uri }
      elsif uri.eql? uri_weird_gdrive_flash_player
        parsed_vars = CGI.parse(flashvars)
        gdrive_file_id = parsed_vars["file"][0].scan(/host\/(.*?)(&|$)/)[0][0]
        media << { "type" => "weird-gdrive-file", "id" => gdrive_file_id }
      elsif uri.include? "youtu.be"
        media << { "type" => "youtube", "uri" => uri }
      elsif uri.eql? uri_sowon_weird_flash_player
        media << { "type" => "sowon_weird_flash_player", "uri" => uri, "flashvars" => flashvars }
      else
        media << { "type" => "unknown", "sub-type" => "embed", "uri" => uri, "flashvars" => flashvars }
      end
    end
    doc.css('iframe').each do |iframe|
      uri = iframe.attribute('src').to_s
      if uri.include? "youtube.com"
        media << { "type" => "youtube", "uri" => uri }
      elsif uri.include? uri_part_kakao_flashplayer
        media << { "type" => "kakao_player", "uri" => uri }
      else
        media << { "type" => "unknown", "sub-type" => "iframe", "uri" => uri }
      end
    end
    doc.css(".blogview_content p").each do |p|
      content = p.content.strip
      next unless content =~ /^#{URI::regexp}$/
      if content.include? "youtu"
        media << { "type" => "youtube", "uri" => content }
      end
    end
    return media
  end

  def self.upload_kakao_player_video(url, page_name, page_number, page_title, event)
    if url.start_with? "//"
      url = "https:" + url
    end
    puts url
    player_page = HTTParty.get(url)
    if player_page.code != 200
      return { "result" => "error", "request" => player_page }
    end

    file_id = player_page.body.scan(/ENV\.clipLinkId = '(\d+)';/)[0][0]
    selected_profile = player_page.body.scan(/ENV.profile = '(\w+)';/)[0][0]
    # impress data contains general video data, and most importantly, provides us with uuid and tid values
    impress = HTTParty.get("http://tv.kakao.com/api/v2/ft/cliplinks/#{file_id}/impress?player=monet_html5&referer=&service=daum_tistory&section=daum_tistory&withConad=true&dteType=PC&fields=clipLink,clip,channel,hasPlusFriend,user,userSkinData,-service,-tagList")
    if impress.code != 200
      return { "result" => "error", "request" => impress }
    end
    impress = JSON.parse(impress.body)
    # raw data contains the video link
    clip_data = HTTParty.get("https://tv.kakao.com/api/v2/ft/cliplinks/#{file_id}/raw" +
      "?player=monet_html5&uuid=#{impress["uuid"]}&service=daum_tistory&section=daum_tistory&tid=#{impress["tid"]}&profile=#{selected_profile}&dteType=PC&continuousPlay=false")
    if clip_data.code != 200
      return { "result" => "error", "request" => clip_data }
    end
    clip_data = JSON.parse(clip_data.body)

    file_name = impress["clipLink"]["clip"]["title"]
    profile_name = clip_data["videoLocation"]["profile"]
    video_uri = clip_data["videoLocation"]["url"]
    file_full_name = File.basename(video_uri)
    filtered_file_full_name = file_full_name.split("?")[0]
    file_extension = File.extname(filtered_file_full_name)
    file_extension[0] = "" # still has leading '.'

    acknowledged_profiles = [
      "LOW",
      "BASE",
      "MAIN",
      "HIGH",
    ]
    found_profiles = {}
    clip_data["outputList"].each{ |profile| found_profiles[profile["profile"]] = profile["label"] }
    unknown_profiles = found_profiles.keys.map{ |profile| if !acknowledged_profiles.include?(profile) then profile + ": " + found_profiles[profile] end }.compact
    if unknown_profiles.length > 0
      self.log_warning ":warning: Video on `#{url}` had unknown profile(s): `#{unknown_profiles}`", event.bot
    end

    self.generic_multi_upload(profile_name + "-" + file_id, url, page_name, page_number, page_title, event) do |dir|
      `cd #{dir} && wget '#{video_uri}'`

      output_file_list = [ { "full" => file_full_name, "name" => file_name, "ext" => file_extension } ]
      {
        "result" => "ok",
        "output_file_list" => output_file_list,
      }
    end
  end

  def self.upload_tistory_parts_video(file_id, url, page_name, page_number, page_title, event)
    self.generic_multi_upload(file_id, url, page_name, page_number, page_title, event) do |dir|
      url = url.strip # some idiots put newlines into their urls...
      player_data = HTTParty.get(url)
      if player_data.code != 200
        return { "result" => "error", "request" => player_data }
      end

      temp_file = nil
      output_file_list = []

      xml = Nokogiri::XML(player_data.body)
      xml_tracks = xml.css("track").sort_by { |k| k.at_css("title").content.to_i }
      begin
        Parallel.map(xml_tracks, in_processes: @@number_of_processes) do |track|
          part_url = track.at_css("location").content
          if part_url =~ /\/attachment\/http:\/\//
            # sometimes we get urls like http://kkangjiilove.tistory.com/attachment/http://cfile8.uf.tistory.com/media/213F224E5415065A215AEA
            part_url = part_url.scan(/\/attachment\/(http:\/\/.*)$/)[0][0]
          end
          part_download = HTTParty.get(part_url)
          if part_download.code != 200
            self.log_warning ":warning: Download error for `#{url} / #{part_url}`: #{part_download.code} - #{part_download.message}\n```\n#{part_download.inspect}\n```", event.bot
            return { "result" => "error", "http" => part_download }
          end
          part_download
        end.each do |part_download|
          if temp_file.nil?
            params = CGI.parse(part_download.headers["content-disposition"])
            if !params || !params[" filename"] || params[" filename"].length > 1
              self.log_warning ":warning: Url <#{url}> had uncompliant content-disposition!\n```\n#{part_download.headers.inspect}\n```", event.bot
              return { "result" => "error", "error" => "content-disposition" }
            end
            file_full_name = (params[" filename"] || [ 'Untitled' ])[0].gsub!('"', '').sub("/", "\/") # filename is wrapped in quotes
            if file_full_name =~ /\.\d+$/
              file_full_name = File.basename file_full_name, ".*" # remove .001
            end
            file_name = File.basename(file_full_name, ".*")
            file_extension = File.extname(file_full_name)
            file_extension[0] = "" # still has leading '.'
            output_file_list = [ { "full" => file_full_name, "name" => file_name, "ext" => file_extension } ]
            temp_file = File.open(dir + "/" + file_full_name, "wb")
          end
          written = temp_file.write part_download.body
        end
      rescue => e
        self.log_warning ":warning: Tistory video down/upload had a big error: \n```\n#{e.inspect}\n```", event.bot
        return { "result" => "error", "e" => e }
      end

      {
        "result" => "ok",
        "output_file_list" => output_file_list,
      }
    end
  end

  def self.upload_gdrive_file_video(file_id, _, page_name, page_number, page_title, event)
    self.generic_multi_upload(file_id, "https://drive.google.com/open?id=#{file_id}", page_name, page_number, page_title, event) do |dir|
      output = `cd #{dir}; gdrive download '#{file_id}'`
      puts output
    end
  end

  def self.upload_youtube_video(file_id, url, page_name, page_number, page_title, event)
    self.generic_multi_upload(file_id, url, page_name, page_number, page_title, event) do |dir|
      output = `cd #{dir} && youtube-dl --write-sub --all-subs https://youtu.be/#{file_id} 2>&1`
      output_filename = "<not downloaded yet>"
      output_file_list = []
      files_support_count = 0
      if output =~ /ERROR: giving up after 10 fragment retries/
        return { "result" => "error" }
      elsif output.include? "[ffmpeg] Merging formats into \""
        output_filename = output.scan(/\[ffmpeg\] Merging formats into "(.*?)"\n/)[0][0]
      elsif output.include? "[download] Destination: "
        scan = output.scan(/\[download\] Destination: (.*?)$/)
        if scan.length > 1
          self.log_warning ":warning: Had multiple output files for #{file_id}", event.bot
          return { "result" => "error" }
        end
        output_filename = scan[0][0]
      elsif output =~ /(ERROR: This video contains content from .*?, who has blocked it( in your country)? on copyright grounds\.|ERROR: This video is unavailable.)/
        self.log_warning ":closed_lock_with_key: YT Video <#{url}> is blocked.", event.bot
        return { "result" => "skipped" }
      else
        self.log_warning ":warning: could not infer file name\n```\n#{output}\n```", event.bot
        return { "result" => "error" }
      end
      file_name, file_extension = output_filename.scan(/^(.*?)-[A-z0-9\-_]{11}\.(.*?)$/)[0]
      output_file_list << { "full" => output_filename, "name" => file_name, "ext" => file_extension }

      if output.include? "Writing video subtitles to:"
        files_sub = output.scan(/Writing video subtitles to: (.*?)\n/).flatten
        output_file_list = output_file_list + files_sub.map do |full|
          file_name, file_extension = full.scan(/^(.*?)-[A-z0-9\-_]{11}\.(.*?)$/)[0]
          { "full" => full, "name" => file_name, "ext" => file_extension }
        end

        files_support_count = files_sub.length
      end

      {
        "result" => "ok",
        "output_file_list" => output_file_list,
        "files_support_count" => files_support_count,
      }
    end
  end

  def self.generic_multi_upload(file_id, url, page_name, page_number, page_title, event, &cb)
    if @@abort_tistory_queue_in_progress
      return { "result" => "error", "error" => "Aborting..." }
    end
    if url.nil?
      return { "result" => "error", "error" => "Empty url..." }
    end

    if @@pages_downloaded.include?(page_name) &&
      @@pages_downloaded[page_name].include?(page_number) &&
      @@pages_downloaded[page_name][page_number].include?("media_files") &&
      @@pages_downloaded[page_name][page_number]["media_files"].include?(file_id)
      # Already replicated
      return { "result" => "skipped", "id" => file_id, "path" => @@pages_downloaded[page_name][page_number]["media_files"][file_id] }
    end

    output_file_list = []

    time_start = Time.now

    files_count = 0
    files_support_count = 0
    files_size = 0

    Dir.mktmpdir do |dir|
      result = cb.call(dir)
      if result && result["result"] = "ok"
        files_support_count = result["files_support_count"] || 0
        output_file_list = result["output_file_list"]
      else
        return result
      end

      time_split = Time.now
      time_end = 0
      files_count = 0

      uploaded_file_names = []

      begin
        output_file_list.each do |file_meta|
          file = file_meta["full"]
          file_name = file_meta["name"]
          file_extension = file_meta["ext"]
          files_count = files_count + 1
          files_size = files_size + File.size(dir + "/" + file)

          s3_filename = self.format_object_name(page_name, page_number, page_title, file_name, file_id, file_extension)
          uploaded_file_names << s3_filename
          object = @@s3_bucket.object(s3_filename)
          result = object.upload_file(dir + "/" + file)
          if !result
            raise 'Upload not successful!'
          end
        end
      rescue Exception => e
        self.log_warning ":warning: One of `#{output_file_list}` had upload error to S3! #{e}\n```\n#{e.backtrace.join("\n")}\n```", event.bot
        return { "result" => "error", "error" => e }
      end
      time_end = Time.now
      files_size = files_size.to_f / (2 ** 20)
      self.log ":ballot_box_with_check: Successfully uploaded media `#{file_id}` => `#{uploaded_file_names[0]}`, #{files_size.round(1)} MB, #{(time_end - time_start).round(1)}s total", event.bot
      puts "Just uploaded #{uploaded_file_names[0]} (#{(files_size.to_f / 2**20).round(2)}MB)"
      return {
        "result" => "ok",
        "id" => file_id,
        "path_sample" => uploaded_file_names[0],
        "file_name_sample" => output_file_list[0],
        "file_list" => output_file_list,
        "total_size" => files_size,
        "total_count" => files_count,
        "total_support_count" => files_support_count,
        "time_download" => (time_split - time_start).round(1),
        "time_upload" => (time_end - time_split).round(1),
      }
    end
  end

  def self.upload_tistory_image_file(url, page_name, page_number, page_title, event)
    if @@abort_tistory_queue_in_progress
      return { "result" => "error", "error" => "Aborting..." }
    end
    if url.nil?
      return { "result" => "error", "error" => "Empty url..." }
    end
    file_id = url.scan(/\/original\/(\w+)$/)[0][0]

    if @@pages_downloaded.include?(page_name) &&
      @@pages_downloaded[page_name].include?(page_number) &&
      @@pages_downloaded[page_name][page_number].include?("files") &&
      @@pages_downloaded[page_name][page_number]["files"].include?(file_id)
      # Already replicated
      return { "result" => "skipped", "id" => file_id, "path" => @@pages_downloaded[page_name][page_number]["files"][file_id] }
    end

    time_start = Time.now # .to_f
    time_split = 0
    response = HTTParty.get(url)

    if response.code != 200
      self.log_warning ":warning: Got #{response.code} #{response.message}, headers\n```\n#{response.headers.inspect}\n```", event.bot
      return { "result" => "error", "error" => "#{response.code} #{response.message}" }
    end

    params = CGI.parse(response.headers["content-disposition"])
    if !params || !params[" filename"] || params[" filename"].length > 1
      self.log_warning ":warning: Url <#{url}> had malicious content-disposition!\n```\n#{response.headers.inspect}\n```", event.bot
      return { "result" => "error", "error" => "content-disposition" }
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
    retry_count = 0

    begin
      Tempfile.create('tmpf') do |tempfile|
        tempfile.write response.body
        tempfile.seek(0)
        time_split = Time.now # .to_f
        file_size = tempfile.size
        image_w, image_h = ImageSize.path(tempfile.path).size
        result = object.upload_file(tempfile)
        if !result
          raise 'Upload not successful!'
        end
      end
    rescue Exception => e
      retry_count = retry_count + retry_count
      retry unless retry_count > 5
      self.log_warning ":warning: Url <#{url}> / `#{s3_filename}` had upload error to S3! #{e}", event.bot
      return { "result" => "error", "error" => e }
    end
    time_end = Time.now # .to_f
    # self.log ":ballot_box_with_check: Uploaded <#{url}> / `#{s3_filename}` " +
    #   "(#{(file_size.to_f / 2 ** 20).round(2)} MB, #{image_w}x#{image_h}, #{(time_split - time_start).round(1)}s " +
    #   "download + write, #{(time_end - time_split).round(1)}s upload S3): " +
    #   "<#{object.presigned_url(:get, expires_in: 604800)}>", event.bot
    puts "Just uploaded #{s3_filename} (#{(file_size.to_f / 2**20).round(2)}MB)"
    result = {
      "result" => "ok",
      "id" => file_id,
      "path" => s3_filename,
      "url" => url,
      "size" => (file_size.to_f / 2 ** 20).round(2),
      "w" => image_w,
      "h" => image_h,
      "time_download" => (time_split - time_start).round(1),
      "time_upload" => (time_end - time_split).round(1),
      "presigned_url" => object.presigned_url(:get, expires_in: 604800),
    }
    return result
  end

  def self.format_object_name(page_name, page_number, page_title, file_name, file_id, file_extension)
    file_name = file_name.sub "/", "\/"
    page_title = page_title.sub "/", "\/"
    self.format_folder(page_name, page_number, page_title) + "#{file_name}-#{file_id}.#{file_extension}"
  end

  def self.format_folder(page_name, page_number, page_title)
    "tistory/#{page_name}/#{page_number} - #{page_title}/"
  end

  def self.replicate_sendanywhere_file(id, event)
    if @@sendanywhere_downloaded.include? id
        return { "result": "skipped", "path": @@sendanywhere_downloaded[id] }
    end

    time_start = Time.now
    time_split = nil

    device_info = HTTParty.post("https://send-anywhere.com/web/device", {
      body: '{"os_type":"web","manufacturer":"Windows","model_number":"Chrome","app_version":"2.0.0","os_version":"67","device_language":"en-US","profile_name":"Aries"}',
      headers: { "Content-Type" => "application/json" }
    })
    device_info = JSON.parse(device_info.body)
    device_key = device_info["device_key"]
    inquiry_info = HTTParty.get("https://send-anywhere.com/web/key/inquiry/" + id, { headers: { "Cookie": "device_key=" + device_key } })
    inquiry_info = JSON.parse(inquiry_info.body)
    server_uri = inquiry_info["server"]

    file_is_multiple = false
    file_full_name = nil

    # only interesting info here is number of files
    # keyinfo = HTTParty.get("#{server_uri}webfile/#{id}?device_key=#{device_key}&mode=keyinfo")

    # file names and list
    filelist = HTTParty.get("#{server_uri}webfile/#{id}?device_key=#{device_key}&mode=list&start_pos=0&end_pos=30")
    filelist = JSON.parse(filelist.body)

    if filelist["file"].length > 1
      file_is_multiple = true
    end

    if !file_is_multiple
      file_full_name = filelist["file"][0]["name"]
    end

    # 'register' device key, unlock download
    key_info = HTTParty.get("https://send-anywhere.com/web/key/#{id}", { headers: { "Cookie": "device_key=" + device_key } })
    key_info = JSON.parse(key_info.body)

    file_uri = key_info["weblink"]

    file_size_expected = key_info["file_size"]
    self.log ":information_desk_person: Starting to download '#{id}' - `#{file_full_name || 'Multi-File Archive'}` (#{(file_size_expected / 2**20).round(1)}MB)!", event.bot
    file_size = 0
    s3_path = ""
    Dir.mktmpdir do |dir|
      begin
        local_file_name = File.basename(file_uri)
        `cd #{dir} && curl -v -D headers.txt '#{file_uri}' > '#{local_file_name}'`
        file_size = File.size(dir + "/" + local_file_name)
        if file_size != file_size_expected
          self.log_warning ":warning: SendAnywhere `#{id}` had unexpected file size: #{file_size} but expected #{file_size_expected}", event.bot
          # return { "result" => "error" }
        end

        if file_is_multiple
          stdout = open(dir + "/" + "headers.txt").read
          result_scan = stdout.scan(/Content-Disposition: attachment; filename="(.*?)"/i)
          if !result_scan || !result_scan[0] || !result_scan[0][0]
            self.log_warning ":warning: SendAnywhere `#{id}` had missing content disposition:\n```\n#{stdout}\n```", event.bot
            return { "result" => "error" }
          end
          file_full_name = result_scan[0][0]
        end

        time_split = Time.now

        s3_path = "sendanywhere/#{id} - #{file_full_name}/#{file_full_name}"
        object = @@s3_bucket.object(s3_path)
        result = object.upload_file(dir + "/" + local_file_name)
        if !result
          raise 'Upload not successful!'
        end
      rescue Exception => e
        self.log_warning ":warning: SendAnywhere `#{id}` had download/upload error to S3! #{e}\n```\n#{e.backtrace.join("\n")}\n```", event.bot
        return { "result" => "error", "error" => e }
      end
    end

    time_end = Time.now
    puts "Just uploaded #{s3_path} (#{(file_size.to_f / 2**20).round(2)}MB)"

    @@sendanywhere_downloaded[id] = s3_path
    File.open(BuddyBot.path("content/downloaded-sendanywhere.yml"), "w") { |file| file.write(YAML.dump(@@sendanywhere_downloaded)) }
    self.log ":ballot_box_with_check: Successfully replicated SendAnywhere `#{id}` to `#{s3_path}` (#{(file_size.to_f / 2**20).round(1)}MB), downloading in #{(time_split - time_start).round(1)}s and uploading in #{(time_end - time_split).round(1)}!", event.bot
    return { "result" => "success", "path" => s3_path }
  end

  message(start_with: /!sendanywhere\s/i) do |event|
    next unless event.user.id == 139342974776639489
    data = event.content.scan(/^!sendanywhere\s+([\w]+)\s*$/i)[0]
    if !data
      event.send_message ":warning: You need to specify a trivia list name..."
      next
    end

    id = data[0]
    result = self.replicate_sendanywhere_file(id, event)
    puts result
  end

  message(contains: /http:\/\/sendanywhe\.re\/\w+/) do |event|
    id = event.content.scan(/http:\/\/sendanywhe.re\/(\w+)\b/)[0][0]
    result = self.replicate_sendanywhere_file(id, event)
    puts result
  end

  message(start_with: "!twitter ") do |event|
    next if event.user.bot_account?
    @@abort_twitter_queue_in_progress = false
    data = event.content.scan(/^!twitter\s+(\S+)\s*$/i)[0]
    if !data
      event.send_message ":warning: You need to specify a trivia list name..."
      next
    end
    data = data[0]

    url = data
    if data =~ /^\d+$/
      url = self.twitter_determine_full_url(data)
    end
    result = self.process_tweet(url, event)
    puts "#{result}"
    if result["result"] == "success"
      self.twitter_record_successful_result(result["author"], result["id"], result)
      File.open(BuddyBot.path("content/downloaded-twitter.yml"), "w") { |file| file.write(YAML.dump(@@twitter_downloaded)) }
    end
    # TODO Do something with errors
    if @@abort_twitter_queue_in_progress
      @@abort_twitter_queue_in_progress = false
      self.log ":information_desk_person: Aborted Twitter!", event.bot
      next
    end
    self.log ":information_desk_person: Finished going through <#{url}>: \n```\n#{result}\n```", event.bot
  end

  message(start_with: "!twitter-page ") do |event|
    next if event.user.bot_account?
    @@abort_twitter_queue_in_progress = false
    data = event.content.scan(/^!twitter-page\s+(\S+)\s*$/i)[0]
    if !data
      event.send_message ":warning: You need to specify a trivia list name..."
      next
    end
    data = data[0]

    author = data
    self.process_twitter_profile(author, event)
    if @@abort_twitter_queue_in_progress
      @@abort_twitter_queue_in_progress = false
      self.log ":information_desk_person: Aborted Twitter!", event.bot
    end
  end

  message(content: "!twitter-queue-run") do |event|
    next if event.user.bot_account?
    @@abort_twitter_queue_in_progress = false
    @@twitter_list.each do |author|
      self.process_twitter_profile(author, event)
    end
    if @@abort_twitter_queue_in_progress
      @@abort_twitter_queue_in_progress = false
      self.log ":information_desk_person: Aborted Twitter!", event.bot
    end
  end

  def self.twitter_determine_full_url(id)
    url = "https://twitter.com/twitter/statuses/#{id}"
    result = HTTParty.head(url, follow_redirects: false)
    if result.code != 301
      self.log_warning ":warning: Tweet ##{id} was maybe not found: `#{result.inspect}`", event.bot
    end
    tweet_url = result.headers["location"]
  end

  def self.process_tweet(url, event)
    if @@abort_twitter_queue_in_progress
      return
    end
    time_start = Time.now
    twitter_host, author, id = url.scan(/^(https:\/\/twitter.com)?\/(\w+)\/status\/(\d+)$/)[0]
    if @@twitter_downloaded.include?(author) &&
      @@twitter_downloaded[author].include?(id) &&
      @@twitter_downloaded[author][id]["files_images"].keys.length == @@twitter_downloaded[author][id]["expected_images"] &&
      @@twitter_downloaded[author][id]["files_videos"].keys.length == @@twitter_downloaded[author][id]["expected_videos"] &&
      @@twitter_downloaded[author][id]["files_links"].keys.length == @@twitter_downloaded[author][id]["expected_links"]
      return { "result" => "skipped" }
    end
    if twitter_host.nil? || twitter_host.empty?
      url = "https://twitter.com" + url
    end
    page_contents = HTTParty.get(url)
    if page_contents.code != 200
      # :sowonnotlikethis:
      return { "result": "error", "request" => page_contents }
    end
    page_contents = Nokogiri::HTML(page_contents.body)
    images = page_contents.css('meta[property="og:image"]').map do |meta|
      image_url = meta.attribute("content").to_s.sub(/:large$/, ":orig")
      image_url = image_url + ":orig" unless image_url =~ /:orig$/
      next unless image_url =~ /\/media\//
      image_url
    end.compact
    title = ""
    description_meta = page_contents.at_css('meta[property="og:description"]')
    if description_meta
      title = description_meta.attribute("content").to_s.gsub(URI::regexp, "").gsub(/[“”]/, "").gsub(/\s+/, " ").gsub(/\s”/, "”").gsub("/", "\/").strip
    end
    videos = page_contents.css('meta[property="og:video:url"]').map do |meta|
      video_id = meta.attribute("content").to_s.scan(/(\d{4,})/)[0][0]
    end.compact
    links = page_contents.css('.TweetTextSize--jumbo.tweet-text a:not(.u-hidden):not(.twitter-hashtag)').map do |link|
      link_url = link.attribute("data-expanded-url").to_s
    end.compact

    subfolder = id.to_s
    if title && title.length != 0
      subfolder = subfolder + " - " + title
    end
    s3_folder = "twitter/@#{author}/#{subfolder}/"

    results_images = images.map do |image_url|
      begin
        image_filename = image_url.scan(/\/([\w-]+\.(jpg|png)):/)[0][0]
      rescue => e
        self.log_warning ":warning: Had an error extracting image_filename from `#{image_url}`:\n```\n#{e.inspect}\n```", event.bot
        next { "result" => "error" }
      end
      if @@twitter_downloaded.include?(author) &&
        @@twitter_downloaded[author].include?(id) &&
        @@twitter_downloaded[author][id]["files_images"].include?(image_filename)
        next { "result" => "skipped" }
      end
      file_size = 0
      s3_path = s3_folder + image_filename
      retry_count = 0
      begin
        Tempfile.create('tmpf') do |tempfile|
          tempfile.write HTTParty.get(image_url).body
          tempfile.seek(0)
          file_size = tempfile.size
          object = @@s3_bucket.object(s3_path)
          result = object.upload_file(tempfile)
          puts "Just uploaded #{s3_path} (#{(file_size.to_f / 2**20).round(2)}MB)"
          if !result
            raise 'Upload not successful!'
          end
        end
        { "result" => "success", "id" => image_filename, "path" => s3_path }
      rescue Exception => e
        retry_count = retry_count + 1
        retry unless retry_count > 5
        self.log_warning ":warning: Url <#{url}> / `#{s3_path}` had upload error to S3! #{e.inspect}", event.bot
        { "result" => "error", "error" => e }
      end
    end

    results_videos = videos.map do |video_id|
      if @@twitter_downloaded.include?(author) &&
        @@twitter_downloaded[author].include?(id) &&
        @@twitter_downloaded[author][id]["files_videos"].include?(video_id)
        next { "result" => "skipped" }
      end
      poster_filename = nil
      # uploading urls
      video_info_url = "https://api.twitter.com/1.1/videos/tweet/config/#{video_id}.json"
      video_info_request = HTTParty.get(video_info_url, { headers: { "Authorization" => "Bearer #{@@twt_app_bearer}" } })
      if video_info_request.code != 200
        next { "result" => "error", "request" => video_info_request }
      end
      video_info = JSON.parse video_info_request.body

      video_uri = video_info["track"]["playbackUrl"]
      video_type = video_info["track"]["playbackType"]
      video_content_type = video_info["track"]["contentType"]
      if ((video_content_type == "media_entity" || video_content_type == "gif") && (video_type != "video/mp4" && video_type != "application/x-mpegURL")) && video_content_type != "vmap"
        self.log_warning ":warning: Twitter <#{url}> had unknown video type: #{video_type}\nInfo: `#{video_info}`", event.bot
        next { "result" => "error", "video_info" => video_info }
      end

      if video_content_type == "vmap"
        vmap_uri = video_info["track"]["vmapUrl"]
        vmap_request = HTTParty.get(vmap_uri)
        if vmap_request.code != 200
          self.log_warning ":warning: Could not retrieve vmap for <#{url}>: `#{vmap_request.inspect}`", event.bot
          next { "result" => "error", "request" => vmap_request }
        end
        vmap = Nokogiri::XML(vmap_request.body)
        video_uri = vmap.xpath("//MediaFile").first.content.strip
        poster_filename = File.basename(video_uri, ".*") + ".png"
      end

      if video_type == "application/x-mpegURL"
        poster_filename = File.basename(video_uri.sub(/\?tag=\d+/i, ""), ".m3u8") + ".jpg"
      end

      # poster
      poster_uri = video_info["posterImage"]
      if !poster_filename
        poster_filename = File.basename(poster_uri)
      end
      s3_path = s3_folder + poster_filename
      begin
        Tempfile.create('tmpf') do |tempfile|
          tempfile.write HTTParty.get(poster_uri).body
          tempfile.seek(0)
          file_size = tempfile.size
          object = @@s3_bucket.object(s3_path)
          result = object.upload_file(tempfile)
          puts "Just uploaded #{s3_path} (#{(file_size.to_f / 2**20).round(2)}MB)"
          if !result
            raise 'Upload not successful!'
          end
        end
      rescue Exception => e
        retry_count = retry_count + 1
        retry unless retry_count > 5
        self.log_warning ":warning: Url <#{url}> / `#{s3_path}` had upload error to S3! #{e.inspect}", event.bot
        next { "result" => "error", "error" => e }
      end

      # actual video
      if video_type == "application/x-mpegURL"
        filename = File.basename(video_uri.sub("?tag=3", ""), ".m3u8") + ".mp4"
        subtitle_map = {}
        twt_video_host = "https://video.twimg.com"
        playlist_request = HTTParty.get(video_uri)
        if playlist_request.code != 200
          return { "result" => "error", "request" => playlist_request }
        end
        playlist = M3u8::Playlist.read playlist_request.body
        next_playlist_uri = twt_video_host + playlist.items.sort_by do |item|
          if item.type == "SUBTITLES"
            subtitle_map[item.language] = twt_video_host + item.uri
            next
          elsif !item.respond_to?(:bandwidth)
            raise "Bandwidth not defined for playlist <#{video_uri}>"
          end
          item.bandwidth
        end[-1].uri
        subtitle_map.each do |lang, subtitle_uri|
          subtitle_playlist_request = HTTParty.get(subtitle_uri)
          if subtitle_playlist_request.code != 200
            return { "result" => "error", "request" => subtitle_playlist_request }
          end
          subtitle_playlist = M3u8::Playlist.read subtitle_playlist_request.body
          if subtitle_playlist.items.length > 1
            self.log_warning ":warning: <#{url}> had multiple subtitle entries, please advise (<#{subtitle_uri}>)", event.bot
            break
          end
          subtitle_file_uri = subtitle_playlist.items.first.uri
          subtitle_file_request = HTTParty.get(subtitle_file_uri)
          if subtitle_file_request.code != 200
            return { "result" => "error", "request" => subtitle_file_request }
          end
          s3_path = s3_folder + File.basename(filename, ".*") + ".#{lang}" + File.extname(subtitle_file_uri)
          Tempfile.create('tmpf') do |tempfile|
            tempfile.write subtitle_file_request.body
            file_size = tempfile.size
            object = @@s3_bucket.object(s3_path)
            result = object.upload_file(tempfile.path)
            puts "Just uploaded #{s3_path} (#{(file_size.to_f / 2**20).round(2)}MB)"
            if !result
              raise 'Upload not successful!'
            end
          end
        end
        next_playlist_request = HTTParty.get(next_playlist_uri)
        if next_playlist_request.code != 200
          return { "result" => "error", "request" => next_playlist_request }
        end
        next_playlist = M3u8::Playlist.read next_playlist_request.body
        begin
          Tempfile.create('tmpf') do |tempfile|
            next_playlist.items.map { |segment| twt_video_host + segment.segment }.each do |segment_uri|
              segment_request = HTTParty.get(segment_uri)
              if segment_request.code != 200
                return { "result" => "error", "request" => segment_request }
              end
              tempfile.write segment_request.body
            end
            path = tempfile.path
            tempfile.flush
            `ffmpeg -i #{path} -c:v copy -c:a copy -bsf:a aac_adtstoasc #{path}2.mp4`

            s3_path = s3_folder + filename
            file_size = tempfile.size
            object = @@s3_bucket.object(s3_path)
            result = object.upload_file("#{path}2.mp4")
            puts "Just uploaded #{s3_path} (#{(file_size.to_f / 2**20).round(2)}MB)"
            if !result
              raise 'Upload not successful!'
            end
          end
        rescue Exception => e
          retry_count = retry_count + 1
          retry unless retry_count > 5
          self.log_warning ":warning: Url <#{url}> / `#{s3_path}` had upload error to S3! #{e.inspect}", event.bot
          { "result" => "error", "error" => e }
        end

        { "result" => "success", "id" => video_id, "path" => s3_path }
      else
        # straight mp4 (/ vmap)

        s3_path = s3_folder + File.basename(video_uri)
        begin
          Tempfile.create('tmpf') do |tempfile|
            tempfile.write HTTParty.get(video_uri).body
            tempfile.flush
            tempfile.seek(0)
            file_size = tempfile.size
            object = @@s3_bucket.object(s3_path)
            result = object.upload_file(tempfile)
            puts "Just uploaded #{s3_path} (#{(file_size.to_f / 2**20).round(2)}MB)"
            if !result
              raise 'Upload not successful!'
            end
          end
          { "result" => "success", "id" => video_id, "path" => s3_path }
        rescue Exception => e
          retry_count = retry_count + 1
          retry unless retry_count > 5
          self.log_warning ":warning: Url <#{url}> / `#{s3_path}` had upload error to S3! #{e.inspect}", event.bot
          { "result" => "error", "error" => e }
        end
      end
    end

    results_links = links.map do |link_url|
      if @@twitter_downloaded.include?(author) &&
        @@twitter_downloaded[author].include?(id) &&
        @@twitter_downloaded[author][id]["files_links"].include?(Digest::MD5.hexdigest(link_url))
        next { "result" => "skipped" }
      end
      { "result" => "not_implemented", "reason" => "not implemented" }
    end

    time_end = Time.now
    {
      "result" => "success",
      "id" => id,
      "author" => author,
      "path" => s3_folder,
      "images" => results_images,
      "videos" => results_videos,
      "links" => results_links,
      "expected_images" => images.length,
      "expected_videos" => videos.length,
      "expected_links" => links.length,
      "time_taken" => time_end - time_start,
    }
  end

  # this routine will also process retweets
  def self.process_twitter_profile(author, event)
    if @@abort_twitter_queue_in_progress
      return
    end
    self.log ":information_desk_person: Going through @#{author}'s Twitter page", event.bot
    time_start = Time.now
    earliest_tweet_id = false
    results = []
    has_more_items = true

    while has_more_items && !earliest_tweet_id.nil? do
      tweets = HTTParty.get("https://twitter.com/i/profiles/show/#{author}/timeline/tweets?include_available_features=1&count=200&include_entities=1#{if earliest_tweet_id then "&max_position=" + earliest_tweet_id end}&reset_error_state=false")
      if tweets.code != 200
        # :sowonnotlikethis:
        return { "result": "error", "request" => tweets }
      end
      tweets = JSON.parse(tweets.body)
      tweets_html = Nokogiri::HTML(tweets["items_html"])
      has_more_items = tweets["has_more_items"]
      earliest_tweet_id = tweets["min_position"]

      tweet_urls = tweets_html.css(".tweet").map do |div|
        # these are absolute urls without host
        div.attribute("data-permalink-path").to_s
      end || []

      tweet_urls.each do |tweet_url|
        begin
          result = self.process_tweet(tweet_url, event)
        rescue => e
          self.log_warning ":warning: Tweet <#{tweet_url}> had an error:\n```\n#{e.inspect}\n```\n", event.bot
          results << { "result" => "error" }
          next
        end
        if @@abort_twitter_queue_in_progress
          return
        end
        results << result

        if result && result["result"] == "success"
          begin
            self.twitter_record_successful_result(result["author"], result["id"], result)
          rescue => e
            self.log_warning ":warning: Tweet `#{tweet_url}` had exception:\n```\n#{e.inspect}\n```", event.bot
          end
        end
        # TODO Do something with errors
      end
      if @@abort_twitter_queue_in_progress
        return
      end

      File.open(BuddyBot.path("content/downloaded-twitter.yml"), "w") { |file| file.write(YAML.dump(@@twitter_downloaded)) }

      self.log ":ballot_box_with_check: `#{Time.now}` Just went through #{tweet_urls.length}x tweets from @#{author}'s profile, #{results.length}x tweets so far", event.bot

      puts "has more pages: #{has_more_items.inspect}, min pos #{earliest_tweet_id.inspect}"
    end

    result_counts = {
      "total_error" => 0,
      "total_skipped" => 0,
      "success_images" => 0,
      "success_videos" => 0,
      "success_links" => 0,
      "skipped_images" => 0,
      "skipped_videos" => 0,
      "skipped_links" => 0,
      "error_images" => 0,
      "error_videos" => 0,
      "error_links" => 0,
      "not_implemented_images" => 0,
      "not_implemented_videos" => 0,
      "not_implemented_links" => 0,
    }

    results.each do |result|
      if !result || result["result"] == "error"
        result_counts["total_error"] = result_counts["total_error"] + 1
        next
      end
      if result["result"] == "skipped"
        result_counts["total_skipped"] = result_counts["total_skipped"] + 1
        next
      end
      [ "images", "videos", "links" ].each do |key|
        (result[key] || []).each do |element_result|
          if !element_result || !element_result["result"]
            result_counts["error_" + key] = result_counts["error_" + key] + 1
          else
            result_counts[element_result["result"] + "_" + key] = result_counts[element_result["result"] + "_" + key] + 1
          end
        end
      end
    end

    download_summary = result_counts.delete_if { |key, value| value == 0 }.map { |key, value| "#{key}: #{value}x" }.join("\n") || "no media found"

    time_end = Time.now
    self.log ":ballot_box_with_check: Finished going through @#{author}'s page, processing #{results.length}x tweets in #{(time_end - time_start).round(1)}s\n#{download_summary}", event.bot
  end

  def self.twitter_record_successful_result(author, id, result)
    if !@@twitter_downloaded.include? author
      @@twitter_downloaded[author] = {}
    end
    if !@@twitter_downloaded[author].include? id
      @@twitter_downloaded[author][id] = {
        "expected_images" => 0,
        "expected_videos" => 0,
        "expected_links" => 0,
        "files_images" => {},
        "files_videos" => {},
        "files_links" => {},
      }
    end

    [ "images", "videos", "links" ].each do |key|
      @@twitter_downloaded[author][id]["expected_" + key] = [ @@twitter_downloaded[author][id]["expected_" + key], result["expected_" + key] ].max
      result[key].each do |element_result|
        if element_result["result"] == "success"
          @@twitter_downloaded[author][id]["files_" + key][element_result["id"]] = element_result["path"]
        end
      end
    end
  end

  # provide bearer token from logging into twitter and looking into the network panel
  message(start_with: "!twitter-get-following ") do |event|
    screen_name, bearer_token, cursor = event.content.scan(/^!twitter-get-following\s+(\w+)\s+(.*?)(\s+(.*?))?\s*$/i)[0]

    screen_names = []

    cursor = (cursor || "-1").strip
    while !cursor.nil? && cursor != "0"
      request = HTTParty.get("https://api.twitter.com/1.1/friends/list.json?cursor=#{cursor}&count=200&include_user_entities=false&skip_status=1&screen_name=#{screen_name}", { "headers": { "authorization": "Bearer " + bearer_token } })
      puts request.code
      if request.code != 200
        if request.code == 429
          event.send_message "Bumped into rate limiting, current cursor is '#{cursor}'"
        end
        break
      end
      data = JSON.parse(request.body)
      cursor = data["next_cursor_str"]
      data["users"].each{ |user| screen_names << user["screen_name"] }

      puts "Just added #{data["users"].length}x followings, next cursor is '#{cursor.inspect}'"
      sleep(5)
    end
    (screen_names.each_slice(10) || []).each do |_screen_names|
      event.send_message _screen_names.map{ |name| "- `#{name}`" }.join("\n")
    end
    event.send_message "EL FINITO."
  end

  def self.twitter_retrieve_app_bearer(key, secret, bot)
    endpoint = "https://api.twitter.com/oauth2/token"
    bearer_basic_authentication = Base64.strict_encode64 "#{key}:#{secret}"
    result = HTTParty.post(endpoint, {
      body: 'grant_type=client_credentials',
      headers: {
        "Authorization" => "Basic #{bearer_basic_authentication}",
        "Content-Type" => "application/x-www-form-urlencoded;charset=UTF-8",
      }
    })
    if result.code != 200
      self.log_warning ":warning: Invalid request when requesting app bearer for Twitter: #{result.inspect}", bot
      return nil
    end
    result_json = JSON.parse(result.body)
    if result_json["token_type"] != "bearer"
      self.log_warning ":warning: Invalid data when requesting app bearer for Twitter: #{result_json.inspect}", bot
      return nil
    end
    result_json["access_token"]
  end
end
