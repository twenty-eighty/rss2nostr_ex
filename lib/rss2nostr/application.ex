defmodule Rss2Nostr.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database
      Rss2Nostr.Repo,

      # Caches (each needs unique id)
      Supervisor.child_spec({Cachex, name: :sources_cache}, id: :sources_cache),
      Supervisor.child_spec({Cachex, name: :posts_cache}, id: :posts_cache),
      Supervisor.child_spec({Cachex, name: :inbox_relays_cache}, id: :inbox_relays_cache),

      # Nostr Relay Registry
      {Registry, keys: :unique, name: Rss2Nostr.RelayRegistry},

      # Import / process / export / cleanup. Start/Stop on the Scheduler
      # page only toggles timers; the process itself stays up.
      {Rss2Nostr.Scheduler, []}
    ]

    opts = [strategy: :one_for_one, name: Rss2Nostr.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
