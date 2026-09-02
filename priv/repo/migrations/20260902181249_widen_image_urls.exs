defmodule Rss2Nostr.Repo.Migrations.WidenImageUrls do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      modify(:image, :text, from: :string)
    end

    alter table(:article_images) do
      modify(:original_url, :text, from: :string)
      modify(:uploaded_url, :text, from: :string)
    end
  end
end
