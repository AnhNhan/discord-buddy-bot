
module BuddyBot
  @@project_root = File.dirname(__FILE__) + "/../"

  @_localconf_filename = @@project_root + "localconf.yml"

  def BuddyBot.path(path = "")
    @@project_root + path
  end

  def BuddyBot.localconf_filename()
    @_localconf_filename
  end

  def BuddyBot.only_channels(channel, id_list, &cb)
    if (id_list || []).include?(channel.id)
      cb.call
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
    @@global_emoji_map[id] || @@global_emoji_map[431133727528058880]
  end
end

module BuddyBot::Modules
end
