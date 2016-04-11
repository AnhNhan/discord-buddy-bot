
require 'discordrb'

module BuddyBot::Modules::BuddyFunctionality
  extend Discordrb::EventContainer

  @@member_names = {
    "eunha" => "eunha",
    "sinb" => "sinb",
    "shinbi" => "sinb",
    "sowon" => "sowon",
    "sojung" => "sowon",
    "yerin" => "yerin",
    "yenni" => "yerin",
    "yuju" => "yuju",
    "yuna" => "yuju",
    "umji" => "umji",
    "yewon" => "umji",
    "umjiya" => "umji"
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
    event.server.general_channel.send_message "#{event.user.mention} joined! Please welcome him!"
    event.user.on(event.server).add_role(self.find_role(event.server, "buddy"))
    event.bot.debug("Added role 'Buddy' to '#{event.user.name}'")
  end

  message(in: "whos_your_bias") do |event|
    text = event.content
    user = event.user.on event.server
    added_roles = []
    puts text.scan(/([A-z]+)/)
    text.scan(/([A-z]+)/).map do |matches|
      word = matches.first.downcase
      if @@member_names.has_key? word
        member_name = @@member_names[word]
        role = self.find_role event.server, member_name
        user.add_role role
        added_roles << role.name
        puts "ÄÄÄÄ Adding #{role.name} to #{user.name}"
        event.bot.debug("Added role '#{role.name}' to '#{event.user.name}'")
      end
    end
    if !added_roles.empty?
      added_roles_text = added_roles.map{ |s| "**#{s}**" }.join ", "
      event.send_message "#{user.mention} your bias#{if added_roles.length > 1 then 'es' end} #{if added_roles.length > 1 then 'are' else 'is' end} now #{added_roles_text}"
    end
  end
end
