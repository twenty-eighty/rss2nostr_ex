defmodule Rss2Nostr.Nostr.NIP46 do
  @moduledoc """
  Implements NIP-46 Nostr Connect (Bunker) protocol.

  Allows remote signing of events using a separate signer application.
  Useful for:
  - Hardware signers
  - Mobile signer apps (Amber, etc.)
  - Keeping private keys secure

  Connection URL format:
    bunker://<remote-signer-pubkey>?relay=<relay>&secret=<secret>

  Protocol:
  - Client generates ephemeral keypair
  - Messages are encrypted using NIP-04
  - Uses kind 24133 events for requests/responses
  """

  use GenServer
  require Logger

  alias Rss2Nostr.Nostr.{Keys, NIP04}

  @kind_nostr_connect 24133
  @request_timeout 60_000

  defstruct [
    :client_privkey,
    :client_pubkey,
    :remote_pubkey,
    :relay_url,
    :secret,
    :ws_pid,
    :subscription_id,
    pending_requests: %{},
    connected: false
  ]

  @type t :: %__MODULE__{}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Parses a bunker:// connection URL.

  Returns {:ok, %{pubkey: ..., relay: ..., secret: ...}} or {:error, reason}
  """
  def parse_bunker_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "bunker", host: pubkey, query: query} when is_binary(pubkey) ->
        params = URI.decode_query(query || "")

        case params do
          %{"relay" => relay} ->
            {:ok,
             %{
               pubkey: pubkey,
               relay: relay,
               secret: params["secret"]
             }}

          _ ->
            {:error, :missing_relay}
        end

      _ ->
        {:error, :invalid_bunker_url}
    end
  end

  @doc """
  Generates a bunker:// connection URL for connecting to this client.

  This is used when you want to connect a remote signer to this application.
  """
  def generate_connection_url(relay_url, opts \\ []) do
    # Generate ephemeral client keypair
    client_privkey = Keyword.get_lazy(opts, :privkey, fn -> Keys.generate_private_key() end)
    client_pubkey = Keys.derive_public_key(client_privkey)
    client_pubkey_hex = Keys.to_hex(client_pubkey)

    # Generate secret
    secret = Keyword.get_lazy(opts, :secret, fn -> generate_secret() end)

    url = "bunker://#{client_pubkey_hex}?relay=#{URI.encode(relay_url)}&secret=#{secret}"

    {:ok, url, client_privkey, secret}
  end

  @doc """
  Starts a NIP-46 Bunker client connection.

  Options:
  - :bunker_url - Full bunker:// URL
  - OR provide separately:
    - :remote_pubkey - The signer's public key (hex)
    - :relay_url - The relay to use for communication
    - :secret - Optional connection secret
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Connects to the remote signer.
  """
  def connect(pid, timeout \\ @request_timeout) do
    GenServer.call(pid, :connect, timeout)
  end

  @doc """
  Gets the public key from the remote signer.
  """
  def get_public_key(pid, timeout \\ @request_timeout) do
    GenServer.call(pid, :get_public_key, timeout)
  end

  @doc """
  Signs an event using the remote signer.

  The event should be an unsigned event map with:
  - kind, created_at, tags, content

  Returns {:ok, signed_event} or {:error, reason}
  """
  def sign_event(pid, event, timeout \\ @request_timeout) do
    GenServer.call(pid, {:sign_event, event}, timeout)
  end

  @doc """
  Disconnects from the remote signer.
  """
  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    # Parse bunker URL if provided
    {remote_pubkey, relay_url, secret} =
      case Keyword.get(opts, :bunker_url) do
        nil ->
          {
            Keyword.fetch!(opts, :remote_pubkey),
            Keyword.fetch!(opts, :relay_url),
            Keyword.get(opts, :secret)
          }

        url ->
          {:ok, parsed} = parse_bunker_url(url)
          {parsed.pubkey, parsed.relay, parsed.secret}
      end

    # Generate ephemeral client keypair
    client_privkey = Keys.generate_private_key()
    client_pubkey = Keys.derive_public_key(client_privkey)

    state = %__MODULE__{
      client_privkey: client_privkey,
      client_pubkey: client_pubkey,
      remote_pubkey: remote_pubkey,
      relay_url: relay_url,
      secret: secret
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:connect, from, state) do
    case do_connect(state) do
      {:ok, new_state} ->
        # Send connect request
        request_id = generate_request_id()

        params =
          if state.secret do
            [Keys.to_hex(state.client_pubkey), state.secret]
          else
            [Keys.to_hex(state.client_pubkey)]
          end

        case send_request(new_state, request_id, "connect", params) do
          {:ok, new_state} ->
            new_state = %{
              new_state
              | pending_requests: Map.put(new_state.pending_requests, request_id, from)
            }

            {:noreply, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, new_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_public_key, from, state) do
    request_id = generate_request_id()

    case send_request(state, request_id, "get_public_key", []) do
      {:ok, new_state} ->
        new_state = %{
          new_state
          | pending_requests: Map.put(new_state.pending_requests, request_id, from)
        }

        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:sign_event, event}, from, state) do
    request_id = generate_request_id()

    # Serialize the event for signing
    unsigned_event = %{
      kind: event.kind,
      created_at: event.created_at,
      tags: event.tags,
      content: event.content
    }

    event_json = Jason.encode!(unsigned_event)

    case send_request(state, request_id, "sign_event", [event_json]) do
      {:ok, new_state} ->
        new_state = %{
          new_state
          | pending_requests: Map.put(new_state.pending_requests, request_id, from)
        }

        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    if state.ws_pid do
      WebSockex.cast(state.ws_pid, :close)
    end

    {:reply, :ok, %{state | connected: false, ws_pid: nil}}
  end

  @impl true
  def handle_info({:ws_message, message}, state) do
    {:ok, new_state} = handle_relay_message(message, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:ws_closed, _reason}, state) do
    Logger.warning("NIP-46 WebSocket closed")
    {:noreply, %{state | connected: false, ws_pid: nil}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_connect(state) do
    Logger.info("Connecting to NIP-46 relay: #{state.relay_url}")

    # Start WebSocket connection
    parent = self()

    case WebSockex.start_link(state.relay_url, Rss2Nostr.Nostr.NIP46.WebSocketHandler, %{
           parent: parent
         }) do
      {:ok, ws_pid} ->
        # Subscribe to responses for our pubkey
        subscription_id = generate_subscription_id()
        client_pubkey_hex = Keys.to_hex(state.client_pubkey)

        filter = %{
          "kinds" => [@kind_nostr_connect],
          "#p" => [client_pubkey_hex],
          "since" => System.os_time(:second) - 60
        }

        sub_message = Jason.encode!(["REQ", subscription_id, filter])
        WebSockex.send_frame(ws_pid, {:text, sub_message})

        {:ok, %{state | ws_pid: ws_pid, subscription_id: subscription_id, connected: true}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_request(state, request_id, method, params) do
    # Build request object
    request = %{
      id: request_id,
      method: method,
      params: params
    }

    request_json = Jason.encode!(request)

    # Encrypt with NIP-04
    case NIP04.encrypt(request_json, state.client_privkey, state.remote_pubkey) do
      {:ok, encrypted} ->
        # Build and sign the event
        event = %{
          kind: @kind_nostr_connect,
          created_at: System.os_time(:second),
          tags: [["p", state.remote_pubkey]],
          content: encrypted
        }

        case Keys.sign_event(event, state.client_privkey) do
          {:ok, %{id: id, sig: sig, pubkey: pubkey}} ->
            signed_event = %{
              id: id,
              pubkey: pubkey,
              created_at: event.created_at,
              kind: event.kind,
              tags: event.tags,
              content: event.content,
              sig: sig
            }

            # Send to relay
            message = Jason.encode!(["EVENT", signed_event])
            WebSockex.send_frame(state.ws_pid, {:text, message})

            {:ok, state}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_relay_message(message, state) do
    case Jason.decode(message) do
      {:ok, ["EVENT", _sub_id, event]} ->
        handle_response_event(event, state)

      {:ok, ["OK", _event_id, true, _message]} ->
        {:ok, state}

      {:ok, ["OK", _event_id, false, message]} ->
        Logger.warning("NIP-46 event rejected: #{message}")
        {:ok, state}

      {:ok, ["EOSE", _sub_id]} ->
        {:ok, state}

      _ ->
        {:ok, state}
    end
  end

  defp handle_response_event(event, state) do
    # Decrypt the response
    case NIP04.decrypt(event["content"], state.client_privkey, event["pubkey"]) do
      {:ok, decrypted} ->
        case Jason.decode(decrypted) do
          {:ok, response} ->
            handle_response(response, state)

          {:error, _} ->
            Logger.warning("Failed to parse NIP-46 response")
            {:ok, state}
        end

      {:error, reason} ->
        Logger.warning("Failed to decrypt NIP-46 response: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp handle_response(%{"id" => request_id, "result" => result}, state) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        Logger.debug("Received response for unknown request: #{request_id}")
        {:ok, state}

      {from, pending_requests} ->
        GenServer.reply(from, {:ok, result})
        {:ok, %{state | pending_requests: pending_requests}}
    end
  end

  defp handle_response(%{"id" => request_id, "error" => error}, state) do
    case Map.pop(state.pending_requests, request_id) do
      {nil, _} ->
        {:ok, state}

      {from, pending_requests} ->
        GenServer.reply(from, {:error, error})
        {:ok, %{state | pending_requests: pending_requests}}
    end
  end

  defp handle_response(_, state), do: {:ok, state}

  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp generate_subscription_id do
    "nip46_#{:rand.uniform(1_000_000)}"
  end

  defp generate_secret do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end

# Simple WebSocket handler for NIP-46
defmodule Rss2Nostr.Nostr.NIP46.WebSocketHandler do
  use WebSockex

  def start_link(url, state) do
    WebSockex.start_link(url, __MODULE__, state)
  end

  @impl true
  def handle_frame({:text, message}, state) do
    send(state.parent, {:ws_message, message})
    {:ok, state}
  end

  @impl true
  def handle_disconnect(_reason, state) do
    send(state.parent, {:ws_closed, :disconnected})
    {:ok, state}
  end

  @impl true
  def handle_cast(:close, state) do
    {:close, state}
  end
end
