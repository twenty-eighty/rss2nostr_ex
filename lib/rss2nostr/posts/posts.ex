defmodule Rss2Nostr.Posts do
  @moduledoc """
  Context for managing posts/articles.
  """

  import Ecto.Query
  alias Rss2Nostr.Repo
  alias Rss2Nostr.Posts.{Post, ArticleImage}

  # Post queries

  @doc """
  Returns all posts.
  """
  @spec list_posts(keyword()) :: [Post.t()]
  def list_posts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    Post
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
    limit = Keyword.get(opts, :limit, 100)

    Post
    |> where([p], p.status == ^status)
    |> order_by([p], asc: p.inserted_at)
    |> limit(^limit)
    |> Repo.all()
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
  Returns processed posts ready for export.
  """
  @spec list_processed_posts(keyword()) :: [Post.t()]
  def list_processed_posts(opts \\ []) do
    list_posts_by_status(Post.status_processed(), opts)
  end

  @doc """
  Gets a single post by ID.
  """
  @spec get_post(integer() | binary()) :: Post.t() | nil
  def get_post(id), do: Repo.get(Post, id)

  @doc """
  Gets a single post by ID, raises if not found.
  """
  @spec get_post!(integer() | binary()) :: Post.t()
  def get_post!(id), do: Repo.get!(Post, id)

  @doc """
  Gets a post by source URL hash.
  """
  @spec get_post_by_url_hash(String.t()) :: Post.t() | nil
  def get_post_by_url_hash(hash) do
    Repo.get_by(Post, source_url_hash: hash)
  end

  @doc """
  Checks if a post exists by URL hash.
  """
  @spec exists_by_url_hash?(String.t()) :: boolean()
  def exists_by_url_hash?(hash) do
    Post
    |> where([p], p.source_url_hash == ^hash)
    |> Repo.exists?()
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
  Marks a post as processed.
  """
  @spec mark_processed(Post.t()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def mark_processed(%Post{} = post) do
    update_status(post, Post.status_processed())
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
      nostr_address: nostr_address
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
    Repo.aggregate(Post, :count, :id)
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

  defp status_from_name(name) do
    case name do
      "new" -> Post.status_new()
      "processing" -> Post.status_processing()
      "processed" -> Post.status_processed()
      "signing" -> Post.status_signing()
      "signed" -> Post.status_signed()
      "publishing" -> Post.status_publishing()
      "published" -> Post.status_published()
      "blocked" -> Post.status_blocked()
      "error" -> Post.status_error()
      _ -> -1
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
  @spec mark_image_uploaded(ArticleImage.t(), String.t()) ::
          {:ok, ArticleImage.t()} | {:error, Ecto.Changeset.t()}
  def mark_image_uploaded(%ArticleImage{} = image, uploaded_url) do
    update_image(image, %{uploaded_url: uploaded_url})
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
  Preloads images for a post.
  """
  @spec preload_images(Post.t()) :: Post.t()
  def preload_images(%Post{} = post) do
    Repo.preload(post, :images)
  end

  @doc """
  Preloads source for a post.
  """
  @spec preload_source(Post.t()) :: Post.t()
  def preload_source(%Post{} = post) do
    Repo.preload(post, :source)
  end
end
