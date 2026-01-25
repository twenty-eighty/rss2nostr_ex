defmodule Rss2Nostr.Repo.Migrations.CreateArticleImages do
  use Ecto.Migration

  def change do
    create table(:article_images) do
      add :original_url, :string, null: false
      add :uploaded_url, :string
      add :alt_text, :string
      add :caption, :string
      add :fetch_error, :boolean, default: false

      add :post_id, references(:posts, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:article_images, [:post_id])
    create unique_index(:article_images, [:post_id, :original_url])
  end
end
