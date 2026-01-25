defmodule Rss2Nostr.CLI.Commands.Web do
  @moduledoc """
  CLI commands for the web interface.
  """

  alias Rss2Nostr.CLI.Output
  alias Rss2Nostr.Web.Server

  def start(options) do
    port = options[:port] || 4000

    Output.info("Starting web server on port #{port}...")
    Output.info("Open http://localhost:#{port} in your browser")
    Output.info("Press Ctrl+C to stop")

    case Server.start(port: port) do
      {:ok, _pid} ->
        # Keep the process running
        Process.sleep(:infinity)

      {:error, {:already_started, _pid}} ->
        Output.warning("Web server is already running")

      {:error, reason} ->
        Output.error("Failed to start web server: #{inspect(reason)}")
    end
  end

  def stop do
    case Server.stop() do
      {:ok, :stopped} ->
        Output.success("Web server stopped")

      {:error, :not_running} ->
        Output.warning("Web server is not running")
    end
  end

  def status do
    if Server.running?() do
      Output.info("Web server is running")
    else
      Output.info("Web server is not running")
    end
  end
end
