
module BuddyBot
  @@project_root = File.dirname(__FILE__) + "/../"

  @_localconf_filename = @@project_root + "localconf.yml"

  @@creator_id = 139342974776639489

  def BuddyBot.path(path = "")
    @@project_root + path
  end

  def BuddyBot.localconf_filename()
    @_localconf_filename
  end

  def BuddyBot.current_voice_channel(user, bot)
    bot.servers.each do |server|
      member = user.on server[1] # for some reason I get [id, server] tuples in the server symbol
      return member.voice_channel if member.voice_channel
    end
    nil
  end

  def BuddyBot.is_creator?(user)
    user.id.eql? @@creator_id
  end

  def BuddyBot.only_creator(user, &cb)
    if BuddyBot.is_creator? user
      cb.call
    else
      # event.respond "#{user.mention} you do not have permission to complete this command."
    end
  end

  def BuddyBot.build_emoji_map(servers)
    @@global_emoji_map = {}
    servers.each do |server_id, server|
      server.emojis.each do |emoji_id, emoji|
        @@global_emoji_map[emoji_id] = emoji
      end
    end
  end

  def BuddyBot.emoji(id)
    @@global_emoji_map[id]
  end
end

module BuddyBot::Modules
end
