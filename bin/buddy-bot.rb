
$LOAD_PATH << (File.dirname(__FILE__) + "/../buddy-bot/")
$LOAD_PATH << (File.dirname(__FILE__) + "/../buddybot-api/")

begin
  require 'rbnacl/libsodium'
rescue LoadError
  ::RBNACL_LIBSODIUM_GEM_LIB_PATH = File.dirname(__FILE__) + "/libsodium.dll"
end

require 'discordrb'
require 'yaml'

require 'buddy-bot'
require 'modules/buddy-functionality'
require 'modules/tistory'
# require 'modules/memes'

###########################################################
#### MAIN
###########################################################

if !File.exists?(BuddyBot.localconf_filename)
  puts "Local config file not found - empty config file '#{BuddyBot.localconf_filename}' will be created"
  puts "Please add configuration and try again"
  config_file = File.open(BuddyBot.localconf_filename, "w")
  config_file.puts "token: ''\nappid: 0\ns3access: ''\ns3secret: ''\ns3bucket: ''\ns3region: ''\ncleverbot_access: ''\ncleverbot_secret: ''\n"
  config_file.close
  exit false
end

localconf = YAML::load(File.read(BuddyBot.localconf_filename))

Aws.config.update({
  credentials: Aws::Credentials.new(localconf['s3access'], localconf['s3secret']),
  region: localconf['s3region'],
})

if localconf['cleverbot_access'] && localconf['cleverbot_secret']
  require 'cleverbot'
  BuddyBot::Modules::BuddyFunctionality.set_cleverbot(Cleverbot.new(localconf['cleverbot_access'], localconf['cleverbot_secret']))
end

if localconf['twt_consumer_key'] && localconf['twt_consumer_secret']
  BuddyBot::Modules::Tistory.set_twitter_credentials(localconf['twt_consumer_key'], localconf['twt_consumer_secret'])
end

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

if localconf["appid"] == 462291371408228352 || localconf["appid"] == 169371086067204096
  require 'aws-sdk'
  BuddyBot::Modules::Tistory.set_s3_bucket_name(localconf['s3bucket'])
  bot.include! BuddyBot::Modules::Tistory
  BuddyBot::Modules::BuddyFunctionality.activate_crawler_mode()
end

bot.run
