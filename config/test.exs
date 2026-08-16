import Config

# Configure your database for tests (local PostgreSQL)
config :rss2nostr, Rss2Nostr.Repo,
  username: System.get_env("POSTGRES_USER") || "postgres",
  password: System.get_env("POSTGRES_PASSWORD") || "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  port: String.to_integer(System.get_env("POSTGRES_PORT") || "5432"),
  database:
    System.get_env("POSTGRES_DB") || "rss2nostr_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Nostr configuration for tests
config :rss2nostr, :nostr,
  relays: %{
    draft: ["wss://draft.example.com"],
    test: ["wss://nos.lol"],
    public: ["wss://relay.example.com"]
  },
  relay_audience: :test,
  private_key: nil,
  public_key: nil,
  upload_endpoint: nil,
  bunker_connection: nil

# secp256k1 generator (private key = 1). Used as the NIP-07 admin allowlist in tests.
config :rss2nostr, :admin,
  pubkeys: ["79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"]

config :rss2nostr,
       :secret_key_base,
       "rss2nostr_test_secret_key_base_rss2nostr_test_secret_key_base"

# Print only warnings and errors during test
config :logger, level: :warning

config :rss2nostr, :code_reloader, false
config :rss2nostr, :enrich_youtube_titles, false
