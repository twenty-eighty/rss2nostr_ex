defmodule Rss2Nostr.Repo.Migrations.AddExcludedHashtags do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add(:excluded_hashtags, {:array, :string}, null: false, default: [])
    end
  end
end
