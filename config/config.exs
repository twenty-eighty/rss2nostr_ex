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
    export: :timer.minutes(10)
  },
  # Default relays for export
  default_relays: [
    "wss://relay.damus.io",
    "wss://nos.lol",
    "wss://relay.nostr.band"
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
