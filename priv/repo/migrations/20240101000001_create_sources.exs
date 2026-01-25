defmodule Rss2Nostr.Repo.Migrations.CreateSources do
  use Ecto.Migration

  def change do
    create table(:sources) do
      add :name, :string, null: false
      add :url, :string, null: false
      add :type, :string, default: "rss"
      add :active, :boolean, default: true
      add :language, :string, default: "de"

      # Nostr-specific
      add :default_post_kind, :integer, default: 30023
      add :pubkey, :string
      add :bunker_connection, :string

      # Filters
      add :publish_after_date, :utc_datetime
      add :fetch_source_from, :string, default: "fetch_from_url"

      # Additional options as JSON
      add :options, :map, default: %{}

      timestamps()
    end

    create unique_index(:sources, [:url])
    create index(:sources, [:active])
  end
end
