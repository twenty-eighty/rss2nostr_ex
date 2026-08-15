defmodule Rss2Nostr.Web.Server do
  @moduledoc """
  Web server management for the admin interface.
  """

  require Logger

  @default_port 4000

  def start(opts \\ []) do
    port =
      Keyword.get(opts, :port) ||
        Application.get_env(:rss2nostr, :web_port, @default_port)

    Logger.info("Starting web server on port #{port}")

    children =
      maybe_reloader() ++
        [{Bandit, plug: Rss2Nostr.Web.Router, port: port}]

    Supervisor.start_link(children, strategy: :one_for_one, name: Rss2Nostr.Web.Supervisor)
  end

  def stop do
    case Process.whereis(Rss2Nostr.Web.Supervisor) do
      nil ->
        {:error, :not_running}

      pid ->
        Supervisor.stop(pid)
        {:ok, :stopped}
    end
  end

  def running? do
    Process.whereis(Rss2Nostr.Web.Supervisor) != nil
  end

  def port do
    Application.get_env(:rss2nostr, :web_port, @default_port)
  end

  defp maybe_reloader do
    if Rss2Nostr.Web.CodeReloader.enabled?() do
      [Rss2Nostr.Web.CodeReloader]
    else
      []
    end
  end
end
