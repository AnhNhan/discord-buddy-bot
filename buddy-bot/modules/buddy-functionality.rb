
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

  def self.log(msg, bot)
    # buddy bot log on anh-test
    bot.send_message 189800756403109889, msg
  end

  def self.find_role(server, name)
    name = name.downcase
    server.roles.find{ |role| role.name.downcase.scan(/([A-z]+)/).find{ |part| part.first.eql?(name) } }
  end

  ready do |event|
    #event.bot.profile.avatar = open("GFriend-gfriend-39231889-1500-998.jpg")
    event.bot.game = "NA NA NA NAVILLERA"
    self.log "ready!", event.bot
  end

  member_join do |event|
    event.server.general_channel.send_message "#{event.user.mention} joined! Please welcome him/her!"
    event.user.on(event.server).add_role(self.find_role(event.server, "buddy"))
    self.log "Added role 'Buddy' to '#{event.user.name}'", event.bot
  end

  message(in: "whos_your_bias") do |event|
    text = event.content
    user = event.user.on event.server
    added_roles = []
    rejected_names = []
    text.scan(/([A-z]+)/).map do |matches|
      word = matches.first.downcase
      if @@member_names.has_key? word
        member_name = @@member_names[word]
        role = self.find_role event.server, member_name
        user.add_role role
        added_roles << "**#{role.name}**" + if !word.eql? member_name then " _(#{matches.first})_" else "" end
        self.log "Added role '#{role.name}' to '#{event.user.name}'", event.bot
      elsif @@members_of_other_groups.has_key? word
        rejected_names << word
        self.log "Warning, '#{event.user.name}' requested '#{word}'.", event.bot
      end
    end
    if !added_roles.empty?
      added_roles_text = added_roles.join ", "
      event.send_message "#{user.mention} your bias#{if added_roles.length > 1 then 'es' end} #{if added_roles.length > 1 then 'are' else 'is' end} now #{added_roles_text}"
    end
    if !rejected_names.empty?
      rejected_names_text = rejected_names.map do |name|
        " - #{name.capitalize} (#{@@members_of_other_groups[name].sample})"
      end.join "\n"
      event.send_message "Warning, the following member#{if rejected_names.length > 1 then 's' else '' end} do not belong to \#Godfriend:\n#{rejected_names_text}\nOfficials have been alerted and now are on the search for you."
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
    bias_stats = self.bias_stats(event.server.members)
    bias_stats.delete "Buddy"
    event.send_message "**##{event.server.name} Bias List** _(note that members may have multiple biases)_"
    event.send_message self.print_bias_stats(bias_stats)
  end

  message(start_with: /^!first-bias-stats\W*/i) do |event|
    bias_stats = self.bias_stats(event.server.members, true, event.server.roles.reverse.map(&:name))
    event.send_message "**##{event.server.name} Bias List**"
    event.send_message self.print_bias_stats(bias_stats)
  end

  message(content: ["!help", "!commands"]) do |event|
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
