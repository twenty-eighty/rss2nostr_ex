defmodule Rss2Nostr.Repo.Migrations.AddDraftCleanedAt do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add(:draft_cleaned_at, :utc_datetime)
    end

    create(index(:posts, [:draft_cleaned_at]))
  end
end
