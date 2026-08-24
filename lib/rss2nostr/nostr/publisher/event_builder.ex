defmodule Rss2Nostr.Nostr.Publisher.EventBuilder do
  @moduledoc false

  alias Rss2Nostr.Nostr.{Event, NIP92}
  alias Rss2Nostr.Nostr.Publisher.{Identifiers, PostContext, PostKind}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.ArticleSplit

  @spec build_inner_events(map(), String.t()) :: [map()]
  def build_inner_events(post, pubkey_hex) do
    content = PostContext.field(post, :content) || ""
    chunks = split_content(post, pubkey_hex, content)
    total = length(chunks)

    chunks
    |> Enum.with_index(1)
    |> Enum.map(fn {chunk, index} ->
      build_event(post, pubkey_hex, content: chunk, index: index, total: total)
    end)
  end

  @spec split_content(map(), String.t(), String.t()) :: [String.t()]
  def split_content(post, pubkey_hex, content) do
    ArticleSplit.split(
      content,
      fn chunk, index ->
        measure_published_size(post, pubkey_hex, chunk, index)
      end,
      max_size: Event.max_event_size()
    )
  end

  @spec measure_published_size(map(), String.t(), String.t(), integer()) :: integer()
  def measure_published_size(post, pubkey_hex, chunk, index) do
    inner = build_event(post, pubkey_hex, content: chunk, index: index, total: 99)

    if PostKind.encrypted_draft?(post) do
      Event.estimate_wrap_message_size(inner, author_pubkey: PostKind.draft_author(post))
    else
      Event.estimate_event_message_size(inner)
    end
  end

  @spec build_event(map(), String.t(), keyword()) :: map()
  def build_event(post, pubkey_hex, opts) do
    index = Keyword.get(opts, :index, 1)
    total = Keyword.get(opts, :total, 1)
    content = Keyword.get(opts, :content) || PostContext.field(post, :content) || ""
    title = Identifiers.part_title(PostContext.field(post, :title) || "Untitled", index, total)
    identifier = Identifiers.part_identifier(Identifiers.from_post(post), index, total)

    Event.build_long_form(pubkey_hex, content,
      title: title,
      summary: PostContext.field(post, :summary),
      image: PostContext.field(post, :image),
      published_at: part_published_at(PostContext.field(post, :published_at), index, total),
      identifier: identifier,
      hashtags: publish_hashtags(post),
      language: PostContext.field(post, :language),
      canonical_url: PostContext.field(post, :source_url),
      imeta:
        NIP92.tags_for_event(images_of(post), content, featured: PostContext.field(post, :image)),
      kind: PostKind.long_form_kind(post),
      author_pubkey: PostKind.draft_author(post),
      client: PostKind.public_article?(post)
    )
  end

  @spec publish_hashtags(map()) :: [String.t()]
  def publish_hashtags(post) do
    source = PostContext.source_of(post)

    Event.merge_hashtags(
      PostContext.field(post, :categories),
      PostContext.hashtag_list(source, :fixed_hashtags),
      PostContext.hashtag_list(source, :excluded_hashtags)
    )
  end

  @spec part_published_at(DateTime.t() | integer() | nil, integer(), integer()) ::
          integer() | nil
  def part_published_at(published_at, _index, 1), do: unix_published_at(published_at)

  def part_published_at(published_at, index, _total) do
    base = unix_published_at(published_at) || System.os_time(:second)
    base + (index - 1)
  end

  defp images_of(%Post{} = post) do
    post = if Ecto.assoc_loaded?(post.images), do: post, else: Posts.preload_images(post)
    post.images || []
  end

  defp images_of(_), do: []

  defp unix_published_at(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp unix_published_at(unix) when is_integer(unix), do: unix
  defp unix_published_at(_), do: nil
end
