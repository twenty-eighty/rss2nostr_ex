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
  port = String.to_integer(port)
  config :rss2nostr, :web_port, port
  config :rss2nostr, Rss2NostrWeb.Endpoint, http: [ip: {0, 0, 0, 0}, port: port]
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
    %{test: test, public: public} = map ->
      %{
        draft: List.wrap(Map.get(map, :draft, [])),
        test: List.wrap(test),
        public: List.wrap(public),
        inbox: List.wrap(Map.get(map, :inbox, []))
      }

    list when is_list(list) ->
      %{draft: [], test: list, public: [], inbox: []}

    _ ->
      %{draft: [], test: [], public: [], inbox: []}
  end

draft_relays = parse_relay_list.(System.get_env("NOSTR_RELAYS_DRAFT"))

test_relays =
  parse_relay_list.(System.get_env("NOSTR_RELAYS_TEST")) ||
    parse_relay_list.(System.get_env("NOSTR_RELAYS"))

public_relays = parse_relay_list.(System.get_env("NOSTR_RELAYS_PUBLIC"))
inbox_relays = parse_relay_list.(System.get_env("NOSTR_RELAYS_INBOX"))

relays =
  existing_relays
  |> then(fn relays ->
    if draft_relays, do: Map.put(relays, :draft, draft_relays), else: relays
  end)
  |> then(fn relays ->
    if test_relays, do: Map.put(relays, :test, test_relays), else: relays
  end)
  |> then(fn relays ->
    if public_relays, do: Map.put(relays, :public, public_relays), else: relays
  end)
  |> then(fn relays ->
    if inbox_relays, do: Map.put(relays, :inbox, inbox_relays), else: relays
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

if gap = System.get_env("NOSTR_PUBLISH_GAP_MS") do
  config :rss2nostr, :nostr, publish_gap_ms: String.to_integer(gap)
end

# Import settings
if import_interval = System.get_env("IMPORT_INTERVAL_MINUTES") do
  config :rss2nostr, :import, interval_minutes: String.to_integer(import_interval)
end

# Tests never auto-start timers, even if the OS env is set.
if config_env() != :test do
  case System.get_env("SCHEDULER_AUTO_START") do
    value when is_binary(value) ->
      case value |> String.trim() |> String.downcase() do
        flag when flag in ["1", "true", "yes", "on"] ->
          config :rss2nostr, Rss2Nostr.Scheduler, auto_start: true

        flag when flag in ["0", "false", "no", "off"] ->
          config :rss2nostr, Rss2Nostr.Scheduler, auto_start: false

        _ ->
          :ok
      end

    _ ->
      :ok
  end
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

if mcp_token = System.get_env("MCP_TOKEN") || System.get_env("RSS2NOSTR_MCP_TOKEN") do
  config :rss2nostr, :mcp, token: mcp_token
end

secret = System.get_env("SECRET_KEY_BASE")

cond do
  is_binary(secret) and secret != "" ->
    config :rss2nostr, :secret_key_base, secret
    config :rss2nostr, Rss2NostrWeb.Endpoint, secret_key_base: secret

  config_env() == :test ->
    config :rss2nostr,
           :secret_key_base,
           "rss2nostr_test_secret_key_base_rss2nostr_test_secret_key_base"

  true ->
    :ok
end
