defmodule Rss2Nostr.Posts.ArticleImage do
  @moduledoc """
  Schema for article images extracted from posts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "article_images" do
    field(:original_url, :string)
    field(:uploaded_url, :string)
    field(:alt_text, :string)
    field(:caption, :string)
    field(:fetch_error, :boolean, default: false)
    field(:fetch_attempts, :integer, default: 0)
    field(:sha256, :string)
    field(:mime_type, :string)
    field(:file_size, :integer)
    field(:dim, :string)
    field(:thumb, :string)
    field(:imeta, {:array, :string}, default: [])

    belongs_to(:post, Rss2Nostr.Posts.Post)

    timestamps()
  end

  @doc false
  def changeset(image, attrs) do
    image
    |> cast(attrs, [
      :original_url,
      :uploaded_url,
      :alt_text,
      :caption,
      :fetch_error,
      :fetch_attempts,
      :sha256,
      :mime_type,
      :file_size,
      :dim,
      :thumb,
      :imeta,
      :post_id
    ])
    |> validate_required([:original_url, :post_id])
    |> unique_constraint([:post_id, :original_url])
  end
end
