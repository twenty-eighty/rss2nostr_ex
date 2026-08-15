defmodule Rss2Nostr.Repo.Migrations.AddPublicToSources do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :public, :boolean, default: false, null: false
    end
  end
end
