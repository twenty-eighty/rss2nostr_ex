defmodule Rss2Nostr.Repo.Migrations.AddStaging do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add :staging_hold_minutes, :integer, null: false, default: 0
      add :notify_pubkey, :string
    end

    alter table(:posts) do
      add :staged_at, :utc_datetime
    end

    create index(:posts, [:staged_at])
  end
end
