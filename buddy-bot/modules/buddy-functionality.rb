
require 'discordrb'

module BuddyBot::Modules::BuddyFunctionality
  extend Discordrb::EventContainer

  @@member_names = {
    "eunha" => "eunha",
    "sinb" => "sinb",
    "sinbi" => "sinb",
    "shinbi" => "sinb",
    "sowon" => "sowon",
    "sojung" => "sowon",
    "yerin" => "yerin",
    "yenni" => "yerin",
    "yerini" => "yerin",
    "rinnie" => "yerin",
    "rinni" => "yerin",
    "yuju" => "yuju",
    "yuna" => "yuju",
    "umji" => "umji",
    "yewon" => "umji",
    "umjiya" => "umji",
    "umjiyah" => "umji",
    "manager" => "manager",
    "buddy" => "buddy",
    "imabuddy" => "buddy"
  }

  @@emoji_map = {
    "sowon" => ":bride_with_veil:",
    "eunha" => ":princess:",
    "yerin" => ":girl:",
    "yuju" => ":heart_eyes_cat:",
    "sinb" => ":dancer:",
    "umji" => ":angel:",
    "buddy" => ":fries:"
  }

  @@motd = [
    "ME GUSTA TU",
    "NA NA NA NAVILLERA",
    "LAUGHING OUT LOUD",
    "LOTS OF LOVE"
  ]

  def self.log(msg, bot)
    # buddy bot log on anh-test
    bot.send_message 189800756403109889, msg
  end

  def self.find_role(server, name)
    name = name.downcase
    server.roles.find{ |role| !role.name.eql?('Sowon\'s Hair') && role.name.downcase.scan(/([A-z]+)/).find{ |part| part.first.eql?(name) } }
  end

  def self.members_map(text, cb_member, cb_other_member)
    text.scan(/([A-z]+)/).map do |matches|
      original = matches.first
      match = matches.first.downcase
      if @@member_names.has_key? match
        cb_member.call match, original
      elsif @@members_of_other_groups.has_key? match
        cb_other_member.call match, original
      end
    end
  end

  def self.print_rejected_names(rejected_names, event)
    rejected_names_text = rejected_names.map do |name|
      " - #{name.capitalize} (#{@@members_of_other_groups[name].sample})"
    end.join "\n"
    event.send_message "Warning, the following member#{if rejected_names.length > 1 then 's do' else ' does' end} not belong to \#Godfriend:\n#{rejected_names_text}\nOfficials have been alerted and now are on the search for you."
  end

  ready do |event|
    event.bot.profile.avatar = open("GFRIEND-NAVILLERA-Lyrics.jpg")
    event.bot.game = @@motd.sample
    self.log "ready!", event.bot
  end

  member_join do |event|
    event.server.general_channel.send_message "#{event.user.mention} joined! Please welcome him/her!"
    event.user.on(event.server).add_role(self.find_role(event.server, "buddy"))
    self.log "Added role 'Buddy' to #{event.user.mention}", event.bot
  end

  message(in: "whos_your_bias") do |event|
    text = event.content
    if text =~ /^!remove/i
      next
    end
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot
    end
    if event.user.bot_account?
      self.log "Ignored message from bot #{event.user.mention}.", event.bot
      next
    end
    user = event.user.on event.server
    added_roles = []
    rejected_names = []

    cb_member = lambda do |match, original|
      member_name = @@member_names[match]
      role = self.find_role event.server, member_name
      user.add_role role
      added_roles << "**#{role.name}**" + if !match.eql? member_name then " _(#{original})_" else "" end
      self.log "Added role '#{role.name}' to '#{event.user.name}'", event.bot
    end
    cb_other_member = lambda do |match, original|
      rejected_names << match
      self.log "Warning, '#{event.user.name}' requested '#{match}'.", event.bot
    end
    self.members_map(text, cb_member, cb_other_member)

    if !added_roles.empty?
      added_roles_text = added_roles.join ", "
      event.send_message "#{user.mention} your bias#{if added_roles.length > 1 then 'es' end} #{if added_roles.length > 1 then 'are' else 'is' end} now #{added_roles_text}"
    end
    if !rejected_names.empty?
      self.print_rejected_names rejected_names, event
    end
  end

  message(start_with: /^!remove\W*/i, in: "whos_your_bias") do |event|
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot
    end
    if event.user.bot_account?
      self.log "Ignored message from bot #{event.user.mention}.", event.bot
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
        member_name = @@member_names[match]
        role = self.find_role event.server, member_name
        user.remove_role role
        removed_roles << "**#{role.name}**" + if !match.eql? member_name then " _(#{original})_" else "" end
        self.log "Removed role '#{role.name}' from '#{event.user.name}'", event.bot
      end
      cb_other_member = lambda do |match, original|
        rejected_names << match
        self.log "Warning, '#{event.user.name}' requested to remove '#{match}'.", event.bot
      end
      self.members_map data, cb_member, cb_other_member

      if !removed_roles.empty?
        removed_roles_text = removed_roles.join ", "
        event.send_message "#{user.mention} removed bias#{if removed_roles.length > 1 then 'es' end} #{removed_roles_text}"
      end
      if !rejected_names.empty?
        self.print_rejected_names rejected_names, event
      end
    else
      self.log "Didn't remove role. No input in '#{event.message.content}' #{event.channel.mention}"
    end
  end

  def self.bias_stats(members, first_bias = false, bias_order = [])
    biases = @@member_names.values.uniq
    result = {}
    result.default = 0

    members
      .flat_map do |member|
        if first_bias
          # ugh
          first_bias = bias_order.find { |bias| member.roles.find { |role| role.name.eql? bias } }
          [member.roles.find { |role| role.name.eql? first_bias }]
        else
          member.roles
        end
      end
      .compact
      .map(&:name)
      .select{ |s| @@member_names.values.include? s.downcase }
      .inject(result) do |result, role|
        result[role] += 1
        result
      end
  end

  def self.print_bias_stats(bias_stats)
    bias_stats.map do |name, count|
      "#{@@emoji_map[name.downcase]} " + "**#{name}**:".rjust(6) + count.to_s.rjust(3) + "x"
    end.join "\n"
  end

  message(start_with: /^!bias-stats\W*/i) do |event|
    if event.user.bot_account?
      self.log "Ignored message from bot #{event.user.mention}.", event.bot
      next
    end
    bias_stats = self.bias_stats(event.server.members)
    bias_stats.delete "Buddy"
    event.send_message "**##{event.server.name} Bias List** _(note that members may have multiple biases)_"
    event.send_message self.print_bias_stats(bias_stats)
  end

  message(start_with: /^!first-bias-stats\W*/i) do |event|
    if event.user.bot_account?
      self.log "Ignored message from bot #{event.user.mention}.", event.bot
      next
    end
    bias_stats = self.bias_stats(event.server.members, true, event.server.roles.reverse.map(&:name))
    event.send_message "**##{event.server.name} Bias List**"
    event.send_message self.print_bias_stats(bias_stats)
  end

  message(content: ["!help", "!commands"]) do |event|
    if event.user.bot_account?
      self.log "Ignored message from bot #{event.user.mention}.", event.bot
      next
    end
    event.send_message "**@BuddyBot** to the rescue!\n\nI help managing #GFRIEND. My creator is <@139342974776639489>, send him a message if I don't behave.\n\n" +
        "**Supported commands**\n" +
        "  **!bias-stats** / **!first-bias-stats** Counts the members biases.\n" +
        "  **!help** / **!commands** Displays this help."
  end

  @@members_of_other_groups = {
    "momo" => [
      "*nico nico ni~*",
    ],
    "sana" => [
      "#ShaShaSha",
    ],
    "nosana" => [
      "#ShaShaSha",
    ],
    "nosananolife" => [
      "#ShaShaSha",
    ],
    "tzuyu" => [
      "Twice",
    ],
    "nayeon" => [
      "Twice",
    ],
    "jihyo" => [
      "don't scream into my ear",
    ],
    "mina" => [
      "Twice",
      "AOA",
      "Mina plz!",
    ],
    "taeyeon" => [
      "SNSD",
    ],
    "jessica" => [
      "Did you mistake her for SinB?",
    ],
    "yoona" => [
      "SNSD",
    ],
    "choa" => [
      "AOA",
    ],
    "yuna" => [
      "AOA",
      "The Ark",
    ],
    "krystal" => [
      "f(x-1)",
    ],
    "minju" => [
      "The Ark",
    ],
    "halla" => [
      "The Ark",
    ],
    "jane" => [
      "The Ark",
    ],
    "yuujin" => [
      "The Ark",
      "CL.Clear",
    ],
    "seungyeon" => [
      "CL.Clear",
    ],
    "seunghee" => [
      "CL.Clear",
      "Oh My Girl",
    ],
    "eunbin" => [
      "Eunbeani Beani",
    ],
    "yeeun" => [
      "CL.Clear",
      "Wonder Girls(??)",
    ],
    "sorn" => [
      "CL.Clear",
    ],
    "elkie" => [
      "CL.Clear",
    ],
    "jimin" => [
      "Lè Motherfucking Top Madam",
    ],
    "jimmy" => [
      "CL.Clear",
    ],
    "arin" => [
      "Oh Ma Girl",
    ],
    "yooa" => [
      "Oh Ma Girl",
    ],
    "binnie" => [
      "Oh My Girl",
    ],
    "somi" => [
      "*PICK ME PICK ME PICK ME PICK ME*",
      "adorbs!",
    ],
    "sohye" => [
      "Ey Ouh Ey", # I was told this was Boston accent
    ],
    "sejeong" => [
      "**GODDESS**",
    ],
    "sejong" => [
      "**GODDESS**",
    ],
    "sejung" => [
      "**GODDESS**",
    ],
    "nayoung" => [
      "Ay Oh Ay",
    ],
    "suzy" => [
      "miss A",
    ],
    "sueji" => [
      "miss A",
    ],
    "sojung" => [
      "I think a lot of people have that name...",
    ],
    "hyojung" => [
      "Oh Ma Girl",
      "*PICK ME PICK ME PICK ME PICK ME*",
    ],
    "mimi" => [
      "@AnhNhan's waifu, hands off!'",
    ],
    "sojin" => [
      "uh.... I'm feeling old'",
    ],
    "yura" => [
      "Yura-chu!",
    ],
    "minah" => [
      "did you mean Mina?",
    ],
    "hyeri" => [
      "did you mean Hyerin?",
    ],
    "hyerin" => [
      "did you mean Hyeri?",
    ],
    "yeri" => [
      "did you mean Yerin?",
      "The Red Velvet Gods demand their sacrifice",
    ],
    "wendy" => [
      "The Red Velvet Gods demand their sacrifice",
    ],
    "seulgi" => [
      "The Red Velvet Gods demand their sacrifice",
    ],
    "irene" => [
      "The Red Velvet Gods demand their sacrifice",
    ],
    "joy" => [
      "The Red Velvet Gods demand their sacrifice",
    ],
    "jiyoung" => [
      "Muthafucking JYP!",
    ],
    "jyp" => [
      "Still Alive",
    ],
    "buddybot" => [
      "I heard you...",
    ],
    "peter" => [
      "who??",
    ],
    "max" => [
      "srsly?",
    ],
    "Dolo7" => [
      "who?",
    ],
    "hate" => [
      "Fun Fact: Hate leads to the dark side of the force.",
    ],
    "cookie" => [
      "Cookies can only be found on the dark side of the force.",
    ],
    "hulk" => [
      "**HE IS ANGRY**",
    ],
    "sojiniee" => [
      "thank you for your interest...",
    ],
    "alice" => [
      "Hello Venus"
    ],
    "nara" => [
      "Hello Venus"
    ],
    "lime" => [
      "Hello Venus"
    ],
    "shinee" => [
      "SHINee is back!"
    ],
    "exo" => [
      "E! X! O!"
    ],
  }
end
