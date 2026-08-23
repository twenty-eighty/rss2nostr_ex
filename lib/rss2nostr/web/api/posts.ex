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

  @spec reprocess(String.t()) :: {:ok, Post.t()} | {:error, atom()}
  def reprocess(id) do
    with {:ok, post_id} <- parse_id(id),
         %Post{} = post <- Posts.get_post(post_id) do
      Processor.reprocess_post(post)
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  @spec publish(String.t(), map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def publish(id, _params \\ %{}) do
    with {:ok, post_id} <- parse_id(id),
         %Post{} = post <- Posts.get_post(post_id, preload: [:source]) do
      case publish_one(post) do
        {:ok, %{success: true} = result} -> {:ok, result}
        {:ok, result} -> {:error, result[:report] || "Publish failed"}
        {:error, reason} -> {:error, format_error(reason)}
      end
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  @spec publish_selected(map()) :: {:ok, map()} | {:error, atom() | String.t()}
  def publish_selected(params) do
    ids = List.wrap(params["post_ids"] || params["post_ids[]"] || [])

    posts =
      ids
      |> Posts.get_posts(preload: [:source])
      |> Enum.filter(&(&1.status == Post.status_processed()))

    publish_posts(posts)
  end

  @spec reprocess_selected(map()) :: {:ok, map()}
  def reprocess_selected(params) do
    ids = List.wrap(params["post_ids"] || params["post_ids[]"] || [])

    results =
      ids
      |> Posts.get_posts()
      |> Enum.map(&Processor.reprocess_post/1)

    {:ok,
     %{
       processed: Enum.count(results, &match?({:ok, _}, &1)),
       errors: Enum.count(results, &match?({:error, _}, &1))
     }}
  end

  @spec publish_posts([Post.t()]) :: {:ok, map()} | {:error, atom() | String.t()}
  def publish_posts([]), do: {:error, "No posts selected"}

  def publish_posts(posts) when is_list(posts) do
    results =
      Publisher.each_with_gap(posts, fn post ->
        case publish_one(post) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      end)

    classified = Enum.map(Enum.zip(posts, results), &classify_publish/1)
    published = Enum.count(classified, &(&1.status == :published))
    issues = for %{issue: issue} when is_binary(issue) <- classified, do: issue

    {:ok,
     %{
       published: published,
       failed: length(posts) - published,
       errors: issues,
       results: Enum.map(classified, & &1.result)
     }}
  end

  defp classify_publish({post, {:ok, %{success: true, failed_relays: []} = result}}) do
    %{status: :published, issue: nil, result: Map.put(result, :title, post.title)}
  end

  defp classify_publish({post, {:ok, %{success: true, report: report} = result}}) do
    %{
      status: :published,
      issue: post_issue(post, report),
      result: Map.put(result, :title, post.title)
    }
  end

  defp classify_publish({post, {:ok, result}}) do
    %{
      status: :failed,
      issue: post_issue(post, result[:report] || "Publish failed"),
      result: result
    }
  end

  defp classify_publish({post, {:error, reason}}) do
    %{status: :failed, issue: post_issue(post, format_error(reason)), result: nil}
  end

  defp post_issue(post, message) do
    title = post.title || "Post #{post.id}"
    "#{title}: #{message}"
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
      {:error, :no_source_signer} -> {:error, "Source has no signing key or bunker URL"}
      other -> other
    end
  end

  @spec update(String.t(), map()) ::
          {:ok, Post.t()} | {:error, atom() | String.t() | Ecto.Changeset.t()}
  def update(id, params) do
    with {:ok, post_id} <- parse_id(id),
         %Post{} = post <- Posts.get_post(post_id),
         :ok <- editable?(post) do
      Posts.update_post(post, editor_attrs(params))
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
      {:error, :not_editable} -> {:error, "Post cannot be edited in this status"}
    end
  end

  @spec revise(String.t()) :: {:ok, Post.t()} | {:error, atom() | String.t()}
  def revise(id) do
    with {:ok, post_id} <- parse_id(id),
         %Post{} = post <- Posts.get_post(post_id, preload: [:source]) do
      cond do
        post.status != Post.status_published() ->
          {:error, "Only published articles can be revised"}

        true ->
          case Processor.reprocess_post(post) do
            {:ok, post} -> {:ok, post}
            {:error, reason} -> {:error, format_error(reason)}
          end
      end
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  defp require_ready(post) do
    cond do
      post.status == Post.status_published() and not Blossom.pending_images?(post) ->
        {:ok, post}

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
        {:error, "Post is not ready to publish"}
    end
  end

  defp editable?(post) do
    if post.status in [Post.status_processed(), Post.status_published()] do
      :ok
    else
      {:error, :not_editable}
    end
  end

  defp editor_attrs(params) do
    %{}
    |> maybe_put(:title, params["title"])
    |> maybe_put(:summary, params["summary"])
    |> maybe_put(:content, params["content"])
    |> maybe_put(:language, blank_to_nil(params["language"]))
    |> maybe_put_categories(params)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_categories(attrs, params) do
    cond do
      Map.has_key?(params, "categories") ->
        Map.put(attrs, :categories, parse_categories(params["categories"]))

      Map.has_key?(params, "hashtags") ->
        Map.put(attrs, :categories, parse_categories(params["hashtags"]))

      true ->
        attrs
    end
  end

  defp parse_categories(nil), do: []

  defp parse_categories(list) when is_list(list),
    do: Enum.map(list, &to_string/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp parse_categories(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_categories(_), do: []

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: String.trim(value)
  defp blank_to_nil(value), do: value

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: Rss2Nostr.Nostr.Relay.format_error(reason)

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
      staged_at: post.staged_at,
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

      "staging" ->
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
