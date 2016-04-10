
module BuddyBot
  cattr_accessor :localconf_filename

  @@project_root = File.dirname(__FILE__) + "/../"

  @@localconf_filename = @@project_root + "localconf.yml"

  def BuddyBot.path(path = "")
    @@project_root + path
  end

  def BuddyBot.current_voice_channel(user, bot)
    bot.servers.each do |server|
      member = user.on server[1] # for some reason I get [id, server] tuples in the server symbol
      return member.voice_channel if member.voice_channel
    end
    nil
  end
end

module BuddyBot::Modules
end
