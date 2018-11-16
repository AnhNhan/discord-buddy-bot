
require 'discordrb'
require 'yaml'
require 'rufus-scheduler'

module BuddyBot::Modules::BuddyFunctionality
  extend Discordrb::EventContainer

  @@initialized = false
  @@is_crawler = false

  @@bot_owner_id = 0

  @@cleverbot = nil

  @@member_names = {}

  @@primary_role_names = []

  @@primary_ids = []

  @@special_members = {}

  @@members_of_other_groups = {}

  @@ignored_roles = []

  @@new_member_roles = {}

  @@bias_replacements = {}

  @@server_invite_bot_reject_active = false

  @@server_thresholds = {}
  @@server_threshold_remove_roles = {}
  @@server_threshold_remove_ignore = []
  @@server_threshold_ignore_channels = {}
  @@server_bot_commands = {}
  @@giveaway_channels = {}
  @@server_log_channels = {}
  @@server_moderator_roles = {}
  @@log_role_events = false

  @@global_counted_messages = 0
  @@member_message_counts = {}
  @@join_counter = {}

  @@member_role_emoji_join = {}
  @@member_role_emoji_leave = {}

  @@global_emoji_map = {}

  @@biasgame_easter_eggs = {}
  @@derp_faces = {}

  @@giveaways = {}
  @@giveaway_joins = {}
  @@global_counted_giveaway_joins = 0

  @@member_name_regex = /([A-z0-9\p{Katakana}\p{Hangul}]+)/

  @@scheduler = Rufus::Scheduler.new
  @@yerin_pic_spam_channel = 0

  @@mutex_roles = Mutex.new
  @@mutex_trivia = Mutex.new

  def self.scan_bot_files()
    member_config = YAML.load_file(BuddyBot.path("content/bot.yml"))

    @@member_names = member_config["member_names"]
    @@primary_role_names = member_config["primary_role_names"]
    @@primary_ids = member_config["primary_ids"]
    @@special_members = member_config["special_members"]
    @@members_of_other_groups = member_config["members_of_other_groups"]
    @@ignored_roles = member_config["ignored_roles"]
    @@new_member_roles = member_config["new_member_roles"]
    @@bias_replacements = member_config["bias_replacements"]
    @@server_invite_bot_reject_active = member_config["server_invite_bot_reject_active"]
    @@server_thresholds = member_config["server_thresholds"]
    @@server_threshold_remove_roles = member_config["server_threshold_remove_roles"]
    @@server_threshold_remove_ignore = member_config["server_threshold_remove_ignore"]
    @@server_threshold_ignore_channels = member_config["server_threshold_ignore_channels"]
    @@server_bot_commands = member_config["server_bot_commands"]
    @@giveaway_channels = member_config["giveaway_channels"]
    @@member_role_emoji_join = member_config["member_role_emoji_join"]
    @@member_role_emoji_leave = member_config["member_role_emoji_leave"]
    @@biasgame_easter_eggs = member_config["biasgame_easter_eggs"]
    @@derp_faces = member_config["derp_faces"]
    @@trivia_config_reveal_after = member_config["trivia_config_reveal_after"]
    @@bot_owner_id = member_config["bot_owner_id"]
    @@server_log_channels = member_config["server_log_channels"]
    @@log_role_events = member_config["log_role_events"]
    @@server_moderator_roles = member_config["server_moderator_roles"]
    @@yerin_pic_spam_channel = member_config["yerin_pic_spam_channel"]

    @@motd = File.readlines(BuddyBot.path("content/motds.txt")).map(&:strip)

    @@giveaways = YAML.load_file(BuddyBot.path("content/giveaways.yml"))
  end

  def self.scan_member_message_counts()
    @@member_message_counts = YAML.load_file(BuddyBot.path("content/member_message_counts.yml"))
    @@join_counter = YAML.load_file(BuddyBot.path("content/data-join-counter.yml"))
  end

  def self.persist_member_message_counts()
    File.open(BuddyBot.path("content/member_message_counts.yml"), "w") { |file| file.write(YAML.dump(@@member_message_counts)) }
    File.open(BuddyBot.path("content/data-join-counter.yml"), "w") { |file| file.write(YAML.dump(@@join_counter)) }
  end

  def self.scan_giveaway_joins()
    @@giveaway_joins = YAML.load_file(BuddyBot.path("content/giveaway-joins.yml"))
  end

  def self.persist_giveaway_joins()
    File.open(BuddyBot.path("content/giveaway-joins.yml"), "w") { |file| file.write(YAML.dump(@@giveaway_joins)) }
  end

  def self.set_cleverbot(bot)
    @@cleverbot = bot
    @@cleverbot.nick = "BuddyBot"
  end

  def self.activate_crawler_mode()
    @@is_crawler = true
  end

  def self.is_mod?(server, user)
    member = user.on server
    mod_role_match = @@server_moderator_roles.has_key?(server.id) && member.roles.find{ |role| @@server_moderator_roles[server.id].include?(role.id) }
    mod_role_match || user.id.eql?(@@bot_owner_id)
  end

  def self.only_mods(server, user, &cb)
    if self.is_mod? server, user
      cb.call
    end
  end

  def self.log(msg, bot, server = nil)
    msg.scan(/.{1,2000}/m).map do |chunk|
      # buddy bot log on anh-test
      begin
        bot.send_message (if server && @@server_log_channels[server.id] then @@server_log_channels[server.id] else 189800756403109889 end), chunk
      rescue
        # do nothing
      end
    end
  end

  def self.log_roles(msg, bot, server = nil)
    return if !@@log_role_events
    self.log(msg, bot, server)
  end

  def self.find_emoji(input)
    input.downcase.scan(/([A-z6]+)/).select{ |part| @@member_role_emoji_join.include?(part.first) }.flatten
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
      match = role.name.downcase.scan(@@member_name_regex).find{ |part| searches.include?(part.first) }
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
    text.scan(@@member_name_regex).map do |matches|
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
      " - #{self.resolve_bias_replacement(name).capitalize} (#{@@members_of_other_groups[name].sample})"
    end.join "\n"
    event.send_message ":warning: #{BuddyBot.emoji(434376562142478367)} The following idol#{if rejected_names.length > 1 then 's do' else ' does' end} not belong to \#Godfriend. Officials have been alerted and now are on the search for you.\n#{rejected_names_text}"
  end

  ready do |event|
    if not @@initialized
      self.scan_bot_files()
      if !@@is_crawler
        self.scan_member_message_counts()
        self.scan_giveaway_joins()
        self.scan_trivia_lists()
      end
      # event.bot.profile.avatar = open("GFRIEND-NAVILLERA-Lyrics.jpg")

      if event.bot.profile.id == 168796631137910784
        @@scheduler.every '20m' do
          yerinpics_root = BuddyBot.path("content/yerinpics/")
          selected_file = `cd /; find #{yerinpics_root} ~/gdrive/GFriend/Yerin/ -type f | grep -v .gitkeep | shuf -n1`
          selected_file = selected_file.sub /\n/, ""
          self.log ":information_desk_person: `#{Time.now}` Sending `#{selected_file}` to <##{@@yerin_pic_spam_channel}>.", event.bot, Struct.new(:id).new(468731351374364672)
          event.bot.send_file @@yerin_pic_spam_channel, File.open(selected_file, "r")
        end
      end

      @@initialized = true
    end
    BuddyBot.build_emoji_map(event.bot.servers)
    event.bot.game = @@motd.sample

    self.log "ready!", event.bot
  end

  message(start_with: /^!motd/) do |event|
    event.bot.game = @@motd.sample
  end

  member_join do |event|
    next if @@is_crawler
    server = event.server
    member = event.user.on(server)
    begin
      if @@server_invite_bot_reject_active
        if member.username =~ /discord\.gg[\/\\]\S+/i
          member.pm "Hello, welcome to the GFriend Discord server!\n" +
                        "I'm afraid that your username resembles a Discord invite link,\n" +
                        "which the mod team regards to be spam.\n" +
                        "If you are indeed a human, you are free to join with a different username.\n\n"
          member.pm BuddyBot.emoji(472108548810342410)
          member.pm "- BuddyBot"
          server.kick member
        end
      end
    end
    begin
      if !@@new_member_roles.include? server.id
        self.log "A user joined #{server.name} \##{server.id} but the bot does not have a config for the server.", event.bot, server
        next
      end
      role_ids = @@new_member_roles[server.id]
      roles = role_ids.map do |role_id|
        server.role role_id
      end
      member.roles = roles
      self.log "<:yerinpeekwave:442204826269515776> User joined: '`#{event.user.username}` - #{event.user.mention}'; adding roles '#{roles.map(&:name).join(', ')}'", event.bot, server
      if @@member_message_counts.include?(event.user.id)
        self.log "<:eunhashock:434376562142478367> User had previous record in new member counting, deleting: '`#{event.user.username}` - \##{event.user.id}'", event.bot, server
        @@member_message_counts.delete(event.user.id)
      end
      if server.id == 468731351374364672 # yerin pic spam
        event.bot.send_message @@yerin_pic_spam_channel, "#{event.user.mention} :sujipraise: Thanks for subscribing to the Yerin pic spam!"
      else
        server.general_channel.send_message "#{event.user.mention} joined! " +
          "Welcome to the GFriend Discord server! Please make sure to read the " +
          "rules in <#290827788016156674>. You can pick a bias in <#166340324355080193>. " +
          "_Do note new members are blocked from posting pictures and embeds for a limited amount of time._"
      end
    rescue
    end
  end

  member_leave do |event|
    next if @@is_crawler
    begin
      if @@server_invite_bot_reject_active
        if event.user.username =~ /discord\.gg[\/\\]\S+/i
          self.log "<:eunhashock:434376562142478367> User got rejected: '#{event.server.name}' - '`#{event.user.username}` - #{event.user.mention}'", event.bot, event.server
          next
        end
      end
    end
    self.log "<:yerinzzz:471761896115011585> User left: '#{event.server.name}' - '`#{event.user.username}` - #{event.user.mention}'", event.bot, event.server
  end

  # biasgame easter egg
  message(from: 283848369250500608, contains: /(GFriend \w+? vs|vs GFriend \w+?\b|Winner: GFriend \w+?!)/) do |event|
    next unless [ 318787939360571393, 492785764493557764 ].include? event.channel.id
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
    next if @@is_crawler
    server = event.server
    if server.nil? || event.user.nil? || event.user.bot_account? || !@@server_threshold_remove_roles.include?(server.id) || !@@server_thresholds.include?(server.id)
      next
    end
    next if @@server_threshold_remove_ignore.include? event.user.id

    if @@server_threshold_ignore_channels.include?(server.id) && @@server_threshold_ignore_channels[server.id].include?(event.channel.id)
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
      self.log "Upgraded '#{event.user.username} - \##{event.user.id}' to a normal user", event.bot, event.server
    end

    # save every five messages
    if @@global_counted_messages % 5 == 0
      # @@global_counted_messages = 0 # prevent overflow from long running counting
      self.persist_member_message_counts()
    end
  end

  # talk with BuddyBot
  mention() do |event|
    next if @@is_crawler
    next if event.user.bot_account?
    next if @@cleverbot.nil?
    next if event.content.nil? || event.content.empty?
    event.channel.start_typing
    event.send_message @@cleverbot.say(event.content)
  end

  message(start_with: /^!suggest-bias\s*/i, in: "whos-your-bias") do |event|
    next if @@is_crawler
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot, event.server
    end
    if event.user.bot_account?
      next
    end
    user = event.user.on event.server
    event.send_message "#{user.mention} My dice says **#{["Yerin", "Yuju", "SinB", "Umji", "Sowon", "Eunha"].sample}**!"
  end

  def self.prepare_bias_replacement(text)
    if @@bias_replacements.length
      @@bias_replacements.each do |replacement, needle|
        text = text.gsub /\b#{Regexp.quote(needle)}\b/i, replacement.downcase
      end
    end
    return text
  end

  def self.resolve_bias_replacement(text)
    @@bias_replacements[text] || text
  end

  message(in: "whos-your-bias") do |event|
    next if @@is_crawler
    text = event.content
    if text =~ /^!(remove|primary|suggest)/i
      next
    end
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot, event.server
    end
    if event.user.bot_account?
      next
    end
    @@mutex_roles.synchronize do
      event.server.delete_member(event.user.id)
      user = event.user.on event.server
      added_roles = []
      rejected_names = []
      added_ot6 = false
      current_primary_roles = user.roles.find_all{ |role| self.role_is_primary(role) }
      ot6_role = self.find_roles(event.server, 'ot6', true).first
      has_ot6_primary = current_primary_roles.find{ |current_role| current_role.id == ot6_role.id }
      has_non_ot6_primary = current_primary_roles.find{ |current_role| current_role.id != ot6_role.id }

      if text =~ /^!(secondary|bias|add) /i
        event.send_message "#{user.mention} you do not need to provide the `!secondary` / `!bias` command."
      end

      if text =~ /\bot6\b/i
        if current_primary_roles.length > 0 && !has_ot6_primary && has_non_ot6_primary
          event.send_message "You wanted OT6 but you already have a primary role. Please note that you have to explicitly specify `!primary OT6` to receive it as a primary."
        elsif !has_ot6_primary
          user.add_role ot6_role
          self.log_roles "Added role '#{ot6_role.name}' to '#{user.name}'", event.bot, event.server
          added_roles << "**#{ot6_role.name}**"
          added_ot6 = true
        end
        # we only handle ot6 up here
        text = text.gsub /\bot6\b/i, ""
      end

      text = self.prepare_bias_replacement(text)

      cb_member = lambda do |match, original|
        member_name = @@member_names[match]
        roles = self.find_roles event.server, member_name, self.determine_requesting_primary(user, member_name)
        if roles.find{ |role| user.role? role }
          next
        end
        user.add_role roles
        roles.map do |role|
          added_roles << "**#{role.name}**" + if !self.resolve_bias_replacement(match).eql? member_name then " _(#{original})_" else "" end
          self.log_roles "Added role '#{role.name}' to '#{user.name}'", event.bot, event.server
        end
      end
      cb_other_member = lambda do |match, original|
        rejected_names << match
      end
      cb_special = lambda do |match, original, user_id|
        # for now disabled
        # member = event.server.member(user_id)
        # event.send_message "Hey **@#{member.nick || member.username}**, lookie lookie super lookie! You have an admirer!"
      end
      self.members_map(text, cb_member, cb_other_member, cb_special)

      if !added_roles.empty?
        added_roles_text = added_roles.join ", "
        event.send_message "#{user.mention} your bias#{if added_roles.length > 1 then 'es' end} #{added_roles_text} #{if added_roles.length > 1 then 'have' else 'has' end} been added"
        if added_ot6 && added_roles.length > 1
          event.send_message "Do note that OT6 has been added as a primary and any further bias has been added as a secondary."
        end
      end
      if !rejected_names.empty?
        self.print_rejected_names rejected_names, event
      end
    end
  end

  message(start_with: /^!primary\s*/i, in: "whos-your-bias") do |event|
    next if @@is_crawler
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot, event.server
    end
    if event.user.bot_account?
      next
    end
    data = event.content.scan(/^!primary\s+(.*?)\s*$/i)[0]
    if data
      data = data[0].downcase
      @@mutex_roles.synchronize do
        event.server.delete_member(event.user.id)
        user = event.user.on event.server
        removed_roles = []
        added_roles = []

        data = self.prepare_bias_replacement(data)

        if !(@@primary_role_names.include?(data) || (@@member_names.include?(data) && @@primary_role_names.include?(@@member_names[data])))
          event.send_message "#{user.mention} you didn't give me a possible primary bias"
          next
        end

        current_primary_roles = user.roles.find_all{ |role| self.role_is_primary(role) }
        member_name = @@member_names[data]
        role = self.find_roles(event.server, member_name, true).first
        if !role
          self.log "Primary role with name '#{member_name}' not found on server '#{event.server.name}', stale config?", event.bot, event.server
          next
        end

        if current_primary_roles.find{ |current_role| current_role.id == role.id }
          event.send_message "You can't hop to your current primary bias #{self.random_derp_emoji()}"
          if current_primary_roles.length > 1
            event.send_message "Do note that you have _multiple_ primary biases. If you are not satisfied with your current color you might consider to `!remove #{current_primary_roles.find_all{ |current_role| current_role.id != role.id }.map(&:name).join(" ")}` #{BuddyBot.emoji(342101928903442432)}"
          end
          next
        end

        event.channel.start_typing

        current_primary_roles.map do |current_primary_role|
          removed_roles << "**#{current_primary_role.name}**"
          user.remove_role current_primary_role
          puts " - removed role '#{current_primary_role.name}'"
          self.log_roles "Removed role '#{current_primary_role.name}' from '#{user.name}'", event.bot, event.server
        end

        user.add_role role
        puts "+  role '#{role.name}'"
        added_roles << "**#{role.name}**"
        self.log_roles "Added role '#{role.name}' to '#{user.name}'", event.bot, event.server

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
      end
    end
  end

  message(start_with: /^!remove\s+/i, in: "whos-your-bias") do |event|
    next if @@is_crawler
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot, event.server
    end
    if event.user.bot_account?
      next
    end
    data = event.content.scan(/^!remove\s+(.*?)\s*$/i)[0]
    if data
      data = data[0]
      @@mutex_roles.synchronize do
        event.server.delete_member(event.user.id)
        user = event.user.on event.server
        rejected_names = []
        removed_roles = []
        data = self.prepare_bias_replacement(data)
        cb_member = lambda do |match, original|
          if match.eql? "buddy" # don't remove buddy role
            next
          end
          member_name = @@member_names[match]
          role = self.find_roles event.server, member_name, true
          role = role + (self.find_roles event.server, member_name, false)
          role.map do |role|
            next unless user.role?(role.id)
            user.remove_role role
            removed_roles << "**#{role.name}**" + if !self.resolve_bias_replacement(match).eql? member_name then " _(#{original})_" else "" end
            self.log_roles "Removed role '#{role.name}' from '#{event.user.name}'", event.bot, event.server
          end
        end
        cb_other_member = lambda do |match, original|
          rejected_names << match
          self.log_roles "Warning, '#{event.user.name}' requested to remove '#{match}'.", event.bot, event.server
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
      end
    end
  end

  message(content: ["!remove-all"]) do |event|
    next if @@is_crawler
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot, event.server
    end
    if event.user.bot_account?
      next
    end
    self.log_roles "Remove-All attempt by '#{event.user.username} - \##{event.user.id}'", event.bot, event.server
    @@mutex_roles.synchronize do
      event.server.delete_member(event.user.id)
      user = event.user.on event.server
      removed_roles = []
      main_roles = user.roles.find_all do |role|
        if @@ignored_roles.include? role.name
          next
        end
        role.name.downcase.scan(/([A-z0-6]+)/).find do |matches|
          @@primary_role_names.include? matches.first
        end
      end

      main_roles.map do |role|
        if not user.role? role
          next
        end
        user.remove_role role
        removed_roles << "**#{role.name}**"
        self.log_roles "Removed role '#{role.name}' from '#{event.user.name}'", event.bot, event.server
      end
      if !removed_roles.empty?
        removed_roles_text = removed_roles.join ", "
        event.send_message "#{user.mention} removed bias#{if removed_roles.length > 1 then 'es' end} #{removed_roles_text}"
      end
    end
  end

  message(content: ["!help", "!commands"]) do |event|
    next if @@is_crawler
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
        "  **!help** / **!commands** Displays this help. It cures cancer and brings world peace.\n\n" +
        "Did you know? I also help managing giveaways!\n" +
        "  **!giveaway list**        Show available giveaways\n" +
        "  **!giveaway join <name>   Join an active giveaway - **please do this in #bot-commands**\n" +
        "```\n"
  end

  # tells everybody how long the bot has been running. also tells everybody when I last restarted the bot.
  message(content: "!uptime") do |event|
    next unless !event.user.bot_account?
    pid = Process.pid
    uptime = `ps -p #{pid} -o etime=`
    event.respond "I have been running for exactly **#{uptime.strip}**, and counting!"
  end

  message(start_with: "!sigh") do |event|
    next if @@is_crawler
    self.only_mods(event.server, event.user) {
      name = "Yerin"
      emoji = "<:yerinlove:437006461751656470>"
      data = event.content.scan(/^!sigh\s+(.*?)\s*$/i)[0]
      if data
        name = data[0]
      end
      name = name.strip
      if !name.downcase.eql? "yerin"
        emoji = ""
      end
      event.respond "_\\*sigh\\* #{name} is so beautiful~_ #{emoji}"
      event.message.delete()
    }
  end

  message(start_with: "!say") do |event|
    next if @@is_crawler
    self.only_mods(event.server, event.user) {
      data = event.content.scan(/^!say\s+((\d+)\s+(.*?))\s*$/i)[0]
      if !data
        event.respond "Input not accepted!"
        break
      end
      self.log "'#{event.user.name}' just said something in <##{data[1]}>!", event.bot, event.server
      event.bot.send_message data[1], data[2]
    }
  end

  message(content: "!reload-configs") do |event|
    self.only_mods(event.server, event.user) {
      self.log "'#{event.user.name}' just requested a config reload!", event.bot, event.server
      self.scan_bot_files()
      BuddyBot.build_emoji_map(event.bot.servers)
      event.respond "Done! Hopefully..."
    }
  end

  message(content: "!reload-message-counts") do |event|
    next if @@is_crawler
    self.only_mods(event.server, event.user) {
      self.log "'#{event.user.name}' just requested a dynamic data reload!", event.bot, event.server
      self.scan_member_message_counts()
      self.scan_giveaway_joins()
      event.respond "Done! Hopefully..."
    }
  end

  message(content: "!save-all") do |event|
    next if @@is_crawler
    self.only_mods(event.server, event.user) {
      self.log "'#{event.user.name}' just requested a dynamic data persist!", event.bot, event.server
      self.persist_member_message_counts()
      self.persist_giveaway_joins
      event.respond "Done! Hopefully..."
    }
  end

  message(content: "!print-message-counts") do |event|
    next if @@is_crawler
    self.only_mods(event.server, event.user) {
      self.log "'#{event.user.name}' just requested a member message count print-out on '#{event.server.name}' - '##{event.channel.name}'!", event.bot, event.server
      event.respond "Current messages counted at #{@@global_counted_messages}"
      event.respond YAML.dump(@@member_message_counts)
    }
  end

  # invoke this command if you want to e.g. add new audio clips or memes, but don't want to restart the bot. for now, you also have to invoke e.g. #audio-load manually afterwards.
  message(content: "!git-pull") do |event|
    self.only_mods(event.server, event.user) {
      event.channel.split_send "Done.\n#{`cd #{BuddyBot.path} && git pull`}"
    }
  end

  message(content: "!print-role-lists") do |event|
    next if @@is_crawler
    self.only_mods(event.server, event.user) {
      event.bot.servers.each do |server_id, server|
        roles = server.roles.sort_by(&:position).map do |role|
          "`Role: #{role.position.to_s.rjust(2, "0")} - #{role.id} - #{role.name} - {#{role.colour.red}|#{role.colour.green}|#{role.colour.blue}} - #{if role.hoist then "hoist" else "dont-hoist" end} - #{if @@primary_ids.include?(role.id) then "primary" else "secondary" end}`\n"
        end.join
        self.log "**#{server.name}**\n#{roles}\n", event.bot, event.server
      end
    }
  end

  message(content: "!print-emoji-lists") do |event|
    next if @@is_crawler
    self.only_mods(event.server, event.user) {
      event.bot.servers.each do |server_id, server|
        self.log "**#{server.name}**\n", event.bot, event.server
        roles = server.emoji.map do |emoji_id, emoji|
          "`< :#{emoji.name}: - #{emoji.id} >` <:#{emoji.name}:#{emoji.id}>\n"
        end.each_slice(25)
        roles.each do |chunk|
          self.log chunk.join, event.bot, event.server
        end
      end
    }
  end

  message(content: "!fix-gfcord-non-buddies") do |event|
    next if @@is_crawler
    self.only_mods(event.server, event.user) {
      event.bot.servers.each do |server_id, server|
        if server_id != 166304074252288000 # gfcord only
          next
        end

        server.members.each do |member|
          if member.roles.find {|role| role.id == 166339124129693696 } # check for buddy role
            next
          end

          # explicitly only add buddy role, not all new roles
          member.add_role 166339124129693696

          self.log "Fix roles: Added roles '#{server.role(166339124129693696).name}' to '#{member.username} - \##{member.id}'", event.bot, event.server

          # No belated greeting per server mods
        end
      end
    }
  end

  message(content: "!fix-gfcord-non-buddies-new") do |event|
    next if @@is_crawler
    self.only_mods(event.server, event.user) {
      event.bot.servers.each do |server_id, server|
        if server_id != 166304074252288000 # gfcord only
          next
        end

        server.members.each do |member|
          if member.roles.find {|role| role.id == 166339124129693696 } # check for buddy role
            next
          end

          member.add_role 166339124129693696
          member.add_role 430593431195353088

          self.log "Fix roles: Added roles '#{server.role(430593431195353088).name}, #{server.role(166339124129693696).name}' to '#{member.username} - \##{member.id}'", event.bot, event.server

          # No belated greeting per server mods
        end
      end
    }
  end

  message(content: "!list-gfcord-non-buddies") do |event|
    next if @@is_crawler
    self.only_mods(event.server, event.user) {
      event.bot.servers.each do |server_id, server|
        if server_id != 166304074252288000 # gfcord only
          next
        end

        role_ids = @@new_member_roles[server.id]
        roles = role_ids.map do |role_id|
          server.role role_id
        end
        members = server.members.find_all do |member|
          !member.roles.find {|role| role.id == 166339124129693696 }
        end

        self.log "Members without Buddy for #{server.name}: #{members.map{|member| member.username + (if member.nick then ' aka ' + member.nick else '' end) + ' (' + member.id.to_s + ', joined ' + member.joined_at.to_s + ')'}}", event.bot, event.server
      end
    }
  end

  # Giveaway stuff
  @@giveaway_emote_id = 472108548810342410

  def self.format_giveaway(giveaway_list_name, server)
    "Giveaway #**#{giveaway_list_name}** - use the #{BuddyBot.emoji(@@giveaway_emote_id)} reaction to join the draw!\n" +
      "Subject: **#{@@giveaways[giveaway_list_name]['subject']}**\n" +
      "Restrictions: #{@@giveaways[giveaway_list_name]['restrictions']}\n" +
      "Responsible: **<#{@@giveaways[giveaway_list_name]['responsible_name']}>**\n" +
      "Giveaway end: #{@@giveaways[giveaway_list_name]['join_end'].utc}\n" +
      "**Disclaimer: It is not subject to legal recourse. We are some random dudes on the internet and can't be held liable. Please don't trust us about anything**"
  end

  message(content: "!giveaway list") do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      if @@giveaways.length
        @@giveaways.keys.reject{ |giveaway_list_name| @@giveaways[giveaway_list_name]['join_end'].utc < Time.now.utc }.map{ |giveaway_list_name| self.format_giveaway(giveaway_list_name, event.server) }.each { |giveaway| event.user.pm(giveaway) }
        event.send_message "#{event.user.mention} please check your DMs!"
      else
        event.send_message "No ongoing giveaways...  #{self.random_derp_emoji()}"
      end
    }
  end

  message(content: "!giveaway status") do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
    next unless event.server
    self.only_mods(event.server, event.user) {
      BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
        if @@giveaway_joins.length
          event.send_message "#{@@giveaway_joins}"
        else
          event.send_message "No ongoing giveaways...  #{self.random_derp_emoji()}"
        end
      }
    }
  end

  message(start_with: "!giveaway announce ") do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
    next unless event.server
    self.only_mods(event.server, event.user) {
      BuddyBot.only_channels(event.channel, @@giveaway_channels[event.server.id]) {
        if @@giveaways.length
          data = event.content.scan(/^!giveaway announce\s+(.*?)\s*$/i)[0]
          if !data
            event.send_message "You need to specify a giveaway list name... #{self.random_derp_emoji()}"
            next
          end

          giveaway_list_name = data[0].downcase
          if !@@giveaways.include? giveaway_list_name
            event.send_message "A list with the name #{giveaway_list_name} does not exist... #{self.random_derp_emoji()}"
            next
          end

          msg = event.send_message self.format_giveaway(giveaway_list_name, event.server)
          msg.create_reaction BuddyBot.emoji(@@giveaway_emote_id)
          if @@giveaways.values.reject{ |giveaway| giveaway['join_end'].utc < Time.now.utc }.length > 1
            event.send_message "Hold up, there's more than one giveaway going on 👀. Use `!giveaway list` in #{@@server_bot_commands[event.server.id].map{|channel_id| '<#' + channel_id.to_s + '>' }.join(' or ')} to know more about them!"
          end
          event.message.delete()
        else
          event.send_message "No ongoing giveaways...  #{self.random_derp_emoji()}"
        end
      }
    }
  end

  message(start_with: "!giveaway draw ") do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
    next unless event.server
    self.only_mods(event.server, event.user) {
      BuddyBot.only_channels(event.channel, @@giveaway_channels[event.server.id]) {
        if @@giveaways.length
          data = event.content.scan(/^!giveaway draw\s+(.*?)\s+(\d{18})\s*$/i)[0]
          if !data
            event.send_message "You need to specify a giveaway list name... #{self.random_derp_emoji()}"
            next
          end

          giveaway_list_name = data[0].downcase
          announce_message_id = data[1].to_i
          if !@@giveaways.include? giveaway_list_name
            event.send_message "A list with the name #{giveaway_list_name} does not exist... #{self.random_derp_emoji()}"
            next
          end

          if @@giveaways[giveaway_list_name]['join_end'].utc > Time.now.utc
            event.send_message "Giveaway '**#{giveaway_list_name}** - #{@@giveaways[giveaway_list_name]['subject']}' did not end yet #{self.random_derp_emoji()}"
            next
          end

          announce_message_object = Discordrb::Message.new(JSON.parse(Discordrb::API::Channel.message(event.bot.token, event.channel.id, announce_message_id)), event.bot)
          reactions_list = announce_message_object.reacted_with(BuddyBot.emoji(@@giveaway_emote_id)).reject(&:bot_account)

          if !reactions_list || reactions_list.length == 0
            event.send_message "No members entered the giveaway #{self.random_derp_emoji()}"
            next
          end

          winner = reactions_list.sample
          self.log ":tada: Winner decided for giveaway '#{giveaway_list_name}' by '#{event.user.username}' / '#{event.user.nick}' / #{event.user.id} ----- it's '`#{winner.username}##{winner.discriminator}` - #{winner.mention}'", event.bot, event.server

          event.message.delete()

          event.send_message "_\*drum roll\*_"
          event.channel.start_typing
          sleep(2)
          event.send_message "_staring at #{reactions_list.length} people..._"
          sleep(2)
          event.send_message "_and only one can win..._"
          event.channel.start_typing
          sleep(2)
          event.send_message "The lucky winner of '#{giveaway_list_name} - #{@@giveaways[giveaway_list_name]['subject']}'..."
          sleep(2)
          event.send_message "is ..."
          event.channel.start_typing
          sleep(6)
          event.send_message ":tada: :confetti_ball: #{winner.mention} :confetti_ball: :tada:"
          sleep(2)
          event.send_message "<@#{@@giveaways[giveaway_list_name]['responsible_id']}> fyi"
          self.log ":eunhapeek: Deleted announcement message for giveaway `#{giveaway_list_name}`"
          announce_message_object.delete()
        else
          event.send_message "No ongoing giveaways...  #{self.random_derp_emoji()}"
        end
      }
    }
  end

  # Trivia stuff

  # trivia-name => file path
  @@trivia_lists = {}

  # for later usage maybe...
  @@trivia_global_scoreboard = {}

  @@trivia_config_reveal_after = 0

  @@trivia_current_list_name = ""
  @@trivia_current_list_path = ""
  @@trivia_current_channel = nil
  @@trivia_current_question = ""
  # question => answers[]
  @@trivia_current_list = {}
  @@trivia_current_matchers = {}
  @@trivia_current_list_scoreboard = {}
  @@trivia_current_question_counter = 0
  @@trivia_current_question_time = 0 # the time at which the question was issued

  # :(
  @@trivia_user_map = {}

  def self.trivia_no_ongoing_game_msg(event)
    event.send_message "There is no ongoing trivia game... #{self.random_derp_emoji()}"
  end

  def self.trivia_game_running?()
    !@@trivia_current_list_name.empty?
  end

  def self.scan_trivia_lists()
    @@trivia_lists = {}
    Dir.glob(BuddyBot.path("content/trivia/**/*.txt")).reject{ |file| [ ".", ",," ].include?(file) || File.directory?(file) }.each do |file|
      @@trivia_lists[File.basename(file, ".txt").downcase] = file
    end
  end

  def self.parse_trivia_list(path)
    lines = File.readlines(path)
    zip = lines.map(&:strip).reject{|line| line.empty? || line.start_with?('#') || !line.include?('`')}.map do |line|
      question, *answers = line.split "`"
      [ question, answers ]
    end
    Hash[zip]
  end

  def self.trivia_reset_game(event)
    @@trivia_current_list_name = ""
    @@trivia_current_list_path = ""
    @@trivia_current_channel = nil
    @@trivia_current_question = ""
    @@trivia_current_list = {}
    @@trivia_current_list_scoreboard = {}
    @@trivia_current_matchers = {}
    @@trivia_current_question_counter = 0
    @@trivia_current_question_time = 0
    @@trivia_user_map = {}
  end

  def self.trivia_print_score_list(event)
    message = "**Trivia score board:**\n```"
    @@trivia_current_list_scoreboard.each do |user_id, count|
      user = @@trivia_user_map[user_id]
      message << " '#{user.nick || user.username}': #{count}"
    end
    message << "```"
    event.send_message message
  end

  message(content: "!reload-trivia-lists") do |event|
    next if @@is_crawler
    self.only_mods(event.server, event.user) {
      self.log "'#{event.user.name}' just requested a trivia list reload!", event.bot, event.server
      self.scan_trivia_lists()
      event.respond "Done! Hopefully... (existing games are unaffected)"
    }
  end

  message(content: "!bot-commands-only-test") do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      event.send_message "Pong!"
    }
  end

  message(content: "!trivia list") do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      event.send_message "The following trivias are available:\n```#{@@trivia_lists.keys.join(", ")}```"
    }
  end

  # score for the current game
  message(content: "!trivia score") do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      if !self.trivia_game_running?()
        self.trivia_no_ongoing_game_msg(event)
        next
      end
      self.trivia_print_score_list(event)
    }
  end

  # repeat question
  message(content: "!trivia repeat") do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
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
    next if @@is_crawler
    next unless !event.user.bot_account?
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

  # spoil the game for all
  message(content: "!trivia reveal") do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      if !self.trivia_game_running?()
        self.trivia_no_ongoing_game_msg(event)
        next
      end
      time_diff = 0
      if (time_diff = Time.now.getutc.to_i - @@trivia_current_question_time) < @@trivia_config_reveal_after
        event.send_message "Please wait another #{time_diff} seconds until revealing the answer... #{self.random_derp_emoji()}"
        next
      end
      event.send_message "The answer would have been '**#{@@trivia_current_list[@@trivia_current_question].sample}**'! No point has been awarded for this question... #{self.random_derp_emoji()}"
      @@trivia_current_list.delete @@trivia_current_question
      self.trivia_choose_question()
      self.trivia_post_question()
    }
  end

  message(content: "!trivia stop") do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
    next unless event.server
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      if !self.trivia_game_running?()
        self.trivia_no_ongoing_game_msg(event)
        next
      end
      event.send_message "Stopping game for `#{@@trivia_current_list_name}`, no points will be awarded :sadeunha:... ~~not that we'd have actual score boards :SowonKek:~~"
      self.trivia_reset_game(event)
    }
  end

  message(start_with: /^!trivia start\b/i) do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
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
        next
      end

      self.trivia_reset_game(event)
      @@trivia_current_list_name = trivia_list_name
      @@trivia_current_list_path = @@trivia_lists[trivia_list_name]
      @@trivia_current_channel = event.channel
      @@trivia_current_list = self.parse_trivia_list(@@trivia_current_list_path)

      self.trivia_choose_question()
      self.trivia_post_question()
    }
  end

  def self.trivia_post_question()
    @@trivia_current_channel.send_message "Question ##{@@trivia_current_question_counter}: **#{@@trivia_current_question}**"
  end

  def self.trivia_choose_question()
    @@trivia_current_question = @@trivia_current_list.keys.sample
    @@trivia_current_question_counter = @@trivia_current_question_counter + 1
    @@trivia_current_matchers = self.build_matchers(@@trivia_current_question, @@trivia_current_list[@@trivia_current_question])
    @@trivia_current_question_time = Time.now.getutc.to_i
  end

  message() do |event|
    next if @@is_crawler
    next unless !event.user.bot_account?
    next unless event.server
    next unless self.trivia_game_running?()
    next unless event.content !~ /^[!_]\w/i # ignore robyul and buddy-bot commands
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      correct_answer = nil
      if correct_answer = @@trivia_current_matchers.find do |answer, matcher|
        matcher.call(event.content)
      end
        event.send_message "Boo yeah **#{event.user.nick || event.user.username}**! _'#{correct_answer[0]}'_ indeed."

        user_current_score = @@trivia_current_list_scoreboard[event.user.id] || 0
        user_current_score = user_current_score + 1
        @@trivia_current_list_scoreboard[event.user.id] = user_current_score
        @@trivia_user_map[event.user.id] = event.user

        @@trivia_current_list.delete @@trivia_current_question

        if @@trivia_current_list.empty?
          event.send_message "Game finished!"
          self.trivia_print_score_list(event)
          self.trivia_reset_game(event)
          next
        end

        self.trivia_choose_question()
        self.trivia_post_question()
      end
    }
  end

  def self.build_matchers(question, answers)
    matchers = answers.map do |answer|
      matcher = nil
      data = question.scan(/\s+\[(.*?)\]\s*$/i)[0] || []
      type, *typeargs = (data[0] || "default").downcase.split(",").map(&:strip)
      case type
      when "date"
      matcher = self.trivia_matcher_date(answer)
      when "year"
        matcher = self.trivia_matcher_year(answer)
      when "multiple"
        if typeargs.length < 1
          self.log "Question has insufficient typespec for multiple: '#{question}'", event.server
          next
        end
        matcher = self.trivia_matcher_multiple(answer, (typeargs[0] || 0).to_i)
      else
        matcher = self.trivia_matcher_default(answer)
      end
      [ answer, matcher ]
    end
    Hash[matchers]
  end

  def self.trivia_normalize(input)
    input.downcase.gsub /[\W_]+/, ""
  end

  def self.trivia_normalize_light(input)
    # only remove punctuation
    input.downcase.gsub /[,.\/\?<>;:'"=\-_\+\|\\\!@#\$%^&\*\(\)]+/, ""
  end

  def self.trivia_matcher_default(term)
    term_n = self.trivia_normalize(term)
    lambda do |input|
      input_n = self.trivia_normalize(input)
      input_n.include? term_n
    end
  end

  def self.trivia_matcher_year(term)
    term_n = self.trivia_normalize(term)
    lambda do |input|
      input_n = self.trivia_normalize(input).gsub /\D+/, ""
      if input_n.length > 1
        term_n =~ /#{Regexp.quote(input_n)}$/
      else
        false
      end
    end
  end

  # requires Y-M-D in N U M B E R S
  def self.trivia_matcher_date(term)
    year, month, day = term.split("-")

    months = [ "stub", "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december" ]
    months_short = months.map{|month| month[0..2]}
    formats = [
      "#{day}th #{months[month.to_i]} #{year[2,2]}",
      "#{day}th #{months[month.to_i]} #{year}",

      "#{day}th #{months_short[month.to_i]} #{year[2,2]}",
      "#{day}th #{months_short[month.to_i]} #{year}",

      "#{day}. #{months[month.to_i]} #{year[2,2]}",
      "#{day}. #{months[month.to_i]} #{year}",

      "#{day}. #{months_short[month.to_i]} #{year[2,2]}",
      "#{day}. #{months_short[month.to_i]} #{year}",

      "#{months[month.to_i]} #{day}th #{year[2,2]}",
      "#{months[month.to_i]} #{day}th #{year}",

      "#{months_short[month.to_i]} #{day}th #{year[2,2]}",
      "#{months_short[month.to_i]} #{day}th #{year}",

      "#{year}#{month}#{day}",
      "#{year[2,2]}#{month}#{day}",
    ]
    [ "-", ".", "/" ].each do |separator|
      [
        term,
        "#{year[2,2]}-#{month}-#{day}",
        "#{day}-#{month}-#{year[2,2]}",
        "#{day}-#{month}-#{year}",
      ].each do |format_base|
        formats << format_base.gsub("-", separator)
      end
    end
    formats = formats.uniq
    lambda do |input|
      formats.include? input.downcase.gsub(/[,!?]+/, "").gsub(/[ ]+/, " ")
    end
  end

  def self.trivia_matcher_multiple(term, count)
    separator_words = [ "and", "," ]
    terms = trivia_normalize_light(term.downcase).split.reject{ |term| separator_words.include? term }
    lambda do |input|
      matching_parts = trivia_normalize_light(input.downcase).split.select{ |part| terms.include? part }.uniq
      matching_parts.length >= count
    end
  end
end
