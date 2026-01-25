defmodule Rss2Nostr.Posts.Post do
  @moduledoc """
  Schema for imported articles/posts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  # Status constants
  @status_new 0
  @status_processing 1
  @status_processed 2
  @status_signing 3
  @status_signed 4
  @status_publishing 5
  @status_published 6
  @status_blocked 7
  @status_error 8

  @type t :: %__MODULE__{}

  @spec status_new() :: integer()
  def status_new, do: @status_new

  @spec status_processing() :: integer()
  def status_processing, do: @status_processing

  @spec status_processed() :: integer()
  def status_processed, do: @status_processed

  @spec status_signing() :: integer()
  def status_signing, do: @status_signing

  @spec status_signed() :: integer()
  def status_signed, do: @status_signed

  @spec status_publishing() :: integer()
  def status_publishing, do: @status_publishing

  @spec status_published() :: integer()
  def status_published, do: @status_published

  @spec status_blocked() :: integer()
  def status_blocked, do: @status_blocked

  @spec status_error() :: integer()
  def status_error, do: @status_error

  @status_names %{
    @status_new => "new",
    @status_processing => "processing",
    @status_processed => "processed",
    @status_signing => "signing",
    @status_signed => "signed",
    @status_publishing => "publishing",
    @status_published => "published",
    @status_blocked => "blocked",
    @status_error => "error"
  }

  @spec status_name(integer()) :: String.t()
  def status_name(status), do: Map.get(@status_names, status, "unknown")

  @spec status_label(integer()) :: String.t()
  def status_label(status), do: status_name(status)

  schema "posts" do
    field(:article_identifier, :string)
    field(:title, :string)
    field(:content, :string)
    field(:source_html, :string)
    field(:image, :string)
    field(:source_url, :string)
    field(:source_url_hash, :string)
    field(:published_at, :utc_datetime)
    field(:imported_at, :utc_datetime)
    field(:author_name, :string)
    field(:author_id, :string)
    field(:summary, :string)
    field(:language, :string, default: "de")

    # Nostr
    field(:type, :integer, default: 30023)
    field(:pubkey, :string)
    field(:event_id, :string)
    field(:nostr_address, :string)

    # Status
    field(:status, :integer, default: 0)
    field(:last_error, :string)

    belongs_to(:source, Rss2Nostr.Sources.Source)
    has_many(:images, Rss2Nostr.Posts.ArticleImage)

    timestamps()
  end

  @doc false
  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :article_identifier,
      :title,
      :content,
      :source_html,
      :image,
      :source_url,
      :source_url_hash,
      :published_at,
      :imported_at,
      :author_name,
      :author_id,
      :summary,
      :language,
      :type,
      :pubkey,
      :event_id,
      :nostr_address,
      :status,
      :last_error,
      :source_id
    ])
    |> validate_required([:source_url_hash])
    |> unique_constraint(:source_url_hash)
  end

  @doc """
  Generates an MD5 hash for deduplication.
  """
  @spec generate_url_hash(String.t() | any()) :: String.t() | nil
  def generate_url_hash(url) when is_binary(url) do
    :crypto.hash(:md5, url) |> Base.encode16(case: :lower)
  end

  def generate_url_hash(_), do: nil
end
