defmodule Rss2Nostr.ConnCase do
  @moduledoc """
  Helpers for Plug router tests. Admin routes expect a NIP-07 session.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Rss2Nostr.DataCase, async: false
      import Plug.Test
      import Plug.Conn
      import Rss2Nostr.ConnCase

      alias Rss2Nostr.Web.Router
    end
  end

  setup do
    Rss2Nostr.Web.Auth.put_current_pubkey(nil)
    :ok
  end

  def admin_pubkey do
    Application.get_env(:rss2nostr, :admin, [])
    |> Keyword.get(:pubkeys, [])
    |> List.first()
  end

  def admin_private_key, do: <<1::256>>

  def call(conn, opts \\ []) do
    authed? = Keyword.get(opts, :auth, true)

    conn =
      if conn.private[:plug_session_fetch] == :done do
        conn
      else
        session = if authed?, do: %{admin_pubkey: admin_pubkey()}, else: %{}
        Plug.Test.init_test_session(conn, session)
      end

    Rss2Nostr.Web.Router.call(conn, Rss2Nostr.Web.Router.init([]))
  end
end
