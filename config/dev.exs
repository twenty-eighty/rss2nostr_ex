import Config

# Configure your database (local PostgreSQL)
config :rss2nostr, Rss2Nostr.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  port: String.to_integer(System.get_env("POSTGRES_PORT") || "5432"),
  database: System.get_env("POSTGRES_DB") || "rss2nostr_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Nostr configuration for development
config :rss2nostr, :nostr,
  relays: %{
    test: ["wss://nos.lol", "wss://relay.damus.io"],
    public: ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.nostr.band"]
  },
  relay_audience: :test,
  private_key: nil,
  public_key: nil,
  upload_endpoint: nil,
  bunker_connection: nil

# Import configuration
config :rss2nostr, :import,
  interval_minutes: 60,
  default_language: "de"

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Recompile Elixir (including CSS/JS in views) on each request.
config :rss2nostr, :code_reloader, true

config :rss2nostr, Rss2NostrWeb.Endpoint,
  http: [
    ip: {0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT") || System.get_env("WEB_PORT") || "4000")
  ],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:rss2nostr, ~w(--sourcemap=inline --watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/rss2nostr_web/(?:components|live)/.*\.(ex|heex)$"
    ]
  ]
