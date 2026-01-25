defmodule Rss2Nostr.Web.API.Posts do
  @moduledoc """
  API handlers for post operations.
  """

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.Processor
  alias Rss2Nostr.Nostr.{Publisher, Keys}

  @spec list(map()) :: map()
  def list(params \\ %{}) do
    status = params["status"]
    page = parse_integer(params["page"], 1)
    per_page = parse_integer(params["per_page"], 20)

    posts =
      if status && status != "" do
        status_int = status_to_int(status)
        Posts.list_posts_by_status(status_int)
      else
        Posts.list_posts()
      end

    # Pagination
    total = length(posts)
    posts = posts |> Enum.drop((page - 1) * per_page) |> Enum.take(per_page)

    %{
      posts: Enum.map(posts, &post_to_map/1),
      pagination: %{
        page: page,
        per_page: per_page,
        total: total,
        total_pages: ceil(total / per_page)
      }
    }
  end

  @spec get(String.t()) :: {:ok, map()} | {:error, :not_found | :invalid_id}
  def get(id) do
    with {:ok, post_id} <- parse_id(id),
         %Post{} = post <- Posts.get_post(post_id) do
      {:ok, post_to_map(post)}
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  @spec process(String.t()) :: {:ok, Post.t()} | {:error, atom()}
  def process(id) do
    with {:ok, post_id} <- parse_id(id),
         %Post{} = post <- Posts.get_post(post_id) do
      Processor.process_post(post)
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  @spec publish(String.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def publish(id) do
    with {:ok, post_id} <- parse_id(id),
         %Post{} = post <- Posts.get_post(post_id) do
      nsec = System.get_env("NOSTR_NSEC")

      if is_nil(nsec) do
        {:error, "NOSTR_NSEC not configured"}
      else
        case Keys.parse_private_key(nsec) do
          {:ok, private_key} ->
            relays =
              Application.get_env(:rss2nostr, :default_relays, [
                "wss://relay.damus.io",
                "wss://nos.lol",
                "wss://relay.nostr.band"
              ])

            Publisher.publish_post(post, private_key: private_key, relays: relays)

          {:error, reason} ->
            {:error, "Invalid NSEC: #{inspect(reason)}"}
        end
      end
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  @spec delete(String.t()) :: {:ok, Post.t()} | {:error, atom()}
  def delete(id) do
    with {:ok, post_id} <- parse_id(id),
         %Post{} = post <- Posts.get_post(post_id) do
      Posts.delete_post(post)
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  def stats do
    %{
      total: Posts.count_posts(),
      new: Posts.count_posts_by_status(Post.status_new()),
      processing: Posts.count_posts_by_status(Post.status_processing()),
      processed: Posts.count_posts_by_status(Post.status_processed()),
      published: Posts.count_posts_by_status(Post.status_published()),
      error: Posts.count_posts_by_status(Post.status_error())
    }
  end

  defp post_to_map(post) do
    %{
      id: post.id,
      title: post.title,
      url: post.source_url,
      status: Post.status_name(post.status),
      source_id: post.source_id,
      published_at: post.published_at,
      nostr_event_id: post.event_id,
      inserted_at: post.inserted_at,
      updated_at: post.updated_at
    }
  end

  defp status_to_int(status) do
    case status do
      "new" -> Post.status_new()
      "processing" -> Post.status_processing()
      "processed" -> Post.status_processed()
      "published" -> Post.status_published()
      "error" -> Post.status_error()
      _ -> -1
    end
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} when int_id > 0 -> {:ok, int_id}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_), do: {:error, :invalid_id}

  defp parse_integer(nil, default), do: default

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp parse_integer(_, default), do: default
end
