defmodule Rss2Nostr.CLI.Commands.Status do
  @moduledoc """
  CLI command for showing status overview.
  """

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources
  alias Rss2Nostr.CLI.Output

  def run do
    Output.info("=== RSS2Nostr Status ===\n")

    # Sources
    sources = Sources.list_sources()
    active_sources = Enum.count(sources, & &1.active)
    Output.info("Sources: #{length(sources)} total, #{active_sources} active\n")

    # Posts by status
    counts = Posts.count_by_status()

    Output.info("Posts by status:")
    Output.info("  New:        #{Map.get(counts, Post.status_new(), 0)}")
    Output.info("  Processing: #{Map.get(counts, Post.status_processing(), 0)}")
    Output.info("  Processed:  #{Map.get(counts, Post.status_processed(), 0)}")
    Output.info("  Pending images: #{Map.get(counts, Post.status_pending_images(), 0)}")
    Output.info("  Signing:    #{Map.get(counts, Post.status_signing(), 0)}")
    Output.info("  Signed:     #{Map.get(counts, Post.status_signed(), 0)}")
    Output.info("  Publishing: #{Map.get(counts, Post.status_publishing(), 0)}")
    Output.info("  Published:  #{Map.get(counts, Post.status_published(), 0)}")
    Output.info("  Blocked:    #{Map.get(counts, Post.status_blocked(), 0)}")
    Output.info("  Error:      #{Map.get(counts, Post.status_error(), 0)}")

    total = counts |> Map.values() |> Enum.sum()
    Output.info("\n  Total:      #{total}")
  end
end
