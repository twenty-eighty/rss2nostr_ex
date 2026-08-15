defmodule Rss2Nostr.Web.API.Settings do
  @moduledoc """
  API handlers for settings operations.
  """

  alias Rss2Nostr.Nostr.{Blossom, Relays}

  def get do
    %{
      nostr_nsec_configured: System.get_env("NOSTR_NSEC") != nil,
      relays: Relays.all(),
      upload_endpoint: Blossom.configured_server(),
      blossom_servers: Blossom.servers(),
      scheduler_intervals:
        Application.get_env(:rss2nostr, Rss2Nostr.Scheduler, [])[:intervals] || %{},
      version: "0.1.0"
    }
  end

  def update(_params) do
    # Settings are managed via environment variables and config
    # This is a placeholder for future functionality
    {:ok, "Settings updated"}
  end
end
