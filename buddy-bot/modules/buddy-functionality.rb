
require 'discordrb'
require 'yaml'

module BuddyBot::Modules::BuddyFunctionality
  extend Discordrb::EventContainer

  @@initialized = false

  @@member_names = {}

  @@primary_role_names = []

  @@primary_ids = []

  @@special_members = {}

  @@members_of_other_groups = {}

  @@ignored_roles = []

  @@new_member_roles = {}

  @@server_thresholds = {}
  @@server_threshold_remove_roles = {}
  @@server_bot_commands = {}

  @@global_counted_messages = 0
  @@member_message_counts = {}

  @@member_role_emoji_join = {}
  @@member_role_emoji_leave = {}

  @@global_emoji_map = {}

  @@biasgame_easter_eggs = {}
  @@derp_faces = {}

  def self.scan_bot_files()
    member_config = YAML.load_file(BuddyBot.path("content/bot.yml"))

    @@member_names = member_config["member_names"]
    @@primary_role_names = member_config["primary_role_names"]
    @@primary_ids = member_config["primary_ids"]
    @@special_members = member_config["special_members"]
    @@members_of_other_groups = member_config["members_of_other_groups"]
    @@ignored_roles = member_config["ignored_roles"]
    @@new_member_roles = member_config["new_member_roles"]
    @@server_thresholds = member_config["server_thresholds"]
    @@server_threshold_remove_roles = member_config["server_threshold_remove_roles"]
    @@server_bot_commands = member_config["server_bot_commands"]
    @@member_role_emoji_join = member_config["member_role_emoji_join"]
    @@member_role_emoji_leave = member_config["member_role_emoji_leave"]
    @@biasgame_easter_eggs = member_config["biasgame_easter_eggs"]
    @@derp_faces = member_config["derp_faces"]

    @@motd = File.readlines(BuddyBot.path("content/motds.txt")).map(&:strip)
  end

  def self.scan_member_message_counts()
    @@member_message_counts = YAML.load_file(BuddyBot.path("content/member_message_counts.yml"))
  end

  def self.persist_member_message_counts()
    File.open(BuddyBot.path("content/member_message_counts.yml"), "w") { |file| file.write(YAML.dump(@@member_message_counts)) }
  end

  def self.log(msg, bot)
    msg.scan(/.{1,2000}/m).map do |chunk|
      # buddy bot log on anh-test
      bot.send_message 189800756403109889, chunk
    end
  end

  def self.find_emoji(input)
    input.downcase.scan(/([A-z]+)/).select{ |part| @@member_role_emoji_join.include?(part.first) }.flatten
  end

  def self.random_derp_emoji()
     BuddyBot.emoji(@@derp_faces[["yerin", "yuju", "sinb", "umji", "sowon", "eunha"].sample]).mention
  end

  def self.find_roles(server, name, requesting_primary)
    name = name.downcase
    searches = []
    if name['+']
      searches.concat name.split('+')
    else
      searches << name
    end
    roles = server.roles.find_all do |role|
      if @@ignored_roles.include? role.name
        next
      end
      match = role.name.downcase.scan(/([A-z]+)/).find{ |part| searches.include?(part.first) }
      if !match
        next
      end
      requesting_primary ^ !self.role_is_primary(role)
    end
    roles
  end

  # Rules for primary role:
  # - compound bias are never considered for primary
  # - when a user has a primary role: no additional primary role
  # - when a user has no primary role yet: pick the first in the list that is not a compound bias
  def self.determine_requesting_primary(user, role_name)
    role_name = role_name.downcase
    # included below
    # if role_name['+']
    #   return false
    # end
    if @@primary_role_names.include?(role_name) || (@@member_names.include?(role_name) && @@primary_role_names.include?(@@member_names[role_name]))
      # no primary yet?
      !user.roles.find{ |role| self.role_is_primary(role) }
    else
      false
    end
  end

  def self.role_is_primary(role)
    @@primary_ids.include?(role.id)
  end

  def self.members_map(text, cb_member, cb_other_member, cb_special)
    text.scan(/([A-z]+)/).map do |matches|
      original = matches.first
      match = matches.first.downcase
      if @@member_names.has_key? match
        cb_member.call match, original
      elsif @@members_of_other_groups.has_key? match
        cb_other_member.call match, original
      # special bots and members
      elsif @@special_members.has_key? match
        cb_special.call match, original, @@special_members[match]
      end
    end
  end

  def self.print_rejected_names(rejected_names, event)
    rejected_names_text = rejected_names.map do |name|
      " - #{name.capitalize} (#{@@members_of_other_groups[name].sample})"
    end.join "\n"
    event.send_message "Warning, the following member#{if rejected_names.length > 1 then 's do' else ' does' end} not belong to \#Godfriend:\n#{rejected_names_text}\nOfficials have been alerted and now are on the search for you. Remember, the only thing you need in life is GFriend."
  end

  ready do |event|
    if not @@initialized
      self.scan_bot_files()
      self.scan_member_message_counts()
      BuddyBot.build_emoji_map(event.bot.servers)
      self.scan_trivia_lists()
      # event.bot.profile.avatar = open("GFRIEND-NAVILLERA-Lyrics.jpg")
      @@initialized = true
    end
    event.bot.game = @@motd.sample
    self.log "ready!", event.bot
  end

  message(start_with: /^!motd/) do |event|
    event.bot.game = @@motd.sample
  end

  member_join do |event|
    event.server.general_channel.send_message "#{event.user.mention} joined! Welcome to the GFriend Discord server! Please make sure to read the rules in <#290827788016156674>. You can pick a bias in <#166340324355080193>."
    begin
      server = event.server
      if !@@new_member_roles.include? server.id
        self.log "A user joined #{server.name} \##{server.id} but the bot does not have a config for the server.", event.bot
        next
      end
      role_ids = @@new_member_roles[server.id]
      roles = role_ids.map do |role_id|
        server.role role_id
      end
      member = event.user.on(server)
      member.roles = roles
      self.log "Added roles '#{roles.map(&:name).join(', ')}' to '#{event.user.username} - \##{event.user.id}'", event.bot
    rescue
    end
  end

  # biasgame easter egg
  message(from: 283848369250500608, in: 318787939360571393, contains: /(GFriend \w+? vs|vs GFriend \w+?\b|Winner: GFriend \w+?!)/) do |event|
    data = event.content.scan(/GFriend (\w+)\b/)[0]
    if !data
      next
    end
    data = data.map(&:downcase)
    data.each do |name|
      if not @@biasgame_easter_eggs.include? name
        next
      end
      event.message.create_reaction(BuddyBot.emoji(@@biasgame_easter_eggs[name].sample))
    end
  end

  # new member counting
  message() do |event|
    server = event.server
    if server.nil? || event.user.nil? || event.user.bot_account? || !@@server_threshold_remove_roles.include?(server.id) || !@@server_thresholds.include?(server.id)
      next
    end
    user = event.user.on server

    remove_roles_ids = @@server_threshold_remove_roles[server.id]
    remove_threshold = @@server_thresholds[server.id]

    removable_roles = user.roles.find_all{ |role| remove_roles_ids.include?(role.id) }

    if removable_roles.empty?
      next
    end

    if !@@member_message_counts.include?(user.id)
      @@member_message_counts[user.id] = {
        "count" => 0,
      }
    end

    @@member_message_counts[user.id] = {
      "count" => @@member_message_counts[user.id]["count"] + 1
    }
    @@global_counted_messages = @@global_counted_messages + 1

    if @@member_message_counts[user.id]["count"] > remove_threshold
      user.remove_role removable_roles #, "Reached new member message threshold of #{remove_threshold}" wtf only one arg supported?
      @@member_message_counts.delete user.id
      self.log "Upgraded '#{event.user.username} - \##{event.user.id}' to a normal user", event.bot
    end

    # save every five messages
    if @@global_counted_messages % 5 == 0
      # @@global_counted_messages = 0 # prevent overflow from long running counting
      self.persist_member_message_counts()
    end
  end

  message(start_with: /^!suggest-bias\s*/i, in: "whos-your-bias") do |event|
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot
    end
    if event.user.bot_account?
      next
    end
    user = event.user.on event.server
    event.send_message "#{user.mention} My dice says **#{["Yerin", "Yuju", "SinB", "Umji", "Sowon", "Eunha"].sample}**!"
  end

  message(in: "whos-your-bias") do |event|
    text = event.content
    if text =~ /^!(remove|primary|suggest)/i
      next
    end
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot
    end
    if event.user.bot_account?
      next
    end
    user = event.user.on event.server
    added_roles = []
    rejected_names = []

    if text =~ /^!secondary /i
      event.send_message "#{user.mention} you do not need to provide the !secondary command."
    end

    if text =~ /\bot6\b/i
      removed_roles = []
      role = self.find_roles(event.server, 'ot', true).first
      if role
        current_primary_roles = user.roles.find_all{ |role| self.role_is_primary(role) }
        current_primary_roles.map do |current_primary_role|
          removed_roles << "**#{current_primary_role.name}**"
          self.log "Removed role '#{current_primary_role.name}' from '#{event.user.name}'", event.bot
          user.remove_role current_primary_role
        end
        removed_roles_text = removed_roles.join ", "
        user.add_role role
        self.find_emoji(removed_roles_text)
          .map{ |name| @@member_role_emoji_leave[name] }
          .map(&:sample).map{ |raw| BuddyBot.emoji(raw) }
          .reject()
          .each{ |emoji| event.message.create_reaction(emoji) }
        join_emojis = self.find_emoji('ot')
          .map{ |name| @@member_role_emoji_join[name] }
          .map(&:sample)
          .map{ |raw| BuddyBot.emoji(raw) }
          .reject{ |emoji| emoji.nil? }
          .map(&:mention)
          .to_a
          .join
        event.send_message(join_emojis) unless join_emojis
      end
    end

    cb_member = lambda do |match, original|
      member_name = @@member_names[match]
      role = self.find_roles event.server, member_name, self.determine_requesting_primary(user, member_name)
      user.add_role role
      role.map do |role|
        added_roles << "**#{role.name}**" + if !match.eql? member_name then " _(#{original})_" else "" end
        self.log "Added role '#{role.name}' to '#{event.user.name}'", event.bot
      end
    end
    cb_other_member = lambda do |match, original|
      rejected_names << match
      self.log "Warning, '#{event.user.name}' requested '#{match}'.", event.bot
    end
    cb_special = lambda do |match, original, user_id|
      member = event.server.member(user_id)
      event.send_message "Hey **@#{member.nick || member.username}**, lookie lookie super lookie! You have an admirer!"
    end
    self.members_map(text, cb_member, cb_other_member, cb_special)

    if !added_roles.empty?
      added_roles_text = added_roles.join ", "
      event.send_message "#{user.mention} your bias#{if added_roles.length > 1 then 'es' end} #{added_roles_text} #{if added_roles.length > 1 then 'have' else 'has' end} been added"
    end
    if !rejected_names.empty?
      self.print_rejected_names rejected_names, event
    end
  end

  message(start_with: /^!primary\s*/i, in: "whos-your-bias") do |event|
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot
    end
    if event.user.bot_account?
      next
    end
    data = event.content.scan(/^!primary\s+(.*?)\s*$/i)[0]
    if data
      data = data[0].downcase
      user = event.user.on event.server
      removed_roles = []
      added_roles = []

      if !(@@primary_role_names.include?(data) || (@@member_names.include?(data) && @@primary_role_names.include?(@@member_names[data])))
        event.send_message "#{user.mention} you didn't give me a possible primary bias"
        next
      end

      current_primary_roles = user.roles.find_all{ |role| self.role_is_primary(role) }
      member_name = @@member_names[data]
      role = self.find_roles(event.server, member_name, true).first
      if !role
        self.log "Primary role with name '#{member_name}' not found on server '#{event.server.name}'", event.bot
        next
      end

      if current_primary_roles.find{ |current_role| current_role.id == role.id }
        event.respond "You can't hop to your current primary bias #{self.random_derp_emoji()}"
        next
      end

      event.channel.start_typing

      current_primary_roles.map do |current_primary_role|
        removed_roles << "**#{current_primary_role.name}**"
        self.log "Removed role '#{current_primary_role.name}' from '#{event.user.name}'", event.bot
        user.remove_role current_primary_role
      end

      user.add_role role
      added_roles << "**#{role.name}**"
      self.log "Added role '#{role.name}' to '#{event.user.name}'", event.bot

      if !removed_roles.empty?
        removed_roles_text = removed_roles.join ", "
        self.find_emoji(removed_roles_text)
          .map{ |name| @@member_role_emoji_leave[name] }
          .map(&:sample).map{ |raw| BuddyBot.emoji(raw) }
          .reject()
          .each{ |emoji| event.message.create_reaction(emoji) }
      end
      if !added_roles.empty?
        added_roles_text = added_roles.join ", "
        event.send_message self.find_emoji(added_roles_text)
          .map{ |name| @@member_role_emoji_join[name] }
          .map(&:sample)
          .map{ |raw| BuddyBot.emoji(raw) }
          .reject()
          .map(&:mention)
          .to_a
          .join
      end
    else
      self.log "Didn't switch role. No input in '#{event.message.content}' #{event.channel.mention}", event.bot
    end
  end

  message(start_with: /^!remove\s+/i, in: "whos-your-bias") do |event|
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot
    end
    if event.user.bot_account?
      next
    end
    self.log "Remove attempt by '#{event.user.username} - \##{event.user.id}'", event.bot
    data = event.content.scan(/^!remove\s+(.*?)\s*$/i)[0]
    if data
      data = data[0]
      user = event.user.on event.server
      rejected_names = []
      removed_roles = []
      cb_member = lambda do |match, original|
        if match.eql? "buddy" # don't remove buddy role
          next
        end
        member_name = @@member_names[match]
        role = self.find_roles event.server, member_name, true
        role = role + (self.find_roles event.server, member_name, false)
        user.remove_role role
        role.map do |role|
          removed_roles << "**#{role.name}**" + if !match.eql? member_name then " _(#{original})_" else "" end
          self.log "Removed role '#{role.name}' from '#{event.user.name}'", event.bot
        end
      end
      cb_other_member = lambda do |match, original|
        rejected_names << match
        self.log "Warning, '#{event.user.name}' requested to remove '#{match}'.", event.bot
      end
      cb_special = lambda do |match, original, user_id|
        member = event.server.member(user_id)
        event.send_message "Do you really think bias hopping away from **@#{member.nick || member.username}** is any fun!?"
      end
      self.members_map data, cb_member, cb_other_member, cb_special

      if !removed_roles.empty?
        removed_roles_text = removed_roles.join ", "
        event.send_message "#{user.mention} removed bias#{if removed_roles.length > 1 then 'es' end} #{removed_roles_text}"
      end
      if !rejected_names.empty?
        self.print_rejected_names rejected_names, event
      end
    else
      self.log "Didn't remove role. No input in '#{event.message.content}' #{event.channel.mention}", event.bot
    end
  end

  message(content: ["!remove-all"]) do |event|
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot
    end
    if event.user.bot_account?
      next
    end
    self.log "Remove-All attempt by '#{event.user.username} - \##{event.user.id}'", event.bot
    user = event.user.on event.server
    removed_roles = []
    main_roles = user.roles.find_all do |role|
      if @@ignored_roles.include? role.name
        next
      end
      role.name.downcase.scan(/([A-z]+)/).find do |matches|
        @@primary_role_names.include? matches.first
      end
    end

    main_roles.map do |role|
      user.remove_role role
      removed_roles << "**#{role.name}**"
      self.log "Removed role '#{role.name}' from '#{event.user.name}'", event.bot
    end
    if !removed_roles.empty?
      removed_roles_text = removed_roles.join ", "
      event.send_message "#{user.mention} removed bias#{if removed_roles.length > 1 then 'es' end} #{removed_roles_text}"
    end
  end

  message(content: ["!help", "!commands"]) do |event|
    if event.user.bot_account?
      next
    end
    event.send_message "```python\n" +
        "**@BuddyBot** to the rescue!\n\nI help managing #GFRIEND. My creator is @AnhNhan (stan Yerin!), send him a message if I don't behave.\n\n" +
        "I will help making sure you are assigned the right bias in #whos_your_bias, just shout your bias(es)' name(es) and watch the magic happen!\n\n" +
        "Note that I also keep watch for people having a bias outside of #GFRIEND, and show them their place on this server. Repeat offenders will be brought to justice by spanking them!\n\n" +
        "Additional available roles: BuddyTV, BuddyCraft and KARAOKE.\n\n" +
        "**Supported commands**\n" +
        "  **!primary <member>**     Replaces your primary bias with the chosen member. \n" +
        "                            Do note that the mods may issue capital punishment \n" +
        "                            if the motivation is light of heart.\n\n" +
        "  **!suggest-bias**         ( ͡° ͜ʖ ͡°).\n\n" +
        "  **!remove**               Removes a bias.\n\n" +
        "  **!remove-all**           Removes all biases. You will have to start deciding \n" +
        "                            again who you stan and in which order.\n\n" +
        "  **!help** / **!commands** Displays this help. It cures cancer and brings world peace.\n" +
        "```\n"
  end

  # tells everybody how long the bot has been running. also tells everybody when I last restarted the bot.
  message(content: "!uptime") do |event|
    pid = Process.pid
    uptime = `ps -p #{pid} -o etime=`
    event.respond "I have been running for exactly **#{uptime.strip}**, and counting!"
  end

  message(start_with: "!sigh") do |event|
    BuddyBot.only_creator(event.user) {
      name = "Yerin"
      data = event.content.scan(/^!sigh\s+(.*?)\s*$/i)[0]
      if data
        name = data[0]
      end
      event.respond "_\\*sigh\\* #{name} is so beautiful~_"
      event.message.delete()
    }
  end

  message(start_with: "!say") do |event|
    BuddyBot.only_creator(event.user) {
      data = event.content.scan(/^!say\s+((\d+)\s+(.*?))\s*$/i)[0]
      if !data
        event.respond "Input not accepted!"
        break
      end
      Discordrb::Channel.new(data[1], event.bot, event.server).send_message data[2]
    }
  end

  message(content: "!reload-configs") do |event|
    BuddyBot.only_creator(event.user) {
      self.log "'#{event.user.name}' just requested a config reload!", event.bot
      self.scan_bot_files()
      BuddyBot.build_emoji_map(event.bot.servers)
      event.respond "Done! Hopefully..."
    }
  end

  message(content: "!reload-message-counts") do |event|
    BuddyBot.only_creator(event.user) {
      self.log "'#{event.user.name}' just requested a member message count reload!", event.bot
      self.scan_member_message_counts()
      event.respond "Done! Hopefully..."
    }
  end

  message(content: "!save-message-counts") do |event|
    BuddyBot.only_creator(event.user) {
      self.log "'#{event.user.name}' just requested a member message count persist!", event.bot
      self.persist_member_message_counts()
      event.respond "Done! Hopefully..."
    }
  end

  message(content: "!print-message-counts") do |event|
    BuddyBot.only_creator(event.user) {
      self.log "'#{event.user.name}' just requested a member message count print-out on '#{event.server.name}' - '##{event.channel.name}'!", event.bot
      event.respond "Current messages counted at #{@@global_counted_messages}"
      event.respond YAML.dump(@@member_message_counts)
    }
  end

  # invoke this command if you want to e.g. add new audio clips or memes, but don't want to restart the bot. for now, you also have to invoke e.g. #audio-load manually afterwards.
  message(content: "!git-pull") do |event|
    BuddyBot.only_creator(event.user) {
      event.channel.split_send "Done.\n#{`cd #{BuddyBot.path} && git pull`}"
    }
  end

  message(content: "!print-role-lists") do |event|
    BuddyBot.only_creator(event.user) {
      event.bot.servers.each do |server_id, server|
        roles = server.roles.sort_by(&:position).map do |role|
          "`Role: #{role.position.to_s.rjust(2, "0")} - #{role.id} - #{role.name} - {#{role.colour.red}|#{role.colour.green}|#{role.colour.blue}} - #{if role.hoist then "hoist" else "dont-hoist" end}`\n"
        end.join
        self.log "**#{server.name}**\n#{roles}\n", event.bot
      end
    }
  end

  message(content: "!print-emoji-lists") do |event|
    BuddyBot.only_creator(event.user) {
      event.bot.servers.each do |server_id, server|
        self.log "**#{server.name}**\n", event.bot
        roles = server.emoji.map do |emoji_id, emoji|
          prefix = ""
          # if emoji.animated
          #   prefix = "a"
          # end
          "\\<#{prefix}:#{emoji.name}:#{emoji.id}> <#{prefix}:#{emoji.name}:#{emoji.id}>\n"
        end.each_slice(25)
        roles.each do |chunk|
          self.log chunk.join, event.bot
        end
      end
    }
  end

  # Trivia stuff

  # trivia-name => file path
  @@trivia_lists = {}

  # for later usage maybe...
  @@trivia_global_scoreboard = {}

  @@trivia_current_list_name = ""
  @@trivia_current_list_path = ""
  @@trivia_current_channel = nil
  @@trivia_current_question = ""
  # question => answers[]
  @@trivia_current_list = {}
  @@trivia_current_list_scoreboard = {}
  @@trivia_question_counter = 0

  def self.trivia_no_ongoing_game_msg(event)
    event.send_message "There is no ongoing trivia game... #{self.random_derp_emoji()}"
  end

  def self.trivia_game_running?()
    !@@trivia_current_list_name.empty?
  end

  message(content: "!bot-commands-only-test") do |event|
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      event.send_message "Pong!"
    }
  end

  message(content: "!trivia list") do |event|
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      event.send_message "The following trivias are available:\n```#{@@trivia_lists.keys.join(", ")}```"
    }
  end

  # score for the current game
  message(content: "!trivia score") do |event|
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      if !self.trivia_game_running?()
        self.trivia_no_ongoing_game_msg(event)
        next
      end
      event.send_message "Current score:\n```#{@@trivia_current_list_scoreboard}```"
    }
  end

  message(content: "!trivia stop") do |event|
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      if !self.trivia_game_running?()
        self.trivia_no_ongoing_game_msg(event)
        next
      end
      event.send_message "Stopping game for `#{@@trivia_current_list_name}`, no points will be awarded :sadeunha:... ~~not that we'd have actual score boards :SowonKek:~~"
      @@trivia_current_list_name = ""
      @@trivia_current_list_path = ""
      @@trivia_current_channel = nil
      @@trivia_current_question = ""
      @@trivia_current_list = {}
      @@trivia_current_list_scoreboard = {}
      @@trivia_question_counter = 0
    }
  end

  message(start_with: /^!trivia start\b/i) do |event|
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      if self.trivia_game_running?()
        event.send_message "There already is an ongoing game using the `#{@@trivia_current_list_name}` list... #{self.random_derp_emoji()}"
        next
      end

      data = event.content.scan(/^!trivia start\s+(.*?)\s*$/i)[0]
      if !data
        event.send_message "You need to specify a trivia list name... #{self.random_derp_emoji()}"
        next
      end

      trivia_list_name = data[0].downcase
      if !@@trivia_lists.include? trivia_list_name
        event.send_message "A list with the name #{trivia_list_name} does not exist... #{self.random_derp_emoji()}"
      end

      @@trivia_current_list_name = trivia_list_name
      @@trivia_current_list_path = @@trivia_lists[trivia_list_name]
      @@trivia_current_channel = event.channel
      @@trivia_current_list = self.parse_trivia_list(@@trivia_current_list_path)
      @@trivia_current_list_scoreboard = {}
      @@trivia_question_counter = 0

      event.send_message "Test: #{@@trivia_current_list}"

      self.trivia_choose_question()
      self.trivia_post_question()
    }
  end

  def self.trivia_post_question()
    @@trivia_current_channel.send_message "Question ##{@@trivia_question_counter}: **#{@@trivia_current_question}**"
  end

  def self.trivia_choose_question()
    @@trivia_current_question = @@trivia_current_list.keys.sample
    @@trivia_question_counter = @@trivia_question_counter + 1
  end

  # repeat question
  message(content: "!trivia repeat") do |event|
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      if !self.trivia_game_running?()
        self.trivia_no_ongoing_game_msg(event)
        next
      end
      self.trivia_post_question()
    }
  end

  # skip question... for now...
  message(content: "!trivia skip") do |event|
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      if !self.trivia_game_running?()
        self.trivia_no_ongoing_game_msg(event)
        next
      end
      self.trivia_choose_question()
      self.trivia_post_question()
    }
  end

  message() do |event|
    next unless event.server
    next unless self.trivia_game_running?()
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      # for now exact match
      if @@trivia_current_list[@@trivia_current_question].include? event.content
        event.send_message "Boo yeah!"
      end
    }
  end

  message(content: "!reload-trivia-lists") do |event|
    BuddyBot.only_creator(event.user) {
      self.log "'#{event.user.name}' just requested a trivia list reload!", event.bot
      self.scan_trivia_lists()
      event.respond "Done! Hopefully... (existing games are unaffected)"
    }
  end

  def self.scan_trivia_lists()
    @@trivia_lists = {}
    Dir.glob(BuddyBot.path("content/trivia/**/*.txt")).reject{ |file| [ ".", ",," ].include?(file) || File.directory?(file) }.each do |file|
      @@trivia_lists[File.basename(file, ".txt").downcase] = file
    end
  end

  def self.parse_trivia_list(path)
    lines = File.readlines(path)
    zip = lines.reject().map do |line|
      question, *answers = line.strip.split "`"
      [ question, answers ]
    end
    Hash[zip]
  end

end
