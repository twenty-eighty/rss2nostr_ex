defmodule Rss2Nostr.Repo.Migrations.AddFixedHashtags do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add(:fixed_hashtags, {:array, :string}, null: false, default: [])
    end
  end
end
