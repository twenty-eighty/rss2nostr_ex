defmodule Rss2Nostr.Web.Views.SchedulerTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources
  alias Rss2Nostr.Web.Views.Scheduler, as: SchedulerView

  test "index shows hourly cleanup and deleted-draft counts" do
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

    html = SchedulerView.index()

    assert html =~ "Draft cleanup"
    assert html =~ "Drafts deleted"
    assert html =~ ">#{Posts.count_draft_cleaned()}<"
    assert html =~ "runs every hour"
    assert html =~ ">1h<" or html =~ ">1 hour<"
  end
end
