defmodule Rss2Nostr.Nostr.Publisher.PostContext do
  @moduledoc false

  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources.Source

  @spec field(map() | Post.t() | nil, atom() | String.t()) :: term()
  def field(%{__struct__: _} = struct, key), do: Map.get(struct, key)

  def field(map, key) when is_map(map), do: map[key] || map[Atom.to_string(key)]
  def field(_, _), do: nil

  @spec source_of(map() | Post.t() | nil) :: Source.t() | nil
  def source_of(%Post{source: %Source{} = source}), do: source
  def source_of(%{source: %Source{} = source}), do: source
  def source_of(%{"source" => %Source{} = source}), do: source
  def source_of(_), do: nil

  @spec hashtag_list(map() | Source.t() | nil, atom() | String.t()) :: [String.t()]
  def hashtag_list(%{__struct__: _} = source, field) do
    case Map.get(source, field) do
      tags when is_list(tags) -> tags
      _ -> []
    end
  end

  def hashtag_list(source, field) when is_map(source) do
    source[field] || source[Atom.to_string(field)] || []
  end

  def hashtag_list(_, _), do: []
end
