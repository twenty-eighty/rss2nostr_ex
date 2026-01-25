import Config

# Configure your database for tests (Docker PostgreSQL)
config :rss2nostr, Rss2Nostr.Repo,
  username: System.get_env("POSTGRES_USER") || "testuser",
  password: System.get_env("POSTGRES_PASSWORD") || "testpassword",
  hostname: "localhost",
  database: "rss2nostr_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Nostr configuration for tests
config :rss2nostr, :nostr,
  relays: ["wss://nos.lol"],
  private_key: nil,
  public_key: nil,
  upload_endpoint: nil,
  bunker_connection: nil

# Print only warnings and errors during test
config :logger, level: :warning
