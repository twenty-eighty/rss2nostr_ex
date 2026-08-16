defmodule Rss2Nostr.Repo.Migrations.WidenNostrAddress do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      modify(:nostr_address, :text, from: :string)
    end
  end
end
