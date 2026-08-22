defmodule Rss2Nostr.Nostr.Publisher.PostLoader do
  @moduledoc false

  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Repo

  @spec ensure_source(Post.t()) :: Post.t()
  def ensure_source(%Post{} = post) do
    post
    |> maybe_preload(:source)
    |> maybe_preload(:images)
  end

  defp maybe_preload(post, assoc) do
    if Ecto.assoc_loaded?(Map.get(post, assoc)), do: post, else: Repo.preload(post, [assoc])
  end
end
