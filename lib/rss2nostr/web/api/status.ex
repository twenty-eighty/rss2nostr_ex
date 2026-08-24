defmodule Rss2Nostr.Web.API.Status do
  @moduledoc """
  API handlers for system status.
  """

  alias Rss2Nostr.{Sources, Posts}

  @type source_counts :: %{total: non_neg_integer(), active: non_neg_integer()}

  @type post_counts :: %{
          total: non_neg_integer(),
          new: non_neg_integer(),
          processing: non_neg_integer(),
          processed: non_neg_integer(),
          pending_images: non_neg_integer(),
          published: non_neg_integer(),
          error: non_neg_integer()
        }

  @type overview :: %{
          sources: source_counts(),
          posts: post_counts(),
          scheduler: %{running: boolean()},
          export_configured: boolean(),
          version: String.t()
        }

  @spec overview() :: overview()
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

  @spec get_scheduler_status() :: %{running: boolean()}
  defp get_scheduler_status do
    %{running: Rss2Nostr.Web.API.Scheduler.status().running}
  end
end
