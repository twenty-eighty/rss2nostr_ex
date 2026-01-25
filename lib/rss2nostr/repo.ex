defmodule Rss2Nostr.Repo do
  use Ecto.Repo,
    otp_app: :rss2nostr,
    adapter: Ecto.Adapters.Postgres
end
