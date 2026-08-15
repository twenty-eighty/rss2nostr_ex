defmodule Rss2Nostr.Repo.Migrations.PostsUrlHashPerSource do
  use Ecto.Migration

  def up do
    execute("DELETE FROM posts WHERE source_id IS NULL")

    drop unique_index(:posts, [:source_url_hash])
    create unique_index(:posts, [:source_id, :source_url_hash])

    execute("""
    ALTER TABLE posts
      DROP CONSTRAINT posts_source_id_fkey,
      ADD CONSTRAINT posts_source_id_fkey
        FOREIGN KEY (source_id) REFERENCES sources(id) ON DELETE CASCADE
    """)
  end

  def down do
    execute("""
    ALTER TABLE posts
      DROP CONSTRAINT posts_source_id_fkey,
      ADD CONSTRAINT posts_source_id_fkey
        FOREIGN KEY (source_id) REFERENCES sources(id) ON DELETE SET NULL
    """)

    drop unique_index(:posts, [:source_id, :source_url_hash])
    create unique_index(:posts, [:source_url_hash])
  end
end
