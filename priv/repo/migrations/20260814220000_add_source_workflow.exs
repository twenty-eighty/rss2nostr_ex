defmodule Rss2Nostr.Repo.Migrations.AddSourceWorkflow do
  use Ecto.Migration

  def change do
    alter table(:sources) do
      add(:mode, :string, null: false, default: "setup")
      add(:publish_as, :string, null: false, default: "draft")
      add(:signing_nsec_ciphertext, :text)
    end

    execute(
      """
      UPDATE sources
      SET mode = CASE WHEN active THEN 'automated' ELSE 'setup' END,
          publish_as = CASE WHEN default_post_kind = 30024 THEN 'draft' ELSE 'article' END
      """,
      "UPDATE sources SET mode = 'setup', publish_as = 'draft'"
    )
  end
end
