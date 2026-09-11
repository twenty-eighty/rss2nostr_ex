defmodule Rss2Nostr.Repo.Migrations.AddFetchAttemptsToArticleImages do
  use Ecto.Migration

  def change do
    alter table(:article_images) do
      add(:fetch_attempts, :integer, null: false, default: 0)
    end
  end
end
