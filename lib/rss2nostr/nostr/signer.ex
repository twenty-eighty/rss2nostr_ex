defmodule Rss2Nostr.Nostr.Signer do
  @moduledoc """
  Resolves who signs a source's events and Blossom uploads.

  Encrypted drafts (NIP-37 kind 31234 wraps) and unencrypted kind 30024
  drafts use the app `NOSTR_NSEC`. Articles (kind 30023) use a per-source
  nsec or a bunker URL.

  Image uploads prefer the source nsec or bunker. The app key is a
  fallback for draft sources (drafts also need an author pubkey).
  """

  alias Rss2Nostr.Nostr.{Event, Keys, NIP46, Secret}
  alias Rss2Nostr.Sources.Source

  @type signer :: {:private_key, binary()} | {:bunker, String.t()}
  @type open_signer :: {:private_key, binary()} | {:bunker, pid()}

  @publish_as_values ~w(draft draft_plain article)

  @spec publish_as(Source.t() | map() | nil) :: String.t()
  def publish_as(%{publish_as: value}) when value in @publish_as_values, do: value
  def publish_as(%{default_post_kind: 30023}), do: "article"
  def publish_as(_), do: "draft"

  @spec draft?(Source.t() | map() | nil) :: boolean()
  def draft?(source), do: publish_as(source) in ~w(draft draft_plain)

  @spec encrypted_draft?(Source.t() | map() | nil) :: boolean()
  def encrypted_draft?(source), do: publish_as(source) == "draft"

  @spec plain_draft?(Source.t() | map() | nil) :: boolean()
  def plain_draft?(source), do: publish_as(source) == "draft_plain"

  @spec resolve(Source.t() | nil, keyword()) :: {:ok, signer()} | {:error, atom()}
  def resolve(source, opts \\ [])
  def resolve(nil, _opts), do: {:error, :no_source}

  def resolve(%Source{} = source, opts) do
    case publish_as(source) do
      "article" -> source_signer(source)
      value when value in ["draft", "draft_plain"] -> draft_signer(opts)
    end
  end

  @doc """
  App key from `NOSTR_NSEC` / `NOSTR_PRIVATE_KEY`.
  """
  @spec app_signer() :: {:ok, signer()} | {:error, atom()}
  def app_signer, do: app_private_key()

  @doc """
  Signer for Blossom image uploads.

  Uses the source nsec or bunker when either is set. Falls back to the
  app key only for draft sources that have an intended author pubkey.
  """
  @spec upload_signer(Source.t() | nil) :: {:ok, signer()} | {:error, atom()}
  def upload_signer(nil), do: {:error, :no_source}

  def upload_signer(%Source{} = source) do
    cond do
      signing_nsec_configured?(source) ->
        source_nsec(source)

      present?(source.bunker_connection) ->
        {:ok, {:bunker, source.bunker_connection}}

      plain_draft?(source) ->
        app_private_key()

      encrypted_draft?(source) and present?(source.pubkey) ->
        app_private_key()

      encrypted_draft?(source) ->
        {:error, :no_source_pubkey}

      true ->
        {:error, :no_source_signer}
    end
  end

  @doc """
  Opens a bunker connection when needed, runs `fun`, then disconnects.
  """
  @spec with_open(signer(), (open_signer() -> result)) :: result | {:error, term()}
        when result: var
  def with_open({:private_key, key}, fun), do: fun.({:private_key, key})

  def with_open({:bunker, pid}, fun) when is_pid(pid), do: fun.({:bunker, pid})

  def with_open({:bunker, url}, fun) when is_binary(url) do
    with {:ok, pid} <- NIP46.start_link(bunker_url: url),
         {:ok, _} <- NIP46.connect(pid) do
      try do
        fun.({:bunker, pid})
      after
        close({:bunker, pid})
      end
    end
  end

  @spec pubkey_hex(open_signer()) :: {:ok, String.t()} | {:error, term()}
  def pubkey_hex({:private_key, private_key}) do
    {:ok, private_key |> Keys.derive_public_key() |> Keys.to_hex()}
  end

  def pubkey_hex({:bunker, pid}) when is_pid(pid) do
    case NIP46.get_public_key(pid) do
      {:ok, pubkey} -> {:ok, String.downcase(pubkey)}
      error -> error
    end
  end

  @spec sign_event(open_signer(), map()) :: {:ok, map()} | {:error, term()}
  def sign_event({:private_key, private_key}, event), do: Event.sign_event(event, private_key)

  def sign_event({:bunker, pid}, event) when is_pid(pid) do
    case NIP46.sign_event(pid, event) do
      {:ok, signed} -> normalize_signed_event(signed, event)
      error -> error
    end
  end

  defp close({:bunker, pid}) when is_pid(pid) do
    NIP46.disconnect(pid)
    GenServer.stop(pid, :normal)
  rescue
    _ -> :ok
  end

  defp close(_), do: :ok

  defp normalize_signed_event(signed, event) when is_map(signed) do
    {:ok,
     %{
       id: signed["id"] || signed[:id],
       pubkey: signed["pubkey"] || signed[:pubkey] || event.pubkey,
       created_at: signed["created_at"] || signed[:created_at] || event.created_at,
       kind: signed["kind"] || signed[:kind] || event.kind,
       tags: signed["tags"] || signed[:tags] || event.tags,
       content: signed["content"] || signed[:content] || event.content,
       sig: signed["sig"] || signed[:sig]
     }}
  end

  defp normalize_signed_event(signed, event) when is_binary(signed) do
    case Jason.decode(signed) do
      {:ok, map} -> normalize_signed_event(map, event)
      _ -> {:error, :invalid_bunker_signature}
    end
  end

  defp normalize_signed_event(_, _), do: {:error, :invalid_bunker_signature}

  @doc """
  Hex pubkey of the intended Nostr author for this source.

  Uses the stored author pubkey, then a source nsec, then the bunker URL.
  """
  @spec author_pubkey(Source.t() | nil) :: String.t() | nil
  def author_pubkey(nil), do: nil

  def author_pubkey(%Source{} = source) do
    parse_hex(source.pubkey) || pubkey_from_nsec(source) || pubkey_from_bunker(source)
  end

  @spec configured?(Source.t() | nil) :: boolean()
  def configured?(source), do: match?({:ok, _}, resolve(source))

  @spec signing_nsec_configured?(Source.t() | nil) :: boolean()
  def signing_nsec_configured?(%{signing_nsec_ciphertext: value})
      when is_binary(value) and value != "",
      do: true

  def signing_nsec_configured?(_), do: false

  defp draft_signer(opts) do
    cond do
      key = Keyword.get(opts, :private_key) ->
        normalize_key(key)

      true ->
        app_private_key()
    end
  end

  defp source_signer(source) do
    cond do
      signing_nsec_configured?(source) ->
        source_nsec(source)

      present?(source.bunker_connection) ->
        {:ok, {:bunker, source.bunker_connection}}

      true ->
        {:error, :no_source_signer}
    end
  end

  defp source_nsec(source) do
    with {:ok, nsec} <- Secret.decrypt(source.signing_nsec_ciphertext) do
      Keys.parse_private_key(nsec) |> wrap_key()
    end
  end

  defp app_private_key do
    nsec =
      Application.get_env(:rss2nostr, :nostr, [])[:private_key] ||
        System.get_env("NOSTR_NSEC") ||
        System.get_env("NOSTR_PRIVATE_KEY")

    case nsec do
      value when is_binary(value) and value != "" ->
        Keys.parse_private_key(value) |> wrap_key()

      _ ->
        {:error, :no_app_private_key}
    end
  end

  defp normalize_key(key) when is_binary(key) and byte_size(key) == 32 do
    {:ok, {:private_key, key}}
  end

  defp normalize_key(key) when is_binary(key) do
    Keys.parse_private_key(key) |> wrap_key()
  end

  defp normalize_key(_), do: {:error, :invalid_private_key}

  defp wrap_key({:ok, key}), do: {:ok, {:private_key, key}}
  defp wrap_key({:error, reason}), do: {:error, reason}

  defp parse_hex(value) do
    case Keys.parse_public_key(value) do
      {:ok, hex} -> hex
      _ -> nil
    end
  end

  defp pubkey_from_nsec(source) do
    with true <- signing_nsec_configured?(source),
         {:ok, nsec} <- Secret.decrypt(source.signing_nsec_ciphertext),
         {:ok, key} <- Keys.parse_private_key(nsec) do
      key |> Keys.derive_public_key() |> Keys.to_hex()
    else
      _ -> nil
    end
  end

  defp pubkey_from_bunker(source) do
    with true <- present?(source.bunker_connection),
         {:ok, parsed} <- NIP46.parse_bunker_url(source.bunker_connection),
         {:ok, hex} <- Keys.parse_public_key(parsed.pubkey) do
      hex
    else
      _ -> nil
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
