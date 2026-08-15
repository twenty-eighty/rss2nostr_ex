defmodule Mix.Tasks.Rss2nostr.Server do
  @shortdoc "Starts the RSS2Nostr web server"

  @moduledoc """
  Starts the admin web server.

  ## Examples

      mix rss2nostr.server
      mix rss2nostr.server --port 8080

  The port is taken from `--port`, then `PORT` / `WEB_PORT`, then 4000.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [port: :integer], aliases: [p: :port])

    Rss2Nostr.CLI.Commands.Web.start(%{port: opts[:port]})
  end
end
