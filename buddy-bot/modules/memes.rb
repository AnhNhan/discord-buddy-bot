
require 'discordrb'
require 'yaml'

module BuddyBot::Modules::Memes
  extend Discordrb::EventContainer
  cattr_accessor :memes

  def self.scan_files()
    YAML.load_file(BuddyBot.path("content/memes.yml"))
  end

  @memes = self.scan_files()

  message(start_with: /!/) do |event|
    meme_name = event.message.content.scan(/^!(.*?)\s*$/i)[0][0].downcase
    meme_exists = @memes.has_key? meme_name
    if meme_exists
      meme = @memes[meme_name]
      if meme.has_key? "comment"
        event.respond "_" + meme["comment"].to_s + "_"
      end
      event.respond meme["img-url"]
    end
  end

  message(content: "!meme-list") do |event|
    event.channel.split_send @memes.keys.sort.reverse!.reverse!.map{ |k| "!" + k }.join("\n")
  end

  message(content: "!meme-reload") do |event|
    old_length = @memes.keys.length
    @memes = self.scan_files()
    new_length = @memes.keys.length
    event.respond "Done! Found #{new_length} files. Δ of #{new_length - old_length}."
  end

  # not sure whether BuddyBot supports this, this is copy-pasta from HanBot
  # register_command "meme-list"
  # register_command "meme-reload"

  # add_valid_command_callback { |str| @memes.has_key?(str) }
  # add_valid_command_list_callback { || @memes.keys }
end
