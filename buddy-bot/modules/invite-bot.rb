require 'discordrb'

module BuddyBot::Modules::InviteBot
  extend Discordrb::EventContainer

  message(content: "!invite-link") do |event|
    event.send_message "#{event.user.mention}\nIf you want me to join your server, you can add me at #{event.bot.invite_url}"
  end
end
