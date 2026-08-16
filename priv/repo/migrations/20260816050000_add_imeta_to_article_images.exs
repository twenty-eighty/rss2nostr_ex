defmodule Rss2Nostr.Repo.Migrations.AddImetaToArticleImages do
  use Ecto.Migration

  def change do
    alter table(:article_images) do
      add :sha256, :string
      add :mime_type, :string
      add :file_size, :integer
      add :dim, :string
      add :thumb, :string
      add :imeta, {:array, :string}, null: false, default: []
    end
  end
end
