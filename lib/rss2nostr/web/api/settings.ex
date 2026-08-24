defmodule Rss2Nostr.Web.API.Settings do
  @moduledoc """
  API handlers for settings operations.
  """

  alias Rss2Nostr.Nostr.{Blossom, Relays}
  alias Rss2Nostr.Processing.Composer
  alias Rss2NostrWeb.Language

  @spec get() :: map()
  def get do
    %{
      nostr_nsec_configured: System.get_env("NOSTR_NSEC") != nil,
      relays: Relays.all(),
      upload_endpoint: Blossom.configured_server(),
      blossom_servers: Blossom.servers(),
      scheduler_intervals:
        Application.get_env(:rss2nostr, Rss2Nostr.Scheduler, [])[:intervals] || %{},
      compose: compose_options(),
      version: "0.1.0"
    }
  end

  @spec compose_options() :: map()
  defp compose_options do
    %{
      body_presets:
        Enum.map(Composer.body_presets(), fn {label, selector} ->
          %{label: label, selector: selector}
        end),
      languages:
        Enum.map(Language.choices(), fn {code, label} ->
          %{code: code, label: label}
        end),
      default_skip_classes: Composer.default_skip_classes_text(),
      fetch_source_from: ~w(content fetch_from_url),
      publish_as: ~w(draft draft_plain article video),
      mirror_media: ~w(blossom original),
      modes: ~w(setup automated)
    }
  end

  @spec update(map()) :: {:ok, String.t()}
  def update(_params) do
    # Settings are managed via environment variables and config
    # This is a placeholder for future functionality
    {:ok, "Settings updated"}
  end
end
