ExUnit.start()

# Configure Ecto for test environment
Ecto.Adapters.SQL.Sandbox.mode(Rss2Nostr.Repo, :manual)
