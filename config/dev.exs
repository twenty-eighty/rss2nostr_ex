import Config

# Configure your database (Docker PostgreSQL)
config :rss2nostr, Rss2Nostr.Repo,
  username: System.get_env("POSTGRES_USER") || "testuser",
  password: System.get_env("POSTGRES_PASSWORD") || "testpassword",
  hostname: "localhost",
  database: "rss2nostr_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Nostr configuration for development
config :rss2nostr, :nostr,
  relays: ["wss://nos.lol", "wss://relay.damus.io"],
  private_key: nil,
  public_key: nil,
  upload_endpoint: nil,
  bunker_connection: nil

# Import configuration
config :rss2nostr, :import,
  interval_minutes: 60,
  default_language: "de"

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"
