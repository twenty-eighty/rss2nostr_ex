defmodule Rss2Nostr.Web.API.Posts do
  @moduledoc """
  API handlers for post operations.
  """

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.Processor
  alias Rss2Nostr.Nostr.{Blossom, Publisher, Relays, Signer}

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

  @spec publish(String.t(), map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def publish(id, _params \\ %{}) do
    with {:ok, post_id} <- parse_id(id),
         %Post{} = post <- Posts.get_post(post_id, preload: [:source]) do
      case publish_posts([post]) do
        {:ok, %{published: 1} = result} -> {:ok, result}
        {:ok, %{errors: [reason | _]}} -> {:error, reason}
        {:ok, result} -> {:error, result[:error] || "Publish failed"}
      end
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  @spec publish_selected(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def publish_selected(params) do
    ids = List.wrap(params["post_ids"] || params["post_ids[]"] || [])
    posts = Posts.get_posts(ids, preload: [:source])
    publish_posts(posts)
  end

  @spec publish_posts([Post.t()]) :: {:ok, map()} | {:error, atom() | String.t()}
  def publish_posts([]), do: {:error, "No posts selected"}

  def publish_posts(posts) when is_list(posts) do
    results =
      Enum.map(posts, fn post ->
        case publish_one(post) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      end)

    published = Enum.count(results, &match?({:ok, _}, &1))
    errors = for {:error, reason} <- results, do: format_error(reason)

    {:ok, %{published: published, failed: length(errors), errors: errors}}
  end

  defp publish_one(%Post{} = post) do
    post = Posts.preload_source(post)

    with {:ok, post} <- require_ready(post),
         {:ok, signer} <- Signer.resolve(post.source) do
      Publisher.publish_post(post,
        signer: signer,
        relays: Relays.publish_relays(post)
      )
    else
      {:error, :no_app_private_key} -> {:error, "NOSTR_NSEC not configured"}
      {:error, :cannot_encrypt_draft} -> {:error, "NOSTR_NSEC is required to encrypt drafts"}
      {:error, :no_source_signer} -> {:error, "Source has no signing key or bunker URL"}
      other -> other
    end
  end

  defp require_ready(post) do
    cond do
      post.status == Post.status_processed() and not Blossom.pending_images?(post) ->
        {:ok, post}

      post.status in [Post.status_processed(), Post.status_pending_images()] ->
        {:ok, ready} = Processor.ensure_images(post)

        if ready.status == Post.status_processed() do
          {:ok, ready}
        else
          {:error, "Images are not uploaded yet"}
        end

      true ->
        {:error, "Post is not processed"}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

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
      pending_images: Posts.count_posts_by_status(Post.status_pending_images()),
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
      "new" ->
        Post.status_new()

      "processing" ->
        Post.status_processing()

      "processed" ->
        Post.status_processed()

      "pending_images" ->
        Post.status_pending_images()

      "published" ->
        Post.status_published()

      "error" ->
        Post.status_error()

      other ->
        case Integer.parse(other) do
          {status, ""} -> status
          _ -> -1
        end
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
