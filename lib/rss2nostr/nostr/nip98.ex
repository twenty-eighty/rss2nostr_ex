defmodule Rss2Nostr.Nostr.NIP98 do
  @moduledoc """
  Implements NIP-98 HTTP Auth.

  Creates authorization events (kind 27235) for authenticating HTTP requests
  to HTTP endpoints.

  The auth event contains:
  - kind: 27235
  - tags: [["u", url], ["method", method], optionally ["payload", sha256]]
  - created_at: current timestamp
  - content: "" (empty)
  """

  alias Rss2Nostr.Nostr.Keys

  @kind_http_auth 27235

  @doc """
  Creates a NIP-98 authorization header value.

  Options:
  - :payload_hash - SHA256 hash of request body (for POST/PUT)
  - :expiration - Custom expiration (default: 60 seconds from now)

  Returns {:ok, "Nostr base64_event"} or {:error, reason}
  """
  @spec create_auth(String.t(), String.t(), binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def create_auth(url, method, private_key, opts \\ []) do
    payload_hash = Keyword.get(opts, :payload_hash)

    # Derive public key
    pubkey_bin = Keys.derive_public_key(private_key)
    pubkey_hex = Keys.to_hex(pubkey_bin)

    # Build tags
    tags = [
      ["u", url],
      ["method", String.upcase(method)]
    ]

    tags =
      if payload_hash do
        tags ++ [["payload", payload_hash]]
      else
        tags
      end

    # Build the auth event
    event = %{
      pubkey: pubkey_hex,
      created_at: System.os_time(:second),
      kind: @kind_http_auth,
      tags: tags,
      content: ""
    }

    # Sign the event
    case Keys.sign_event(event, private_key) do
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

        # Encode as base64
        event_json = Jason.encode!(signed_event)
        auth_value = "Nostr #{Base.encode64(event_json)}"

        {:ok, auth_value}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verifies a NIP-98 authorization header.

  Returns {:ok, pubkey} if valid, {:error, reason} otherwise.
  """
  @spec verify_auth(String.t(), String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def verify_auth(auth_header, url, method, opts \\ []) do
    expected_payload_hash = Keyword.get(opts, :payload_hash)
    max_age = Keyword.get(opts, :max_age, 60)

    with {:ok, event} <- decode_auth_header(auth_header),
         :ok <- verify_event_signature(event),
         :ok <- verify_url_tag(event, url),
         :ok <- verify_method_tag(event, method),
         :ok <- verify_payload_tag(event, expected_payload_hash),
         :ok <- verify_timestamp(event, max_age) do
      {:ok, event["pubkey"]}
    end
  end

  @spec decode_auth_header(String.t()) :: {:ok, map()} | {:error, atom()}
  defp decode_auth_header(header) do
    with ["Nostr", base64_event] <- String.split(header, " ", parts: 2),
         {:ok, json} <- Base.decode64(base64_event),
         {:ok, event} <- Jason.decode(json) do
      {:ok, event}
    else
      :error -> {:error, :invalid_base64}
      {:error, _} -> {:error, :invalid_json}
      _ -> {:error, :invalid_auth_format}
    end
  end

  @spec verify_event_signature(map()) :: :ok | {:error, atom()}
  defp verify_event_signature(event) do
    expected_id = compute_event_id(event)

    with :ok <- verify_event_id(event["id"], expected_id),
         {:ok, id_bin} <- Keys.from_hex(event["id"]),
         {:ok, sig_bin} <- Keys.from_hex(event["sig"]),
         {:ok, pubkey_bin} <- Keys.from_hex(event["pubkey"]) do
      if Keys.verify(id_bin, sig_bin, pubkey_bin) do
        :ok
      else
        {:error, :invalid_signature}
      end
    end
  end

  @spec compute_event_id(map()) :: String.t()
  defp compute_event_id(event) do
    [0, event["pubkey"], event["created_at"], event["kind"], event["tags"], event["content"]]
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec verify_event_id(String.t(), String.t()) :: :ok | {:error, atom()}
  defp verify_event_id(id, expected_id) when id == expected_id, do: :ok
  defp verify_event_id(_, _), do: {:error, :invalid_event_id}

  @spec verify_url_tag(map(), String.t()) :: :ok | {:error, atom()}
  defp verify_url_tag(event, expected_url) do
    case find_tag(event["tags"], "u") do
      nil ->
        {:error, :missing_url_tag}

      url ->
        if normalize_url(url) == normalize_url(expected_url),
          do: :ok,
          else: {:error, :url_mismatch}
    end
  end

  @spec verify_method_tag(map(), String.t()) :: :ok | {:error, atom()}
  defp verify_method_tag(event, expected_method) do
    case find_tag(event["tags"], "method") do
      nil ->
        {:error, :missing_method_tag}

      method ->
        if String.upcase(method) == String.upcase(expected_method),
          do: :ok,
          else: {:error, :method_mismatch}
    end
  end

  @spec verify_payload_tag(map(), String.t() | nil) :: :ok | {:error, atom()}
  defp verify_payload_tag(_event, nil), do: :ok

  defp verify_payload_tag(event, expected_hash) do
    case find_tag(event["tags"], "payload") do
      nil -> {:error, :missing_payload_tag}
      hash -> if hash == expected_hash, do: :ok, else: {:error, :payload_mismatch}
    end
  end

  @spec verify_timestamp(map(), non_neg_integer()) :: :ok | {:error, atom()}
  defp verify_timestamp(event, max_age) do
    now = System.os_time(:second)
    created_at = event["created_at"]

    cond do
      created_at > now + 60 -> {:error, :timestamp_in_future}
      now - created_at > max_age -> {:error, :timestamp_expired}
      true -> :ok
    end
  end

  @spec find_tag(list() | term(), String.t()) :: String.t() | nil
  defp find_tag(tags, name) when is_list(tags) do
    case Enum.find(tags, fn [tag | _] -> tag == name end) do
      [_, value | _] -> value
      _ -> nil
    end
  end

  defp find_tag(_, _), do: nil

  @spec normalize_url(String.t()) :: String.t()
  defp normalize_url(url) do
    # Normalize URL for comparison (remove trailing slash, etc.)
    url
    |> String.trim()
    |> String.trim_trailing("/")
    |> String.downcase()
  end
end
