defmodule Rss2Nostr.Sources.Source do
  @moduledoc """
  Schema for RSS/Atom feed sources.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type_values ~w(rss atom)

  @type t :: %__MODULE__{}

  schema "sources" do
    field(:name, :string)
    field(:url, :string)
    field(:type, :string, default: "rss")
    field(:active, :boolean, default: true)
    field(:language, :string, default: "de")

    # Nostr-specific
    field(:default_post_kind, :integer, default: 30023)
    field(:pubkey, :string)
    field(:bunker_connection, :string)

    # Filters
    field(:publish_after_date, :utc_datetime)
    field(:fetch_source_from, :string, default: "fetch_from_url")

    # Additional options
    field(:options, :map, default: %{})

    has_many(:posts, Rss2Nostr.Posts.Post)

    timestamps()
  end

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :name,
      :url,
      :type,
      :active,
      :language,
      :default_post_kind,
      :pubkey,
      :bunker_connection,
      :publish_after_date,
      :fetch_source_from,
      :options
    ])
    |> validate_required([:name, :url])
    |> validate_inclusion(:type, @type_values)
    |> validate_inclusion(:default_post_kind, [30023, 30024])
    |> unique_constraint(:url)
  end
end
