defmodule Rss2Nostr.Posts do
  @moduledoc """
  Context for managing posts/articles.
  """

  import Ecto.Query
  alias Rss2Nostr.Repo
  alias Rss2Nostr.Import.ItemIdentity
  alias Rss2Nostr.Nostr.StagingNotify
  alias Rss2Nostr.Posts.{Post, ArticleImage}
  alias Rss2Nostr.Sources.Source

  # Post queries

  @doc """
  Returns all posts.
  """
  @spec list_posts(keyword()) :: [Post.t()]
  def list_posts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    Post
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_source(Keyword.get(opts, :source_id))
    |> maybe_filter_term(Keyword.get(opts, :q))
    |> order_by([p], desc: p.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns posts by status (accepts integer or string status).
  """
  @spec list_posts_by_status(integer() | String.t(), keyword()) :: [Post.t()]
  def list_posts_by_status(status, opts \\ [])

  def list_posts_by_status(status, opts) when is_integer(status) do
    list_posts(Keyword.put(opts, :status, status))
  end

  def list_posts_by_status(status_name, opts) when is_binary(status_name) do
    status = status_from_name(status_name)
    list_posts_by_status(status, opts)
  end

  @doc """
  Returns new posts (status = 0).
  """
  @spec list_new_posts(keyword()) :: [Post.t()]
  def list_new_posts(opts \\ []) do
    list_posts_by_status(Post.status_new(), opts)
  end

  @doc """
  Returns posts whose Markdown is ready but images still need uploading.
  """
  @spec list_pending_image_posts(keyword()) :: [Post.t()]
  def list_pending_image_posts(opts \\ []) do
    list_posts_by_status(Post.status_pending_images(), opts)
  end

  @doc """
  Returns posts the process task should handle: new articles and
  articles waiting on image uploads.
  """
  @spec list_processable_posts(keyword()) :: [Post.t()]
  def list_processable_posts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    statuses = [Post.status_new(), Post.status_pending_images()]

    Post
    |> where([p], p.status in ^statuses)
    |> order_by([p], asc: p.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns processed posts ready for export.
  Processed means content and images are ready.
  """
  @spec list_processed_posts(keyword()) :: [Post.t()]
  def list_processed_posts(opts \\ []) do
    list_posts_by_status(Post.status_processed(), opts)
  end

  @doc """
  Staging posts on active automated sources whose hold has elapsed.
  """
  @spec list_exportable_posts(keyword()) :: [Post.t()]
  def list_exportable_posts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    now = utc_now()

    Post
    |> join(:inner, [p], s in Source, on: p.source_id == s.id)
    |> where([p, s], p.status == ^Post.status_processed())
    |> where([p, s], s.active == true and s.mode == "automated")
    |> where(
      [p, s],
      is_nil(p.staged_at) or
        datetime_add(p.staged_at, s.staging_hold_minutes, "minute") <= ^now
    )
    |> order_by([p], asc: p.staged_at)
    |> limit(^limit)
    |> preload([p, s], source: s)
    |> Repo.all()
  end

  @doc """
  Published posts whose app-signed drafts have not been cleaned up yet.
  """
  @spec list_draft_cleanup_candidates(keyword()) :: [Post.t()]
  def list_draft_cleanup_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Post
    |> join(:inner, [p], s in Source, on: p.source_id == s.id)
    |> where([p], p.status == ^Post.status_published())
    |> where([p], is_nil(p.draft_cleaned_at))
    |> order_by([p], asc: p.id)
    |> limit(^limit)
    |> preload([p, s], source: s)
    |> Repo.all()
  end

  @spec mark_draft_cleaned(Post.t()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def mark_draft_cleaned(%Post{} = post) do
    update_post(post, %{draft_cleaned_at: utc_now()})
  end

  @doc """
  Published posts whose app-signed drafts have already been deleted.
  """
  @spec count_draft_cleaned() :: non_neg_integer()
  def count_draft_cleaned do
    Post
    |> where([p], not is_nil(p.draft_cleaned_at))
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Published posts still waiting for draft cleanup.
  """
  @spec count_draft_cleanup_candidates() :: non_neg_integer()
  def count_draft_cleanup_candidates do
    Post
    |> where([p], p.status == ^Post.status_published())
    |> where([p], is_nil(p.draft_cleaned_at))
    |> Repo.aggregate(:count, :id)
  end

  @spec hold_elapsed?(Post.t(), DateTime.t()) :: boolean()
  def hold_elapsed?(%Post{} = post, now \\ utc_now()) do
    post = preload_source(post)
    hold = (post.source && post.source.staging_hold_minutes) || 0

    cond do
      is_nil(post.staged_at) -> true
      hold <= 0 -> true
      true -> DateTime.compare(DateTime.add(post.staged_at, hold, :minute), now) != :gt
    end
  end

  @doc """
  Returns posts for a source, newest first.
  """
  @spec list_posts_for_source(integer(), keyword()) :: [Post.t()]
  def list_posts_for_source(source_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Post
    |> where([p], p.source_id == ^source_id)
    |> order_by([p], desc: p.published_at, desc: p.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns posts by a list of IDs, preloaded with their source.
  """
  @spec get_posts([integer() | binary()], keyword()) :: [Post.t()]
  def get_posts(ids, opts \\ []) when is_list(ids) do
    ids = Enum.flat_map(ids, &parse_post_id/1)

    posts =
      Post
      |> where([p], p.id in ^ids)
      |> Repo.all()

    case Keyword.get(opts, :preload) do
      nil -> posts
      assocs -> Repo.preload(posts, assocs)
    end
  end

  @spec parse_post_id(integer() | binary()) :: [pos_integer()]
  defp parse_post_id(id) when is_integer(id) and id > 0, do: [id]

  defp parse_post_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} when int > 0 -> [int]
      _ -> []
    end
  end

  defp parse_post_id(_), do: []

  @doc """
  Gets a single post by ID.
  """
  @spec get_post(integer() | binary(), keyword()) :: Post.t() | nil
  def get_post(id, opts \\ []) do
    case Repo.get(Post, id) do
      nil ->
        nil

      post ->
        case Keyword.get(opts, :preload) do
          nil -> post
          assocs -> Repo.preload(post, assocs)
        end
    end
  end

  @doc """
  Gets a single post by ID, raises if not found.
  """
  @spec get_post!(integer() | binary()) :: Post.t()
  def get_post!(id), do: Repo.get!(Post, id)

  @doc """
  Gets a post by source URL hash, optionally limited to one source.
  """
  @spec get_post_by_url_hash(String.t(), integer() | nil) :: Post.t() | nil
  def get_post_by_url_hash(hash, source_id \\ nil)

  def get_post_by_url_hash(hash, nil) do
    Repo.get_by(Post, source_url_hash: hash)
  end

  def get_post_by_url_hash(hash, source_id) do
    Repo.get_by(Post, source_url_hash: hash, source_id: source_id)
  end

  @doc """
  Checks if a post exists by URL hash.

  When `source_id` is given, only posts belonging to that source count.
  Orphaned posts (source deleted) do not count as duplicates for a new source.
  """
  @spec exists_by_url_hash?(String.t(), integer() | nil) :: boolean()
  def exists_by_url_hash?(hash, source_id \\ nil)

  def exists_by_url_hash?(hash, nil) do
    Post
    |> where([p], p.source_url_hash == ^hash)
    |> Repo.exists?()
  end

  def exists_by_url_hash?(hash, source_id) when is_integer(source_id) do
    Post
    |> where([p], p.source_url_hash == ^hash and p.source_id == ^source_id)
    |> Repo.exists?()
  end

  @doc """
  True when a post already stores one of these `<link>` / `<guid>` values.

  URL variants (scheme, www, trailing slash) are included. When `pubkey` is
  set, only that author's posts count.
  """
  @spec exists_by_identity?([String.t()], keyword()) :: boolean()
  def exists_by_identity?(values, opts \\ []) when is_list(values) do
    keys = ItemIdentity.lookup_keys(values)

    if keys == [] do
      false
    else
      hashes =
        keys
        |> Enum.map(&Post.generate_url_hash/1)
        |> Enum.reject(&is_nil/1)

      pubkey = Keyword.get(opts, :pubkey)

      Post
      |> where(
        [p],
        p.source_url in ^keys or p.article_identifier in ^keys or p.source_url_hash in ^hashes
      )
      |> maybe_filter_pubkey(pubkey)
      |> Repo.exists?()
    end
  end

  @spec maybe_filter_pubkey(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Queryable.t()
  defp maybe_filter_pubkey(query, pubkey) when is_binary(pubkey) and pubkey != "" do
    where(query, [p], p.pubkey == ^pubkey)
  end

  defp maybe_filter_pubkey(query, _), do: query

  @doc """
  Reassigns a post left without a source (after the old source was deleted)
  to `source_id`. Returns `:none` when no orphan exists for that hash.
  """
  @spec adopt_orphaned_by_url_hash(String.t(), integer()) ::
          {:ok, Post.t()} | {:error, Ecto.Changeset.t()} | :none
  def adopt_orphaned_by_url_hash(hash, source_id) when is_integer(source_id) do
    post =
      Post
      |> where([p], p.source_url_hash == ^hash and is_nil(p.source_id))
      |> limit(1)
      |> Repo.one()

    case post do
      nil -> :none
      post -> update_post(post, %{source_id: source_id})
    end
  end

  @doc """
  Creates a new post.
  """
  @spec create_post(map()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def create_post(attrs \\ %{}) do
    %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a post.
  """
  @spec update_post(Post.t(), map()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def update_post(%Post{} = post, attrs) do
    post
    |> Post.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a post.
  """
  @spec delete_post(Post.t()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def delete_post(%Post{} = post) do
    Repo.delete(post)
  end

  @doc """
  Updates the post status.
  """
  @spec update_status(Post.t(), integer()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def update_status(%Post{} = post, status) do
    update_post(post, %{status: status})
  end

  @doc """
  Marks a post as processing.
  """
  @spec mark_processing(Post.t()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def mark_processing(%Post{} = post) do
    update_status(post, Post.status_processing())
  end

  @doc """
  Marks a post as processed. Call only when images are uploaded or absent.
  """
  @spec mark_processed(Post.t()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def mark_processed(%Post{} = post) do
    enter_staging(post)
  end

  @doc """
  Moves a complete article into staging.

  The first time, or when `reset_hold: true` (Revise), `staged_at` is
  stamped and a NIP-17 DM is sent. Reprocess of an already staged
  article keeps the original hold and does not notify again.
  """
  @spec enter_staging(Post.t(), keyword()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def enter_staging(%Post{} = post, opts \\ []) do
    reset_hold? = Keyword.get(opts, :reset_hold, false)
    notify? = Keyword.get(opts, :notify, true)
    stamp? = is_nil(post.staged_at) or reset_hold?

    attrs = %{status: Post.status_processed(), last_error: nil}
    attrs = if stamp?, do: Map.put(attrs, :staged_at, utc_now()), else: attrs

    with {:ok, post} <- update_post(post, attrs) do
      if notify? and stamp? do
        _ = StagingNotify.maybe_notify(post)
      end

      {:ok, post}
    end
  end

  @doc """
  Returns a published article to staging and restarts the hold.
  """
  @spec revise_to_staging(Post.t()) ::
          {:ok, Post.t()} | {:error, :not_published | Ecto.Changeset.t()}
  def revise_to_staging(%Post{} = post) do
    if post.status == Post.status_published() do
      enter_staging(post, reset_hold: true)
    else
      {:error, :not_published}
    end
  end

  @spec utc_now() :: DateTime.t()
  defp utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  @doc """
  Marks a post as waiting on image uploads so processing can be finished later.
  """
  @spec mark_pending_images(Post.t(), String.t() | nil) ::
          {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def mark_pending_images(%Post{} = post, error_message \\ nil) do
    attrs = %{status: Post.status_pending_images()}
    attrs = if error_message, do: Map.put(attrs, :last_error, error_message), else: attrs
    update_post(post, attrs)
  end

  @doc """
  Marks a post as published with event ID, pubkey, and naddr.
  """
  @spec mark_published(Post.t(), String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def mark_published(%Post{} = post, event_id, pubkey \\ nil, nostr_address \\ nil) do
    update_post(post, %{
      status: Post.status_published(),
      event_id: event_id,
      pubkey: pubkey,
      nostr_address: nostr_address,
      last_error: nil
    })
  end

  @doc """
  Marks a post as error with message.
  """
  @spec mark_error(Post.t(), String.t()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def mark_error(%Post{} = post, error_message) do
    update_post(post, %{
      status: Post.status_error(),
      last_error: error_message
    })
  end

  @doc """
  Returns post counts grouped by status.
  """
  @spec count_by_status() :: %{integer() => non_neg_integer()}
  def count_by_status do
    Post
    |> group_by([p], p.status)
    |> select([p], {p.status, count(p.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Returns the total count of posts.
  """
  @spec count_posts() :: non_neg_integer()
  def count_posts do
    count_posts([])
  end

  @doc """
  Returns the count of posts matching the same filters as `list_posts/1`.
  """
  @spec count_posts(keyword()) :: non_neg_integer()
  def count_posts(opts) when is_list(opts) do
    Post
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_source(Keyword.get(opts, :source_id))
    |> maybe_filter_term(Keyword.get(opts, :q))
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Returns the count of posts with a specific status.
  """
  @spec count_posts_by_status(integer() | String.t()) :: non_neg_integer()
  def count_posts_by_status(status) when is_integer(status) do
    Post
    |> where([p], p.status == ^status)
    |> Repo.aggregate(:count, :id)
  end

  def count_posts_by_status(status_name) when is_binary(status_name) do
    status = status_from_name(status_name)
    count_posts_by_status(status)
  end

  @doc """
  Returns recent posts (alias for list_posts with descending order).
  """
  @spec list_recent_posts(keyword()) :: [Post.t()]
  def list_recent_posts(opts \\ []) do
    list_posts(opts)
  end

  @spec maybe_filter_status(Ecto.Queryable.t(), integer() | String.t() | nil) ::
          Ecto.Queryable.t()
  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query

  defp maybe_filter_status(query, status) when is_integer(status) do
    where(query, [p], p.status == ^status)
  end

  defp maybe_filter_status(query, status) when is_binary(status) do
    maybe_filter_status(query, status_from_name(status))
  end

  @spec maybe_filter_source(Ecto.Queryable.t(), integer() | String.t() | nil) ::
          Ecto.Queryable.t()
  defp maybe_filter_source(query, nil), do: query
  defp maybe_filter_source(query, ""), do: query

  defp maybe_filter_source(query, source_id) when is_integer(source_id) do
    where(query, [p], p.source_id == ^source_id)
  end

  defp maybe_filter_source(query, source_id) when is_binary(source_id) do
    case Integer.parse(source_id) do
      {id, ""} -> maybe_filter_source(query, id)
      _ -> query
    end
  end

  @spec maybe_filter_term(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Queryable.t()
  defp maybe_filter_term(query, nil), do: query
  defp maybe_filter_term(query, ""), do: query

  defp maybe_filter_term(query, term) when is_binary(term) do
    trimmed = String.trim(term)

    if trimmed == "" do
      query
    else
      pattern = "%" <> like_pattern(trimmed) <> "%"

      where(
        query,
        [p],
        ilike(p.title, ^pattern) or
          ilike(p.content, ^pattern) or
          ilike(p.summary, ^pattern) or
          ilike(p.source_url, ^pattern)
      )
    end
  end

  @spec like_pattern(String.t()) :: String.t()
  defp like_pattern(term) do
    String.replace(term, ~r/[%_\\]/, "")
  end

  @spec status_from_name(String.t()) :: integer()
  defp status_from_name(name) do
    case name do
      "new" ->
        Post.status_new()

      "processing" ->
        Post.status_processing()

      "processed" ->
        Post.status_processed()

      "staging" ->
        Post.status_processed()

      "signing" ->
        Post.status_signing()

      "signed" ->
        Post.status_signed()

      "publishing" ->
        Post.status_publishing()

      "published" ->
        Post.status_published()

      "blocked" ->
        Post.status_blocked()

      "error" ->
        Post.status_error()

      "pending_images" ->
        Post.status_pending_images()

      "pending images" ->
        Post.status_pending_images()

      other ->
        case Integer.parse(other) do
          {status, ""} -> status
          _ -> -1
        end
    end
  end

  # Article Image queries

  @doc """
  Gets all images for a post.
  """
  @spec list_images_for_post(integer()) :: [ArticleImage.t()]
  def list_images_for_post(post_id) do
    ArticleImage
    |> where([i], i.post_id == ^post_id)
    |> Repo.all()
  end

  @doc """
  Gets images that haven't been uploaded yet.
  """
  @spec list_pending_images(integer()) :: [ArticleImage.t()]
  def list_pending_images(post_id) do
    ArticleImage
    |> where([i], i.post_id == ^post_id)
    |> where([i], is_nil(i.uploaded_url))
    |> where([i], i.fetch_error == false)
    |> Repo.all()
  end

  @doc """
  Creates an article image.
  """
  @spec create_image(map()) :: {:ok, ArticleImage.t()} | {:error, Ecto.Changeset.t()}
  def create_image(attrs) do
    %ArticleImage{}
    |> ArticleImage.changeset(attrs)
    |> Repo.insert()
  end

  @spec delete_image(ArticleImage.t()) :: {:ok, ArticleImage.t()} | {:error, Ecto.Changeset.t()}
  def delete_image(%ArticleImage{} = image) do
    Repo.delete(image)
  end

  @doc """
  Updates an article image.
  """
  @spec update_image(ArticleImage.t(), map()) ::
          {:ok, ArticleImage.t()} | {:error, Ecto.Changeset.t()}
  def update_image(%ArticleImage{} = image, attrs) do
    image
    |> ArticleImage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks an image as uploaded.
  """
  @spec mark_image_uploaded(ArticleImage.t(), String.t(), map()) ::
          {:ok, ArticleImage.t()} | {:error, Ecto.Changeset.t()}
  def mark_image_uploaded(%ArticleImage{} = image, uploaded_url, attrs \\ %{}) do
    update_image(image, Map.merge(attrs, %{uploaded_url: uploaded_url}))
  end

  @doc """
  Marks an image as failed.
  """
  @spec mark_image_error(ArticleImage.t()) ::
          {:ok, ArticleImage.t()} | {:error, Ecto.Changeset.t()}
  def mark_image_error(%ArticleImage{} = image) do
    update_image(image, %{fetch_error: true})
  end

  @doc """
  Clears permanent fetch failures so a manual reprocess can retry downloads.
  """
  @spec clear_image_fetch_errors(integer()) :: {non_neg_integer(), nil}
  def clear_image_fetch_errors(post_id) when is_integer(post_id) do
    from(i in ArticleImage, where: i.post_id == ^post_id and i.fetch_error == true)
    |> Repo.update_all(set: [fetch_error: false, updated_at: NaiveDateTime.utc_now(:second)])
  end

  @doc """
  Preloads images for a post.
  """
  @spec preload_images(Post.t()) :: Post.t()
  def preload_images(%Post{} = post) do
    Repo.preload(post, :images, force: true)
  end

  @doc """
  Preloads source for a post.
  """
  @spec preload_source(Post.t()) :: Post.t()
  def preload_source(%Post{} = post) do
    Repo.preload(post, :source)
  end
end
