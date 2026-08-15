import Config
import Dotenvy

# Load `.env` into the process environment. Existing OS vars win.
# Tests only read `.env.test` so a local `.env` cannot point them at the dev DB.
env_dir = System.get_env("RELEASE_ROOT") || File.cwd!()

sources =
  case config_env() do
    :test ->
      [Path.join(env_dir, ".env.test"), System.get_env()]

    env ->
      [
        Path.join(env_dir, ".env"),
        Path.join(env_dir, ".env.#{env}"),
        System.get_env()
      ]
  end

{:ok, vars} = source(sources)

vars
|> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
|> Map.new()
|> System.put_env()

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
else
  repo_opts =
    [
      username: System.get_env("POSTGRES_USER"),
      password: System.get_env("POSTGRES_PASSWORD"),
      hostname: System.get_env("POSTGRES_HOST"),
      database: System.get_env("POSTGRES_DB"),
      port: System.get_env("POSTGRES_PORT")
    ]
    |> Enum.reduce([], fn
      {_key, nil}, acc -> acc
      {:port, port}, acc -> Keyword.put(acc, :port, String.to_integer(port))
      {key, value}, acc -> Keyword.put(acc, key, value)
    end)

  if repo_opts != [] do
    config :rss2nostr, Rss2Nostr.Repo, repo_opts
  end
end

if port = System.get_env("PORT") || System.get_env("WEB_PORT") do
  config :rss2nostr, :web_port, String.to_integer(port)
end

# Nostr configuration from environment variables
parse_relay_list = fn
  nil ->
    nil

  str ->
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
end

existing_relays =
  case Application.get_env(:rss2nostr, :nostr, []) |> Keyword.get(:relays) do
    %{test: test, public: public} -> %{test: List.wrap(test), public: List.wrap(public)}
    list when is_list(list) -> %{test: list, public: []}
    _ -> %{test: [], public: []}
  end

test_relays =
  parse_relay_list.(System.get_env("NOSTR_RELAYS_TEST")) ||
    parse_relay_list.(System.get_env("NOSTR_RELAYS"))

public_relays = parse_relay_list.(System.get_env("NOSTR_RELAYS_PUBLIC"))

relays =
  existing_relays
  |> then(fn relays ->
    if test_relays, do: Map.put(relays, :test, test_relays), else: relays
  end)
  |> then(fn relays ->
    if public_relays, do: Map.put(relays, :public, public_relays), else: relays
  end)

config :rss2nostr, :nostr, relays: relays

case System.get_env("NOSTR_RELAY_AUDIENCE") do
  "public" -> config :rss2nostr, :nostr, relay_audience: :public
  "test" -> config :rss2nostr, :nostr, relay_audience: :test
  _ -> :ok
end

if nostr_private_key = System.get_env("NOSTR_PRIVATE_KEY") || System.get_env("NOSTR_NSEC") do
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

case System.get_env("ADMIN_NOSTR_PUBKEYS") do
  value when is_binary(value) and value != "" ->
    config :rss2nostr, :admin, pubkeys: Rss2Nostr.Nostr.Keys.parse_pubkey_list(value)

  _ ->
    :ok
end

secret = System.get_env("SECRET_KEY_BASE")

cond do
  is_binary(secret) and secret != "" ->
    config :rss2nostr, :secret_key_base, secret

  config_env() == :test ->
    config :rss2nostr,
           :secret_key_base,
           "rss2nostr_test_secret_key_base_rss2nostr_test_secret_key_base"

  true ->
    :ok
end
