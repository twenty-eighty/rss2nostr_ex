defmodule Rss2Nostr.Web.API.Status do
  @moduledoc """
  API handlers for system status.
  """

  alias Rss2Nostr.{Sources, Posts}

  def overview do
    %{
      sources: %{
        total: Sources.count_sources(),
        active: Sources.count_active_sources()
      },
      posts: %{
        total: Posts.count_posts(),
        new: Posts.count_posts_by_status("new"),
        processing: Posts.count_posts_by_status("processing"),
        processed: Posts.count_posts_by_status("processed"),
        pending_images: Posts.count_posts_by_status("pending_images"),
        published: Posts.count_posts_by_status("published"),
        error: Posts.count_posts_by_status("error")
      },
      scheduler: get_scheduler_status(),
      export_configured: System.get_env("NOSTR_NSEC") != nil,
      version: "0.1.0"
    }
  end

  defp get_scheduler_status do
    %{running: Rss2Nostr.Web.API.Scheduler.status().running}
  end
end
