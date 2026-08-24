defmodule Rss2Nostr.Nostr.Publisher.Preview do
  @moduledoc false

  alias Rss2Nostr.Nostr.{Keys, Relays, Signer}
  alias Rss2Nostr.Nostr.Publisher.{EventBuilder, PostContext, PostKind, PostLoader}
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources.Source

  @spec preview_event(Post.t() | map(), keyword()) :: map()
  def preview_event(post_or_attrs, opts \\ []) do
    source = Keyword.get(opts, :source) || source_of(post_or_attrs)
    post_or_attrs = post_or_attrs |> ensure_source_if_post() |> attach_source(source)
    pubkey = preview_pubkey(source, post_or_attrs)
    parts = EventBuilder.build_inner_events(post_or_attrs, pubkey)
    event = List.first(parts)
    relays = preview_relays(post_or_attrs, source)

    %{
      event: event,
      parts: parts,
      inner: nil,
      encrypted: false,
      draft: PostKind.encrypted_draft?(post_or_attrs),
      plain_draft: PostKind.plain_draft?(post_or_attrs),
      json: Jason.encode!(["EVENT", event], pretty: true),
      message: ["EVENT", event],
      relays: relays,
      signed: false
    }
  end

  @spec preview_pubkey(Source.t() | nil, Post.t() | map()) :: String.t()
  defp preview_pubkey(source, post) do
    author = PostKind.draft_author(post, source)

    cond do
      PostKind.encrypted_draft?(post) and Keys.valid_pubkey?(author) ->
        String.downcase(author)

      true ->
        case Signer.resolve(source) do
          {:ok, {:private_key, key}} ->
            key |> Keys.derive_public_key() |> Keys.to_hex()

          _ ->
            PostContext.field(source, :pubkey) || String.duplicate("0", 64)
        end
    end
  end

  @spec preview_relays(Post.t() | map(), Source.t() | nil) :: [String.t()]
  defp preview_relays(%Post{} = post, _source), do: Relays.publish_relays(post)
  defp preview_relays(_attrs, %Source{} = source), do: Relays.publish_relays(source)
  defp preview_relays(_, _), do: Relays.test()

  @spec attach_source(Post.t() | map(), Source.t() | nil) :: Post.t() | map()
  defp attach_source(%Post{} = post, %Source{} = source), do: %{post | source: source}
  defp attach_source(%Post{} = post, _), do: post
  defp attach_source(attrs, source) when is_map(attrs), do: Map.put(attrs, :source, source)
  defp attach_source(other, _), do: other

  @spec source_of(Post.t() | map()) :: Source.t() | nil
  defp source_of(%Post{source: %Source{} = source}), do: source
  defp source_of(%Post{} = post), do: PostLoader.ensure_source(post).source
  defp source_of(%{source: %Source{} = source}), do: source
  defp source_of(%{"source" => %Source{} = source}), do: source
  defp source_of(_), do: nil

  @spec ensure_source_if_post(Post.t() | map()) :: Post.t() | map()
  defp ensure_source_if_post(%Post{} = post), do: PostLoader.ensure_source(post)
  defp ensure_source_if_post(other), do: other
end
