defmodule Rss2Nostr.Web.Server do
  @moduledoc """
  Web server management for the admin interface.
  """

  require Logger

  @default_port 4000

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start, [opts]},
      type: :supervisor,
      restart: :permanent
    }
  end

  def start(opts \\ []) do
    port =
      Keyword.get(opts, :port) ||
        Application.get_env(:rss2nostr, :web_port, @default_port)

    Logger.info("Starting web server on port #{port}")

    endpoint_config =
      :rss2nostr
      |> Application.get_env(Rss2NostrWeb.Endpoint, [])
      |> Keyword.merge(
        http: [ip: {0, 0, 0, 0}, port: port],
        server: true,
        secret_key_base: Rss2Nostr.Web.Auth.secret_key_base()
      )

    Application.put_env(:rss2nostr, Rss2NostrWeb.Endpoint, endpoint_config)

    children =
      maybe_reloader() ++
        [Rss2NostrWeb.Endpoint]

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
