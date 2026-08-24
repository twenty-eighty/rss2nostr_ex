import Config

# Configure your database
config :rss2nostr, Rss2Nostr.Repo, pool_size: 10

# Nostr configuration
config :rss2nostr, :nostr,
  relays: %{draft: [], test: [], public: [], inbox: []},
  relay_audience: :public,
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

config :rss2nostr, :code_reloader, false
config :rss2nostr, :start_web_server, true
config :rss2nostr, :web_port, 4000

config :rss2nostr, Rss2NostrWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  server: true,
  check_origin: true,
  url: [host: "localhost"]
