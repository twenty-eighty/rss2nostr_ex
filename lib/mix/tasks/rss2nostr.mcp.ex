defmodule Mix.Tasks.Rss2nostr.Mcp do
  @shortdoc "Starts the RSS2Nostr MCP server on stdio"

  @moduledoc """
  Speaks MCP on stdin/stdout so an editor or agent can manage this instance.

  ## Examples

      mix rss2nostr.mcp

  Point Cursor or Claude Desktop at this task. The process stays up until
  the client closes the pipe.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    case Rss2Nostr.MCP.start_stdio() do
      {:ok, _pid} ->
        Process.sleep(:infinity)

      {:error, reason} ->
        Mix.raise("Failed to start MCP server: #{inspect(reason)}")
    end
  end
end
