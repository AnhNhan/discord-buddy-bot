
$LOAD_PATH << (File.dirname(__FILE__) + "/../buddy-bot/")

begin
  require 'rbnacl/libsodium'
rescue LoadError
  ::RBNACL_LIBSODIUM_GEM_LIB_PATH = File.dirname(__FILE__) + "/libsodium.dll"
end

require 'discordrb'
require 'yaml'

require 'aws-sdk'

require 'buddy-bot'
require 'modules/buddy-functionality'
require 'modules/invite-bot'
require 'modules/tistory'
# require 'modules/memes'

###########################################################
#### MAIN
###########################################################

if !File.exists?(BuddyBot.localconf_filename)
  puts "Local config file not found - empty config file '#{BuddyBot.localconf_filename}' will be created"
  puts "Please add configuration and try again"
  config_file = File.open(BuddyBot.localconf_filename, "w")
  config_file.puts "token: ''\nappid: 0\ns3access: ''\ns3secret: ''\ns3bucket: ''\ns3region: ''\n"
  config_file.close
  exit false
end

localconf = YAML::load(File.read(BuddyBot.localconf_filename))

Aws.config.update({
  credentials: Aws::Credentials.new(localconf['s3access'], localconf['s3secret']),
  region: localconf['s3region'],
})

BuddyBot::Modules::Tistory.set_s3_bucket_name(localconf['s3bucket'])

bot = nil
if localconf["token"] && localconf["token"].length && localconf["appid"] != 0
  bot = Discordrb::Bot.new token: localconf["token"], client_id: localconf["appid"]
else
  puts "No authentication info, check localconf.yml."
  exit false
end

bot.message(with_text: /^!ping\W*$/i) do |event|
  event.respond "Pong!"
end

bot.include! BuddyBot::Modules::BuddyFunctionality
bot.include! BuddyBot::Modules::Tistory
# bot.include! BuddyBot::Modules::InviteBot
# bot.include! BuddyBot::Modules::Memes

bot.run
