defmodule Rss2Nostr.Web.API.Settings do
  @moduledoc """
  API handlers for settings operations.
  """

  def get do
    %{
      nostr_nsec_configured: System.get_env("NOSTR_NSEC") != nil,
      relays: Application.get_env(:rss2nostr, :default_relays, []),
      scheduler_intervals: Application.get_env(:rss2nostr, :scheduler, %{}),
      version: "0.1.0"
    }
  end

  def update(_params) do
    # Settings are managed via environment variables and config
    # This is a placeholder for future functionality
    {:ok, "Settings updated"}
  end
end
