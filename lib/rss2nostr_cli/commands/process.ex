defmodule Rss2Nostr.CLI.Commands.Process do
  @moduledoc """
  CLI command for processing new posts (HTML to Markdown conversion).
  """

  alias Rss2Nostr.CLI.Output
  alias Rss2Nostr.Processing.Processor
  alias Rss2Nostr.Posts

  @spec run(map()) :: :ok
  def run(options) do
    limit = Map.get(options, :limit, 10)

    new_count = Posts.list_new_posts(limit: 99999) |> length()
    Output.info("Processing new posts...")
    Output.info("  Found #{new_count} new posts, processing up to #{limit}")

    if new_count == 0 do
      Output.info("No new posts to process.")
    else
      result = Processor.process_new_posts(limit: limit)

      Output.info("")
      Output.info("=== Processing Summary ===")
      Output.info("  Processed: #{result.processed}")
      Output.info("  Skipped:   #{result.skipped}")
      Output.info("  Errors:    #{result.errors}")

      cond do
        result.processed > 0 ->
          Output.success("Processing completed successfully!")

        result.errors > 0 ->
          Output.warning("Processing completed with errors.")

        true ->
          Output.info("No posts were processed.")
      end
    end

    :ok
  end
end
