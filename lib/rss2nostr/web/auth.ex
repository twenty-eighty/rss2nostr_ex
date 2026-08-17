defmodule Rss2Nostr.Web.Auth do
  @moduledoc """
  NIP-07 admin authentication.

  The browser signs a kind 27235 event with `window.nostr.signEvent`.
  The server checks the signature, a one-time challenge, and that the
  pubkey is listed in `ADMIN_NOSTR_PUBKEYS`.
  """

  require Logger
  import Plug.Conn

  alias Rss2Nostr.Nostr.{Event, Keys, NIP19}

  @kind_http_auth 27235
  @challenge_ttl_seconds 300
  @event_max_age_seconds 120
  @session_pubkey :admin_pubkey
  @session_challenge :auth_challenge
  @session_max_age 60 * 60 * 24
  @secret_file ".secret_key_base"
  @content "rss2nostr-admin"
  @current_pubkey_key {__MODULE__, :pubkey}

  @type event_map :: map()

  @spec kind() :: integer()
  def kind, do: @kind_http_auth

  @spec content() :: String.t()
  def content, do: @content

  @spec pubkeys() :: [String.t()]
  def pubkeys do
    Application.get_env(:rss2nostr, :admin, [])
    |> Keyword.get(:pubkeys, [])
    |> Keys.parse_pubkey_list()
  end

  @spec configured?() :: boolean()
  def configured?, do: pubkeys() != []

  @spec allowed?(String.t()) :: boolean()
  def allowed?(pubkey) when is_binary(pubkey) do
    hex = String.downcase(pubkey)
    hex in pubkeys()
  end

  def allowed?(_), do: false

  @spec secret_key_base() :: String.t()
  def secret_key_base do
    case Application.get_env(:rss2nostr, :secret_key_base) do
      secret when is_binary(secret) and byte_size(secret) >= 64 ->
        secret

      _ ->
        case :persistent_term.get({__MODULE__, :secret_key_base}, nil) do
          nil ->
            secret = read_or_create_secret_file()
            :persistent_term.put({__MODULE__, :secret_key_base}, secret)
            secret

          secret ->
            secret
        end
    end
  end

  @spec session_max_age() :: pos_integer()
  def session_max_age, do: @session_max_age

  @spec session_opts() :: keyword()
  def session_opts do
    [
      store: :cookie,
      key: "_rss2nostr_session",
      signing_salt: "rss2nostr.auth",
      same_site: "Lax",
      http_only: true,
      max_age: @session_max_age
    ]
  end

  defp read_or_create_secret_file do
    path = secret_file_path()

    case File.read(path) do
      {:ok, secret} ->
        secret = String.trim(secret)
        if byte_size(secret) >= 64, do: secret, else: write_secret_file(path)

      _ ->
        write_secret_file(path)
    end
  end

  defp write_secret_file(path) do
    secret = Base.encode64(:crypto.strong_rand_bytes(48))
    File.write!(path, secret <> "\n")
    secret
  end

  defp secret_file_path do
    root = System.get_env("RELEASE_ROOT") || File.cwd!()
    Path.join(root, @secret_file)
  end

  @spec put_current_pubkey(String.t() | nil) :: String.t() | nil
  def put_current_pubkey(pubkey) do
    Process.put(@current_pubkey_key, pubkey)
    pubkey
  end

  @spec current_pubkey() :: String.t() | nil
  def current_pubkey, do: Process.get(@current_pubkey_key)

  @spec current_npub() :: String.t() | nil
  def current_npub do
    case current_pubkey() do
      nil ->
        nil

      hex ->
        case NIP19.encode_npub(hex) do
          {:ok, npub} -> npub
          _ -> hex
        end
    end
  end

  @spec logged_in?(Plug.Conn.t()) :: boolean()
  def logged_in?(conn) do
    case get_session(conn, @session_pubkey) do
      pubkey when is_binary(pubkey) -> allowed?(pubkey)
      _ -> false
    end
  end

  @spec session_pubkey(Plug.Conn.t()) :: String.t() | nil
  def session_pubkey(conn), do: get_session(conn, @session_pubkey)

  @spec new_challenge(Plug.Conn.t()) :: {Plug.Conn.t(), map()}
  def new_challenge(conn) do
    token = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
    url = login_url(conn)
    now = System.os_time(:second)

    payload = %{
      "challenge" => token,
      "url" => url,
      "method" => "POST",
      "kind" => @kind_http_auth,
      "content" => @content
    }

    conn =
      put_session(conn, @session_challenge, %{
        "token" => token,
        "url" => url,
        "issued_at" => now
      })

    Logger.info("[Auth] Issued NIP-07 login challenge")

    {conn, payload}
  end

  @spec login(Plug.Conn.t(), event_map()) ::
          {:ok, Plug.Conn.t()} | {:error, Plug.Conn.t(), atom()}
  def login(conn, event) do
    challenge = get_session(conn, @session_challenge)
    conn = delete_session(conn, @session_challenge)

    with {:ok, event} <- normalize_event(event),
         :ok <- verify_challenge(event, challenge),
         {:ok, _} <- Event.verify_event(event),
         :ok <- verify_kind(event),
         :ok <- verify_content(event),
         :ok <- verify_timestamp(event),
         :ok <- verify_admin(event.pubkey) do
      Logger.info("[Auth] NIP-07 login succeeded for #{String.slice(event.pubkey, 0, 8)}…")
      {:ok, put_session(conn, @session_pubkey, String.downcase(event.pubkey))}
    else
      {:error, reason} ->
        Logger.warning("[Auth] NIP-07 login failed: #{inspect(reason)}")
        {:error, conn, reason}
    end
  end

  @spec logout(Plug.Conn.t()) :: Plug.Conn.t()
  def logout(conn) do
    conn
    |> delete_session(@session_pubkey)
    |> delete_session(@session_challenge)
  end

  @spec login_url(Plug.Conn.t()) :: String.t()
  def login_url(conn) do
    scheme = conn.scheme |> to_string()
    host = conn.host
    port = conn.port

    authority =
      cond do
        scheme == "http" and port == 80 -> host
        scheme == "https" and port == 443 -> host
        true -> "#{host}:#{port}"
      end

    "#{scheme}://#{authority}/auth/login"
  end

  @spec public_path?(Plug.Conn.t()) :: boolean()
  def public_path?(%Plug.Conn{method: method, path_info: path_info}) do
    case {method, path_info} do
      {"GET", ["login"]} -> true
      {"GET", ["auth", "challenge"]} -> true
      {"POST", ["auth", "login"]} -> true
      {"POST", ["logout"]} -> true
      {"GET", ["static" | _]} -> true
      _ -> false
    end
  end

  defp normalize_event(event) when is_map(event) do
    id = event["id"] || event[:id]
    pubkey = event["pubkey"] || event[:pubkey]
    created_at = event["created_at"] || event[:created_at]
    kind = event["kind"] || event[:kind]
    tags = event["tags"] || event[:tags] || []
    content = event["content"] || event[:content] || ""
    sig = event["sig"] || event[:sig]

    cond do
      not is_binary(id) or not is_binary(pubkey) or not is_binary(sig) ->
        {:error, :invalid_event}

      not is_integer(created_at) or not is_integer(kind) or not is_list(tags) ->
        {:error, :invalid_event}

      true ->
        {:ok,
         %{
           id: id,
           pubkey: String.downcase(pubkey),
           created_at: created_at,
           kind: kind,
           tags: tags,
           content: content,
           sig: sig
         }}
    end
  end

  defp normalize_event(_), do: {:error, :invalid_event}

  defp verify_challenge(_event, nil), do: {:error, :missing_challenge}

  defp verify_challenge(event, %{"token" => token, "url" => url, "issued_at" => issued_at}) do
    now = System.os_time(:second)

    cond do
      not is_integer(issued_at) or now - issued_at > @challenge_ttl_seconds ->
        {:error, :challenge_expired}

      find_tag(event.tags, "challenge") != token ->
        {:error, :challenge_mismatch}

      find_tag(event.tags, "u") != url ->
        {:error, :url_mismatch}

      String.upcase(find_tag(event.tags, "method") || "") != "POST" ->
        {:error, :method_mismatch}

      true ->
        :ok
    end
  end

  defp verify_challenge(_, _), do: {:error, :missing_challenge}

  defp verify_kind(%{kind: kind}) when kind == @kind_http_auth, do: :ok
  defp verify_kind(_), do: {:error, :invalid_kind}

  defp verify_content(%{content: @content}), do: :ok
  defp verify_content(_), do: {:error, :invalid_content}

  defp verify_timestamp(%{created_at: created_at}) do
    now = System.os_time(:second)

    cond do
      created_at > now + 60 -> {:error, :timestamp_in_future}
      now - created_at > @event_max_age_seconds -> {:error, :timestamp_expired}
      true -> :ok
    end
  end

  defp verify_admin(pubkey) do
    if allowed?(pubkey), do: :ok, else: {:error, :unauthorized_pubkey}
  end

  defp find_tag(tags, name) when is_list(tags) do
    case Enum.find(tags, fn
           [tag | _] when is_binary(tag) -> tag == name
           _ -> false
         end) do
      [_, value | _] when is_binary(value) -> value
      _ -> nil
    end
  end

  defp find_tag(_, _), do: nil
end
