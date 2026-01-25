import Config

# Configure your database
config :rss2nostr, Rss2Nostr.Repo, pool_size: 10

# Nostr configuration
config :rss2nostr, :nostr,
  relays: [],
  private_key: nil,
  public_key: nil,
  upload_endpoint: nil,
  bunker_connection: nil

# Import configuration
config :rss2nostr, :import,
  interval_minutes: 60,
  default_language: "de"

# Do not print debug messages in production
config :logger, level: :info
