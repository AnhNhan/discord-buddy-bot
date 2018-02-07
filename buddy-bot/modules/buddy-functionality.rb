
require 'discordrb'

module BuddyBot::Modules::BuddyFunctionality
  extend Discordrb::EventContainer

  @@member_names = {
    # ships
    "sinrin" => "sinb+yerin",
    "2bi" => "eunha+sinb",
    "2ye" => "yerin+umji",
    "2won" => "umji+sowon",
    "eunbi" => "eunha+sinb",
    "eunrin" => "eunha+yerin",
    "yurin" => "yuju+yerin",
    "wonha" => "sowon+eunha",
    # regular members
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
    "ginseng" => "yerin",
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

  @@primary_role_names = [
    "eunha",
    "sinb",
    "sowon",
    "yerin",
    "yuju",
    "umji",
  ]

  @@primary_ids = [
    # gfriend
    166306322520735744, # 🌌 Umji 엄지
    166306300261564416, # 🌌 SinB 신비
    166306276148510720, # 🌌 Yuju 유주
    166306204379906048, # 🌌 Eunha 은하
    166306254048854017, # 🌌 Yerin 예린
    166306230468476928, # 🌌 Sowon 소원
    345292659600130048, # new umji role
    # anh-test
    168814333717905408, # Sowon
    168813932239126528, # Eunha
    168813954406154241, # SinB
    168814003982696449, # Yuju
    168814302495637505, # Yerin
    168814320212246528, # Umji
    # t-2
    326506500904452109, # yuju main
    326506388761214988, # umji main
    326506323145392140, # yerin main
    326506255726411786, # sinb main
    326506188348981250, # eunha main
    326506102214754305, # sowon main
  ];
  
  @@special_members = {
    "fingerteep" => 283848369250500608,
    "owlofjune" => 326237059918462976,
    "owlofshipping" => 326237059918462976,
    "anhnhan" => 139342974776639489,
    "leth" => 144545054441078784,
    "lethargic" => 144545054441078784,
    "dot" => 112191130728161280,
    "sojiniee" => 163122269403480065,
    "idiot" => 116361044217167876,
    "chipst3r" => 212291933748330497,
    "gfriendbot" => 115385224119975941,
    "noona" => 155149108183695360, # noona bot
    "robyul" => 283848369250500608, # is he even on #gfriend?
    "buddybot" => 168796631137910784,
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
    "BUDDIES, TOGEHTER, FOREVER",
    "NA NA NA NAVILLERA",
    "LAUGHING OUT LOUD",
    "LOTS OF LOVE",
    "TANG TANG TANG",
    "FINGER FINGERTIP",
    "PINGO TIP",
    "TIME GOES TICK TOCK",
    "STARTING FROM TODAY, US",
    "I'LL GIVE YOU PRECIOUS MEMORIES",
    "LET ME TELL YOU A PRECIOUS STORY",
    "OPEN YOUR EARS",
    "BLOOM LIKE THE FLOWERS",
    "WAKE FROM THE DREAMS",
    "LET'S START FRESH, YOU AND ME",
    "SOMEDAY, YOU AND I",
    "IN THE SAME PLACE, JUST US TWO",
    "BABY UNTIL ALWAYS OH YEAH",
    "WANNA BE YOUR ONE WAY",
    "WE ARE LIKE PARALLEL LINES",
    "I GUESS WE ARE STILL TOO YOUNG",
    "OH MY GOD LOVE MY BOY",
    "WELCOME TO THE NEVERLAND",
    "KISS ME BABY",
    "WOO YEAH",
    "I'LL SHINE ON YOU FOREVER",
    "PROTECT ME SO I WON'T BREAK",
    "SUMMER RAIN",
    "AVE MARIA",
    "RAINBOW",
    "PARALLEL",
    "I'M WITH YOU",
    "LIKE THE SUMMER RAIN",
    "OUR CRYSTAL CLEAR STORY",
    "DUGEUNDAEYO",
    "DUGEUN DUGEUN DUGEUN",
    "HEY MR. TAXI",
    "TAKE ME AWAY",
    "HURRY UP UP",
    "DANCE DANCE COME ON",
    "HIDE AND SEEK IN 1 CHANNEL",
    "ON THE ONE AND ONLY GUILD",
  ]

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
      if role.name.eql?('Sowon\'s Hair') || role.name.eql?('Umji\'s Cheeks') || role.name.eql?('Yeppeu Yerin')
        next
      end
      match = role.name.downcase.scan(/([A-z]+)/).find{ |part| searches.include?(part.first) }
      if !match
        next
      end
      requesting_primary ^ !self.role_is_primary(role)
    end
    puts roles.map(&:name)
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
    if @@primary_role_names.include? role_name
      no_primary_yet = !user.roles.find{ |role| self.role_is_primary(role) }
      puts no_primary_yet
      no_primary_yet
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
    # event.bot.profile.avatar = open("GFRIEND-NAVILLERA-Lyrics.jpg")
    event.bot.game = @@motd.sample
    self.log "ready!", event.bot

    # event.bot.servers.each do |server_id, server|
    #   roles = server.roles.sort_by(&:position).map do |role|
    #     "`Role: #{role.position.to_s.rjust(2, "0")} - #{role.id} - #{role.name} - {#{role.colour.red}|#{role.colour.green}|#{role.colour.blue}} - #{if role.hoist then "hoist" else "dont-hoist" end}`\n"
    #   end.join
    #   self.log "**#{server.name}**\n#{roles}\n", event.bot
    # end
  end

  message(start_with: /^!motd/) do |event|
    event.bot.game = @@motd.sample
  end

  member_join do |event|
    event.server.general_channel.send_message "#{event.user.mention} joined! Please welcome him/her!"
    event.user.on(event.server).add_role(self.find_roles(event.server, "buddy", false))
    self.log "Added role 'Buddy' to #{event.user.mention}", event.bot
  end

  message(in: "whos_your_bias") do |event|
    text = event.content
    if text =~ /^!(remove|primary)/i
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
      event.send_message "Hey @#{member.nick || member.username}, lookie lookie super lookie! You have an admirer!"
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

  message(start_with: /^!primary\s*/i, in: "whos_your_bias") do |event|
    if event.user.nil?
      self.log "The message received in #{event.channel.mention} did not have a user?", event.bot
    end
    if event.user.bot_account?
      self.log "Ignored message from bot #{event.user.mention}.", event.bot
      next
    end
    self.log "Primary switch attempt by #{event.user.mention}", event.bot
    data = event.content.scan(/^!primary\s+(.*?)\s*$/i)[0]
    if data
      data = data[0].downcase
      user = event.user.on event.server
      removed_roles = []
      added_roles = []

      current_primary_roles = user.roles.find_all{ |role| self.role_is_primary(role) }

      current_primary_roles.map do |current_primary_role|
        removed_roles << "**#{current_primary_role.name}**"
        self.log "Removed role '#{current_primary_role.name}' from '#{event.user.name}'", event.bot
        user.remove_role current_primary_role
      end

      if !@@primary_role_names.include? data
        event.send_message "#{user.mention} you didn't give me a possible primary bias"
        next
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

  message(start_with: /^!remove\s+/i, in: "whos_your_bias") do |event|
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
      self.members_map data, cb_member, cb_other_member

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
      self.log "Ignored message from bot #{event.user.mention}.", event.bot
      next
    end
    self.log "Remove-All attempt by #{event.user.mention}", event.bot
    user = event.user.on event.server
    removed_roles = []
    main_roles = user.roles.find_all do |role|
      if role.name.eql? 'Sowon\'s Hair'
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
        "  **!remove** Removes a bias." +
        "  **!help** / **!commands** Displays this help."
  end

  @@members_of_other_groups = {
    "momo" => [
      "*nico nico ni~*",
      "omo momo",
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
    "chaeyoung" => [
      "Baby Chaeng",  
    ],
    "jungyeon" => [
      "Kith her!",  
    ],
    "jeongyeon" => [
      "Kith her!",  
    ],
    "dahyun" => [
      "Twice",
    ],
    "dubu" => [
      "Twice",
    ],
    "nayeon" => [
      "Twice",
    ],
    "jihyo" => [
      "don't scream into my ear :(",
    ],
    "mina" => [
      "Twice",
      "AOA",
      "Mina plz!",
      "Minabois!",
    ],
    "gain" => [
      "Full Bloom",  
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
    "tiffany" => [
      "SNSD",
    ],
    "fany" => [
      "SNSD",
    ],
    "sica" => [
      "Did you mistake her for SinB?",
    ],
    "sunny" => [
      "omo",
    ],
    "choa" => [
      "AOA",
    ],
    "yuna" => [
      "AOA",
      "The Ark",
    ],
    "euna" => [
      "The Ark",  
    ],
    "seolhyun" => [
      "omo",  
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
    "suji" => [
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
      "Muh ha:t felt wa doki doki",
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
    "chungha" => [
      "*PICK ME PICK ME PICK ME PICK ME*",  
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
      "[x] Yes [ ] No [ ] Maybe",
    ],
    "sueji" => [
      "miss A",
    ],
    "sojung" => [
      "I think a lot of people have that name...",
    ],
    "soojung" => [
      "I think a lot of people have that name...",
    ],
    "hyojung" => [
      "Oh Ma Girl",
      "*PICK ME PICK ME PICK ME PICK ME*",
    ],
    "mimi" => [
      "@AnhNhan's waifu, hands off!'",
    ],
    "jiho" => [
      "She looks like Krystal..."
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
    "iu" => [
      "muh red shoes!"
    ],
    "le" => [
      "EXID",
    ],
    "hani" => [
      "EXID",
    ],
    "junghwa" => [
      "Did you mistake her for Jeonghwa?",
    ],
    "jeonghwa" => [
      "Did you mistake her for Junghwa",
    ],
    "ailee" => [
      "Ai Lee"
    ],
    "hyosung" => [
      "himitsu desu!"
    ],
    "kyungri" => [
      "Hot damn!"
    ],
    "heejin" => [
      "LOOΠΔ!",
    ],
    "hyunjin" => [
      "LOOΠΔ!",
    ],
    "haseul" => [
      "LOOΠΔ!",
    ],
    "yeojin" => [
      "LOOΠΔ!",
    ],
    "vivi" => [
      "LOOΠΔ!",
    ],
    "kimlip" => [
      "LOOΠΔ!",
    ],
    "jinsoul" => [
      "LOOΠΔ!",
    ],
    "choerry" => [
      "LOOΠΔ!",
    ],
    "yves" => [
      "LOOΠΔ!",
    ],
    "chuu" => [
      "LOOΠΔ!",
    ],
    "gowon" => [
      "LOOΠΔ!",
    ],
    "loona" => [
      "https://discord.gg/K7vsQEU",
    ],
    "sohee" => [
      "Sorry, who?",
      "Did you mean Kim Sohee, Kim Sohee or Kim Sohee?",
    ],
    "rose" => [
      "BLΛƆKPIИK IN YOUR AREA!"
    ],
    "jisoo" => [
      "BLΛƆKPIИK IN YOUR AREA!",
      "Ah-Choo!",
    ],
    "lisa" => [
      "BLΛƆKPIИK IN YOUR AREA!"
    ],
    "lalisa" => [
      "BLΛƆKPIИK IN YOUR AREA!"
    ],
    "jennie" => [
      "BLΛƆKPIИK IN YOUR AREA!"
    ],
    "wheein" => [
      "Mamamoo~"
    ],
    "solar" => [
      "Mamamoo~"
    ],
    "hwasa" => [
      "Mamamoo~"
    ],
    "moonbyul" => [
      "Mamamoo~"
    ],
    "nancy" => [
      "Jjang!"
    ],
    "exy" => [
      "Catch me!"
    ],
    "luda" => [
      "GFriend?"
    ],
    "eunseo" => [
      "WJSN"
    ],
    "jenny" => [
      "GFriend?"
    ],
    "chaeyeon" => [
      "Do It Amazing!"
    ],
    "kei" => [
      "Aegyo Queen"
    ],
    "sujeong" => [
      "Lovelyz"
    ],
    "jinsol" => [
      "April"
    ],
    "seventeen" => [
      "Aju nice!",
    ],
    "jungkook" => [
      "BTS",  
    ],
    "v" => [
      "Bi",  
    ],
    "leeteuk" => [
      "SJ",  
    ],
    "heechul" => [
      "SJ",  
    ],
    "kyuhyun" => [
      "SJ",  
    ],
    "jackson" => [
      "I GOT 7",  
    ],
    "naeun" => [
      "Her ankle hurt :( ...",  
    ],
    "eunji" => [
      "APink",
    ],
    "namjoo" => [
      "APink",
    ],
    "sunmi" => [
      "Full Moon",  
      "JYP Ent.",  
      "Jack Bauer",  
      "Gashina",  
      "Wonder Girls",
    ],
    "xiyeon" => [
      "Prithtin",  
    ],
    "siyeon" => [
      "Prithtin",  
      "Dreamcatcher",
    ],
    "kyulkyung" => [
      "We are Pristin!",  
    ],
    "roa" => [
      "Annyeong...",  
    ],
    "minkyung" => [
      "Annyeong",  
    ],
    "jiu" => [
      "Dreamcatcher",  
    ],
    "yoohyeon" => [
      "Dreamcatcher",  
    ],
    "dami" => [
      "Dreamcatcher",  
    ],
    "soyou" => [
      "Collab Queen",  
    ],
    "cl" => [
      "Imma da best!",  
    ],
    "dara" => [
      "2NE1",  
    ],
    "youngji" => [
      "Hur hur hur",  
    ],
    "pinky" => [
      "I.O.I",  
    ],
    "yeonjung" => [
      "I.O.I",  
    ],
    "yg" => [
      "Daddy!",  
    ],
    "dad" => [
      "I'm your father...",  
    ],
    "baekhyun" => [
      "Did you mistake him for Bacon?",
    ],
    "bacon" => [
      "Did you mistake him for Oreo?",
    ],
    "oreo" => [
      "Did you mistake him for the pervert?",
    ],
    "pervert" => [
      "Did you mistake him for Byun Baekhyun?",
    ],
    "daniel" => [
      "Wanna GFriend?",  
    ],
    "gfriend" => [
      "You are at the right place :D",
    ],
    "defconn" => [
      "Weeekly Aidol!1!",  
    ],
    "hyungdon" => [
      "Weeekly Aidol!1!",  
    ],
    "hyeongdon" => [
      "Weeekly Aidol!1!",  
    ],
    "boa" => [
      "SM Family",
      "SM Top Madam",
    ],
    "dam" => [
      "https://i.imgur.com/eNtlu1r.jpg"
    ],
    "amber" => [
      "We don't serve guys here"
    ],
    "avenger" => [
      "You could have the power of the gods!"
    ],
    "avengers" => [
      "You could have the power of the gods!"
    ],
    "nugu" => [
      "who?"
    ],
    "batman" => [
      "na-na-na-na-na-na-na"
    ],
    "once" => [
      "Are you actually a Buddy?",
      "https://discord.gg/5nZM7c8",
      "https://discord.gg/9Wq9f5G",
      "https://discord.gg/2ABZXUw",
    ],
    "table" => [
      "https://discord.gg/RfM3ZXr"
    ],
    "pogba" => [
      "..."
    ],
    "zlatan" => [
      "..."
    ],
  }
end
