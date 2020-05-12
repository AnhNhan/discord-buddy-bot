# Deployment

1. Install Ruby >= 2.2.0
2. Install gems via bundler
3. Install other dependencies
  - libopus / `opus.dll`
  - ffmpeg available on `PATH`
4. `ruby retrieve-pokemon.rb` - most important

Okay, we should be done with the most difficult part. Now go run the bot for the first time to generate the config file: `ruby han-bot.rb`.

Fill in bot token and app id. Using username+password combo is only recommended if you are not using a bot user.

Now just run the bot again and relax. To have the bot join the server, if it's a bot account follow the usual steps of adding it per OAuth2, or if it's a regular user use an official client to join.
