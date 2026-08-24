defmodule Rss2Nostr.Nostr.Publisher.Signing do
  @moduledoc false

  alias Rss2Nostr.Nostr.{Event, Keys, NIP46, Signer}
  alias Rss2Nostr.Nostr.Publisher.{EventBuilder, Identifiers, PostKind}
  alias Rss2Nostr.Posts.Post

  @type signer :: {:private_key, binary()} | {:bunker, pid()}

  @spec resolve_signer(Post.t(), keyword()) :: {:ok, signer()} | {:error, term()}
  def resolve_signer(post, opts) do
    cond do
      Keyword.has_key?(opts, :signer) ->
        {:ok, Keyword.fetch!(opts, :signer)}

      Keyword.has_key?(opts, :private_key) ->
        {:ok, {:private_key, Keyword.fetch!(opts, :private_key)}}

      true ->
        Signer.resolve(post.source)
    end
  end

  @spec pubkey_for_signer(signer()) :: {:ok, String.t(), signer()} | {:error, term()}
  def pubkey_for_signer({:private_key, private_key}) do
    pubkey_hex = private_key |> Keys.derive_public_key() |> Keys.to_hex()
    {:ok, pubkey_hex, {:private_key, private_key}}
  end

  def pubkey_for_signer({:bunker, url}) do
    with {:ok, pid} <- NIP46.start_link(bunker_url: url),
         {:ok, _} <- NIP46.connect(pid),
         {:ok, pubkey} <- NIP46.get_public_key(pid) do
      {:ok, pubkey_hex(pubkey), {:bunker, pid}}
    end
  end

  @spec prepare_events(Post.t(), String.t(), signer()) :: {:ok, [map()]} | {:error, term()}
  def prepare_events(post, pubkey_hex, signer) do
    inners = EventBuilder.build_inner_events(post, inner_pubkey(post, pubkey_hex))

    if PostKind.encrypted_draft?(post) do
      wrap_all(inners, post, signer)
    else
      {:ok, inners}
    end
  end

  @spec sign_all(signer(), [map()]) :: {:ok, [map()]} | {:error, term()}
  def sign_all(signer, events) do
    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
      case sign_with(signer, event) do
        {:ok, signed} -> {:cont, {:ok, acc ++ [signed]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec close_signer(signer()) :: :ok
  def close_signer({:bunker, pid}) when is_pid(pid) do
    NIP46.disconnect(pid)
    GenServer.stop(pid, :normal)
  rescue
    _ -> :ok
  end

  def close_signer(_), do: :ok

  @spec sign_with(signer(), map()) :: {:ok, map()} | {:error, term()}
  def sign_with({:private_key, private_key}, event), do: Event.sign_event(event, private_key)

  def sign_with({:bunker, pid}, event) do
    case NIP46.sign_event(pid, event) do
      {:ok, signed} -> normalize_signed_event(signed, event)
      error -> error
    end
  end

  @spec wrap_all([map()], Post.t(), Signing.signer()) :: {:ok, [map()]} | {:error, term()}
  defp wrap_all(inners, post, signer) do
    Enum.reduce_while(inners, {:ok, []}, fn inner, {:ok, acc} ->
      case wrap_draft_event(inner, post, signer) do
        {:ok, wrap} -> {:cont, {:ok, acc ++ [wrap]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec wrap_draft_event(map(), Post.t(), Signing.signer()) :: {:ok, map()} | {:error, term()}
  defp wrap_draft_event(inner, post, {:private_key, key}) do
    Event.wrap_draft(inner, key,
      identifier: Identifiers.from_event(inner),
      author_pubkey: PostKind.draft_author(post)
    )
  end

  defp wrap_draft_event(_inner, _post, _), do: {:error, :cannot_encrypt_draft}

  @spec inner_pubkey(Post.t(), String.t()) :: String.t()
  defp inner_pubkey(post, signer_pubkey) do
    author = if PostKind.encrypted_draft?(post), do: PostKind.draft_author(post)

    if Keys.valid_pubkey?(author) do
      String.downcase(author)
    else
      signer_pubkey
    end
  end

  @spec normalize_signed_event(map() | binary(), map()) :: {:ok, map()} | {:error, term()}
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

  @spec pubkey_hex(String.t()) :: String.t()
  defp pubkey_hex(value) when is_binary(value), do: String.downcase(value)
end
