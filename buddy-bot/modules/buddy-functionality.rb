
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

  def self.find_role(server, name)
    name = name.downcase
    server.roles.find{ |role| role.name.downcase.eql? name }
  end

  ready do |event|
    #event.bot.profile.avatar = open("GFriend-gfriend-39231889-1500-998.jpg")
    event.bot.game = "👍"
  end

  member_join do |event|
    event.server.general_channel.send_message "#{event.user.mention} joined! Please welcome him/her!"
    event.user.on(event.server).add_role(self.find_role(event.server, "buddy"))
    event.bot.debug("Added role 'Buddy' to '#{event.user.name}'")
  end

  message(in: "whos_your_bias") do |event|
    text = event.content
    user = event.user.on event.server
    added_roles = []
    text.scan(/([A-z]+)/).map do |matches|
      word = matches.first.downcase
      if @@member_names.has_key? word
        member_name = @@member_names[word]
        role = self.find_role event.server, member_name
        user.add_role role
        added_roles << "**#{role.name}**" + if !word.eql? member_name then " _(#{matches.first})_" else "" end
        event.bot.debug("Added role '#{role.name}' to '#{event.user.name}'")
      end
    end
    if !added_roles.empty?
      added_roles_text = added_roles.join ", "
      event.send_message "#{user.mention} your bias#{if added_roles.length > 1 then 'es' end} #{if added_roles.length > 1 then 'are' else 'is' end} now #{added_roles_text}"
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
    event.send_message "**@BuddyBot** to the help!\n\nI help managing #GFRIEND. My creator is <@139342974776639489>, send him a message if I don't behave.\n\n" +
        "**Supported commands**\n" +
        "  **!bias-stats** / **!first-bias-stats** Counts the members biases.\n" +
        "  **!help** / **!commands** Displays this help."
  end
end
