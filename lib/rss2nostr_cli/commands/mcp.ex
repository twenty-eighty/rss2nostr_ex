defmodule Rss2Nostr.CLI.Commands.MCP do
  @moduledoc """
  CLI command that runs the MCP server on stdio.
  """

  alias Rss2Nostr.CLI.Output

  def run do
    Output.info("Starting RSS2Nostr MCP server on stdio")

    case Rss2Nostr.MCP.start_stdio() do
      {:ok, _pid} ->
        Process.sleep(:infinity)

      {:error, reason} ->
        Output.error("Failed to start MCP server: #{inspect(reason)}")
    end
  end
end
