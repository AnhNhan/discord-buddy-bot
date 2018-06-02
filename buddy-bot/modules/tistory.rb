
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
end