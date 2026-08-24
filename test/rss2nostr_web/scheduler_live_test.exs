defmodule Rss2NostrWeb.SchedulerLiveTest do
  use Rss2NostrWeb.ConnCase, async: false

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  test "index shows hourly cleanup and deleted-draft counts", %{conn: conn} do
    {:ok, source} =
      Sources.create_source(%{
        name: "Scheduler View Source",
        url: "https://example.com/scheduler-view-#{System.unique_integer([:positive])}.xml",
        type: "rss",
        language: "en",
        active: true
      })

    url = "https://example.com/cleaned-#{System.unique_integer([:positive])}"

    {:ok, post} =
      Posts.create_post(%{
        title: "Cleaned Article",
        source_url: url,
        source_url_hash: Post.generate_url_hash(url),
        source_html: "<p>Content</p>",
        status: Post.status_new(),
        source_id: source.id
      })

    {:ok, published} = Posts.mark_published(post, "abc123", "def456", "naddr1...")
    {:ok, _} = Posts.mark_draft_cleaned(published)

    html = page(conn, "/scheduler")

    assert html =~ "Draft cleanup"
    assert html =~ "Drafts deleted"
    assert html =~ ">#{Posts.count_draft_cleaned()}<"
    assert html =~ "runs every hour"
    assert html =~ "SCHEDULER_AUTO_START"
    assert html =~ ">1h<" or html =~ ">1 hour<"
  end
end
