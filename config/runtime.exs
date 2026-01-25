import Config

# Runtime configuration for production
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :rss2nostr, Rss2Nostr.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")
end

# Nostr configuration from environment variables
if nostr_relays = System.get_env("NOSTR_RELAYS") do
  config :rss2nostr, :nostr, relays: String.split(nostr_relays, ",") |> Enum.map(&String.trim/1)
end

if nostr_private_key = System.get_env("NOSTR_PRIVATE_KEY") do
  config :rss2nostr, :nostr, private_key: nostr_private_key
end

if nostr_public_key = System.get_env("NOSTR_PUBLIC_KEY") do
  config :rss2nostr, :nostr, public_key: nostr_public_key
end

if upload_endpoint = System.get_env("NOSTR_UPLOAD_ENDPOINT") do
  config :rss2nostr, :nostr, upload_endpoint: upload_endpoint
end

if bunker_connection = System.get_env("NOSTR_BUNKER_CONNECTION") do
  config :rss2nostr, :nostr, bunker_connection: bunker_connection
end

# Import settings
if import_interval = System.get_env("IMPORT_INTERVAL_MINUTES") do
  config :rss2nostr, :import, interval_minutes: String.to_integer(import_interval)
end

if default_language = System.get_env("DEFAULT_LANGUAGE") do
  config :rss2nostr, :import, default_language: default_language
end
