
require 'discordrb'
require 'yaml'

module BuddyBot::Modules::BuddyFunctionality
  extend Discordrb::EventContainer

  @@creator_id = 139342974776639489

  @@member_names = {}

  @@primary_role_names = []

  @@primary_ids = []

  @@special_members = {}

  @@members_of_other_groups = {}

  @@ignored_roles = []

  @@new_member_roles = {}

  @@server_thresholds = {}
  @@server_threshold_remove_roles = {}

  @@global_counted_messages = 0
  @@member_message_counts = {}

  def self.is_creator?(user)
    user.id.eql? @@creator_id
  end

  def self.only_creator(user, &cb)
    if self.is_creator? user
      cb.call
    else
      # event.respond "#{user.mention} you do not have permission to complete this command."
    end
  end

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
    self.scan_bot_files()
    self.scan_member_message_counts()
    # event.bot.profile.avatar = open("GFRIEND-NAVILLERA-Lyrics.jpg")
    # event.bot.game = @@motd.sample
    self.log "ready!", event.bot

    # event.bot.servers.each do |server_id, server|
    #   roles = server.roles.sort_by(&:position).map do |role|
    #     "`Role: #{role.position.to_s.rjust(2, "0")} - #{role.id} - #{role.name} - {#{role.colour.red}|#{role.colour.green}|#{role.colour.blue}} - #{if role.hoist then "hoist" else "dont-hoist" end}`\n"
    #   end.join
    #   self.log "**#{server.name}**\n#{roles}\n", event.bot
    # end
  end

  # message(start_with: /^!motd/) do |event|
  #   event.bot.game = @@motd.sample
  # end

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

  # new member counting
  message() do |event|
    server = event.server
    if event.user.nil? || event.user.bot_account? || !@@server_threshold_remove_roles.include?(server.id) || !@@server_thresholds.include?(server.id)
      next
    end
    user = event.user.on server

    remove_roles_ids = @@server_threshold_remove_roles[server.id]
    remove_threshold = @@server_thresholds[server.id]

    removable_roles = user.roles.find_all{ |role| remove_roles_ids.include?(role.id) }
    puts "Removable roles: #{removable_roles.map(&:name).join(", ")}"

    if !removable_roles.length
      next
    end

    if !@@member_message_counts.include?(user.id)
      @@member_message_counts[user.id] = {
        "count" => 0,
      }
    end

    current_entry = @@member_message_counts[user.id]
    @@member_message_counts[user.id] = {
      "count" => current_entry["count"] + 1
    }
    @@global_counted_messages = @@global_counted_messages + 1

    if @@global_counted_messages % 5 == 0
      # @@global_counted_messages = 0 # prevent overflow from long running counting
      self.persist_member_message_counts()
      self.log "Saved!", event.bot
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
    self.log "Primary switch attempt by #{event.user.mention}", event.bot
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

      current_primary_roles.map do |current_primary_role|
        removed_roles << "**#{current_primary_role.name}**"
        self.log "Removed role '#{current_primary_role.name}' from '#{event.user.name}'", event.bot
        user.remove_role current_primary_role
      end

      member_name = @@member_names[data]
      roles = self.find_roles event.server, member_name, true
      if roles
        user.add_role roles
        roles.map do |role|
          added_roles << "**#{role.name}**"
          self.log "Added role '#{role.name}' to '#{event.user.name}'", event.bot
        end
      end

      if !removed_roles.empty?
        removed_roles_text = removed_roles.join ", "
        event.send_message "#{user.mention} removed bias#{if removed_roles.length > 1 then 'es' end} #{removed_roles_text}"
      end
      if !added_roles.empty?
        added_roles_text = added_roles.join ", "
        event.send_message "#{user.mention} your primary bias has been changed to #{added_roles_text}"
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
    self.log "Remove attempt by #{event.user.mention}", event.bot
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
    self.log "Remove-All attempt by #{event.user.mention}", event.bot
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

    puts main_roles.map(&:name)

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
    self.only_creator(event.user) {
      name = "Yerin"
      data = event.content.scan(/^!sigh\s+(.*?)\s*$/i)[0]
      if data
        name = data[0]
      end
      event.respond "_\\*sigh\\* #{name} is so beautiful~_"
      event.message.delete()
    }
  end

  message(content: "!reload-configs") do |event|
    self.only_creator(event.user) {
      self.log "'#{event.user.name}' just requested a config reload!", event.bot
      self.scan_bot_files()
      event.respond "Done! Hopefully..."
    }
  end

  message(content: "!reload-message-counts") do |event|
    self.only_creator(event.user) {
      self.log "'#{event.user.name}' just requested a member message count reload!", event.bot
      self.scan_member_message_counts()
      event.respond "Done! Hopefully..."
    }
  end

  message(content: "!save-message-counts") do |event|
    self.only_creator(event.user) {
      self.log "'#{event.user.name}' just requested a member message count persist!", event.bot
      self.persist_member_message_counts()
      event.respond "Done! Hopefully..."
    }
  end

  message(content: "!print-message-counts") do |event|
    self.only_creator(event.user) {
      self.log "'#{event.user.name}' just requested a member message count print-out on '#{event.server.name}' - '##{event.channel.name}'!", event.bot
      event.respond YAML.dump(@@member_message_counts)
    }
  end

  message(start_with: "!spank") do |event|
    self.only_creator(event.user) {
      mentions = event.message.mentions.map(&:mention).join " "
      event.respond "#{mentions} bend over bitch and accept your punishment\nhttps://cdn.discordapp.com/attachments/107942652275601408/107945087350079488/TuHGJ.gif"
    }
  end

  # invoke this command if you want to e.g. add new audio clips or memes, but don't want to restart the bot. for now, you also have to invoke e.g. #audio-load manually afterwards.
  message(content: "!git-pull") do |event|
    self.only_creator(event.user) {
      event.channel.split_send "Done.\n#{`cd #{BuddyBot.path} && git pull`}"
    }
  end

end
