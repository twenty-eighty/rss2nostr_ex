defmodule Rss2Nostr.Repo.Migrations.AddCategoriesToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :categories, {:array, :string}, null: false, default: []
    end
  end
end
