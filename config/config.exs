import Config

config :rss2nostr,
  ecto_repos: [Rss2Nostr.Repo]

# Scheduler configuration
config :rss2nostr, Rss2Nostr.Scheduler,
  # Task intervals in milliseconds
  intervals: %{
    # Fetch new articles every 15 minutes
    import: :timer.minutes(15),
    # Process new posts every 5 minutes
    process: :timer.minutes(5),
    # Export to Nostr every 10 minutes
    export: :timer.minutes(10),
    # Delete our drafts after the article exists as kind 30023
    cleanup: :timer.hours(1)
  }

# Draft / test / public / inbox Nostr relays. Overridden per env and by
# NOSTR_RELAYS_DRAFT / NOSTR_RELAYS_TEST / NOSTR_RELAYS_PUBLIC / NOSTR_RELAYS_INBOX
# (NOSTR_RELAYS still fills the test list).
config :rss2nostr, :nostr,
  relays: %{
    draft: [],
    test: [
      "wss://nos.lol",
      "wss://relay.damus.io"
    ],
    public: [
      "wss://relay.damus.io",
      "wss://nos.lol",
      "wss://relay.nostr.band"
    ],
    inbox: []
  },
  relay_audience: :test,
  # Pause between articles (and before retrying a rate-limited relay).
  publish_gap_ms: 10_000

# Admin UI: NIP-07 allowlist (overridden by ADMIN_NOSTR_PUBKEYS)
config :rss2nostr, :admin, pubkeys: []

# MCP server (stdio via `mix rss2nostr.mcp`, HTTP at /mcp)
config :ex_mcp, protocol_mode: :prefer_modern
config :rss2nostr, :mcp, token: nil

config :tzdata, :http_client, Rss2Nostr.TzdataHTTPClient

config :phoenix, :json_library, Jason
config :phoenix, :filter_parameters, ["password", "nsec", "signing_nsec", "secret"]

config :rss2nostr, Rss2NostrWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: Rss2NostrWeb.ErrorHTML, json: Rss2NostrWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Rss2Nostr.PubSub,
  live_view: [signing_salt: "rss2nostr_live_view"],
  server: false

config :esbuild,
  version: "0.25.4",
  rss2nostr: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
