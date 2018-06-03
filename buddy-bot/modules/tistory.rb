
require 'discordrb'
require 'yaml'

module BuddyBot::Modules::Tistory
  extend Discordrb::EventContainer

  message(start_with: /^!tistory\b/i) do |event|
    next unless !event.user.bot_account?
    BuddyBot.only_channels(event.channel, @@server_bot_commands[event.server.id]) {
      data = event.content.scan(/^!tistory\s+(.*?)\s*$/i)[0]
      if !data
        event.send_message "You need to specify a trivia list name... #{self.random_derp_emoji()}"
        next
      end

      trivia_list_name = data[0].downcase
      #
    }
  end
end
