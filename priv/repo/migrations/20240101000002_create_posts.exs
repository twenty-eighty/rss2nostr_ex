defmodule Rss2Nostr.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :article_identifier, :string
      add :title, :string
      add :content, :text
      add :source_html, :text
      add :image, :string
      add :source_url, :string
      add :source_url_hash, :string, null: false
      add :published_at, :utc_datetime
      add :imported_at, :utc_datetime
      add :author_name, :string
      add :author_id, :string
      add :summary, :text
      add :language, :string, default: "de"

      # Nostr
      add :type, :integer, default: 30023
      add :pubkey, :string
      add :event_id, :string
      add :nostr_address, :string

      # Status tracking
      add :status, :integer, default: 0
      add :last_error, :text

      add :source_id, references(:sources, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:posts, [:source_url_hash])
    create index(:posts, [:status])
    create index(:posts, [:source_id])
    create index(:posts, [:published_at])
    create index(:posts, [:event_id])
  end
end
