
require 'cgi'
require 'tempfile'
require 'digest/md5'

require 'aws-sdk'
require 'nokogiri'
require 'httparty'
require 'image_size'
require 'parallel'

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

  @@initialized = false

  @@number_of_processes = 50

  @@abort_in_progress = false

  def self.scan_bot_files()
    @@pages = YAML.load_file(BuddyBot.path("content/tistory-list.yml")) || []
    @@pages_special = YAML.load_file(BuddyBot.path("content/tistory-special-list.yml")) || []
    @@pages_downloaded = YAML.load_file(BuddyBot.path("content/tistory-pages-downloaded.yml")) || {}
    @@sendanywhere_downloaded = YAML.load_file(BuddyBot.path("content/downloaded-sendanywhere.yml")) || {}
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
    puts "Ready to upload to '#{@@s3_bucket_name}'"

    # self.process_mobile_page("http://gfriendcom.tistory.com/m/145", "http://gfriendcom.tistory.com/m/145", "gfriendcom", "145", event, true)
  end

  def self.set_s3_bucket_name(name)
    @@s3_bucket_name = name
    @@s3 = Aws::S3::Resource.new()
    @@s3_bucket = @@s3.bucket(@@s3_bucket_name)
  end

  # invoke this command if you want to e.g. add new audio clips or memes, but don't want to restart the bot. for now, you also have to invoke e.g. #audio-load manually afterwards.
  message(content: "!tistory-git-sync") do |event|
    next unless event.user.id == 139342974776639489
    event.channel.split_send "Done.\n#{`cd #{BuddyBot.path} && git pull && git add content/tistory-list.yml && git commit -m "tistory: update pages" && git push`}"
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

  message(start_with: /!tistory-queue-abort/i) do |event|
    next unless event.user.id == 139342974776639489
    @@abort_in_progress = true
  end

  message(start_with: /!tistory-queue-run/i) do |event|
    next unless event.user.id == 139342974776639489

    self.log ":information_desk_person: Starting to process the page queue! :sujipraise:", event.bot
    @@pages_special.each do |page_name|
      self.process_pages(page_name, event) { |page_name, page_number| "http://#{page_name}/m/#{page_number}" }
    end
    @@pages.each do |page_name|
      self.process_pages(page_name, event) { |page_name, page_number| "http://#{page_name}.tistory.com/m/#{page_number}" }
    end

    if @@abort_in_progress
      @@abort_in_progress = false
      self.log ":information_desk_person: Aborted!", event.bot
    end
  end

  def self.process_pages(page_name, event, &build_url)
    if @@abort_in_progress
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
      if @@abort_in_progress
        break
      end

      if result.is_a?(Integer)
        if result == 404
          count_404 = count_404 + 1
          if count_first_404 == 0
            count_first_404 = page_number
          end
          if count_404 % 20 == 0
            self.log ":information_desk_person: Had #{count_404}x 404s already, currently at ##{page_number}, ##{count_first_404} was the first in this series for `#{page_name}`'s page!", event.bot
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
    if @@abort_in_progress
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
        else
          self.log_warning ":warning: No idea how to process `#{info}`!", event.bot
          { "result" => "error" }
        end
      rescue Exception => e
        self.log_warning ":warning: #{BuddyBot.emoji(434376562142478367)} Had a big error for `#{url}`, `#{page_name}`, `#{page_number}`, `#{page_title}`: `#{e}`\n```\n#{e.backtrace.join("\n")}\n```", event.bot
        { "result" => "error", "error" => e }
      end
    end
    # self.log ":information_desk_person: Media result: #{process_results_media}", event.bot
    if @@abort_in_progress
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
        if uri !~ /\/contents\/emoticon\// # ignore error on emoticons
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
    doc.css('embed').each do |embed|
      uri = embed.attribute('src').to_s
      flashvars = (embed.attribute('flashvars') || "").to_s

      if uri_tistory_flashplayers.include? uri
        parsed_vars = CGI.parse(flashvars)
        uri_parts_list = parsed_vars["xml"][0]
        media << { "type" => "tistory_parts_list", "uri" => uri_parts_list }
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
      xml_tracks = xml.css("track").sort_by { |k| k.at_css("title").content.to_i }.map{ |track| track.at_css("location").content }.each do |part_url|
        part_download = HTTParty.get(part_url)
        if part_download.code != 200
          self.log_warning ":warning: Download error for `#{url} / #{part_url}`: #{part_download.code} - #{part_download.message}\n```\n#{part_download.headers.inspect}\n```", event.bot
          return { "result" => "error", "http" => part_download }
        end
        if temp_file.nil?
          part_download
          params = CGI.parse(part_download.headers["content-disposition"])
          if !params || !params[" filename"] || params[" filename"].length > 1
            self.log_warning ":warning: Url <#{url}> had malicious content-disposition!\n```\n#{part_download.headers.inspect}\n```", event.bot
            return { "result" => "error", "error" => "content-disposition" }
          end
          file_full_name = (params[" filename"] || [ 'Untitled' ])[0].gsub!('"', '').sub("/", "\/") # filename is wrapped in quotes
          file_full_name = File.basename file_full_name, ".*" # remove .001
          file_name = File.basename(file_full_name, ".*")
          file_extension = File.extname(file_full_name)
          file_extension[0] = "" # still has leading '.'
          output_file_list = [ { "full" => file_full_name, "name" => file_name, "ext" => file_extension } ]
          temp_file = File.open(dir + "/" + file_full_name, "wb")
        end
        written = temp_file.write part_download.body
      end

      {
        "result" => "ok",
        "output_file_list" => output_file_list,
      }
    end
  end

  def self.upload_gdrive_file_video(file_id, _, page_name, page_number, page_title, event)
  end

  def self.upload_youtube_video(file_id, url, page_name, page_number, page_title, event)
    self.generic_multi_upload(file_id, url, page_name, page_number, page_title, event) do |dir|
      output = `cd #{dir} && youtube-dl --write-sub --all-subs https://youtu.be/#{file_id} 2>&1`
      output_filename = "<not downloaded yet>"
      output_file_list = []
      files_support_count = 0
      if output.include? "[ffmpeg] Merging formats into \""
        output_filename = output.scan(/\[ffmpeg\] Merging formats into "(.*?)"\n/)[0][0]
      elsif output.include? "[download] Destination: "
        scan = output.scan(/\[download\] Destination: (.*?)$/)
        if scan.length > 1
          self.log_warning ":warning: Had multiple output files for #{file_id}", event.bot
          return { "result" => "error" }
        end
        output_filename = scan[0][0]
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

        files_support_count = files_sub
      end

      {
        "result" => "ok",
        "output_file_list" => output_file_list,
        "files_support_count" => files_support_count,
      }
    end
  end

  def self.generic_multi_upload(file_id, url, page_name, page_number, page_title, event, &cb)
    if @@abort_in_progress
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
    if @@abort_in_progress
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
      self.log_warning ":warning: Url <#{url}> / `#{s3_filename}` had upload error to S3! #{e}", event.bot
      return { "result" => "error", "error" => e }
    end
    time_end = Time.now # .to_f
    # self.log ":ballot_box_with_check: Uploaded <#{url}> / `#{s3_filename}` " +
    #   "(#{(file_size.to_f / 2 ** 20).round(2)} MB, #{image_w}x#{image_h}, #{(time_split - time_start).round(1)}s " +
    #   "download + write, #{(time_end - time_split).round(1)}s upload S3): " +
    #   "<#{object.presigned_url(:get, expires_in: 604800)}>", event.bot
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

    # only interesting info here is number of files
    # keyinfo = HTTParty.get("#{server_uri}webfile/#{id}?device_key=#{device_key}&mode=keyinfo")

    # file names and list
    filelist = HTTParty.get("#{server_uri}webfile/#{id}?device_key=#{device_key}&mode=list&start_pos=0&end_pos=30")
    filelist = JSON.parse(filelist.body)

    if filelist["file"].length > 1
      self.log_warning ":warning: SendAnywhere #{id} had multiple files!", event.bot
    end

    file_full_name = filelist["file"][0]["name"]

    # 'register' device key, unlock download
    key_info = HTTParty.get("https://send-anywhere.com/web/key/#{id}", { headers: { "Cookie": "device_key=" + device_key } })
    key_info = JSON.parse(key_info.body)

    file_uri = key_info["weblink"]

    file_size_expected = key_info["file_size"]
    self.log ":information_desk_person: Starting to download '#{id}' - `#{file_full_name}` (#{(file_size_expected / 2**20).round(1)}MB)!", event.bot
    file_size = 0
    s3_filename = ""
    Dir.mktmpdir do |dir|
      begin
        local_file_name = File.basename(file_uri)
        `cd #{dir} && curl -v '#{file_uri}' > '#{local_file_name}'`
        file_size = File.size(dir + "/" + local_file_name)
        if file_size != file_size_expected
          self.log_warning ":warning: SendAnywhere `#{id}` had unexpected file size: #{file_size} but expected #{file_size_expected}", event.bot
          return { "result" => "error" }
        end

        time_split = Time.now

        s3_filename = "sendanywhere/#{id} - #{file_full_name}/#{file_full_name}"
        object = @@s3_bucket.object(s3_filename)
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

    @@sendanywhere_downloaded[id] = s3_filename
    File.open(BuddyBot.path("content/downloaded-sendanywhere.yml"), "w") { |file| file.write(YAML.dump(@@sendanywhere_downloaded)) }
    self.log ":ballot_box_with_check: Successfully replicated SendAnywhere `#{id}` to `#{s3_filename}` (#{(file_size / 2**20).round(1)}MB), downloading in #{(time_split - time_start).round(1)}s and uploading in #{(time_end - time_split).round(1)}!", event.bot
    return { "result" => "success", "path" => s3_filename }
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
end
