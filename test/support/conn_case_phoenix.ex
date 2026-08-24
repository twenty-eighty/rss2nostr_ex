defmodule Rss2NostrWeb.ConnCase do
  @moduledoc """
  Helpers for Phoenix Endpoint / LiveView tests.
  """

  use ExUnit.CaseTemplate

  import Phoenix.ConnTest

  @endpoint Rss2NostrWeb.Endpoint

  using do
    quote do
      use Rss2Nostr.DataCase, async: false
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Rss2NostrWeb.ConnCase

      @endpoint Rss2NostrWeb.Endpoint
    end
  end

  setup do
    Rss2Nostr.Web.Auth.put_current_pubkey(nil)
    start_endpoint!()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def admin_pubkey do
    Application.get_env(:rss2nostr, :admin, [])
    |> Keyword.get(:pubkeys, [])
    |> List.first()
  end

  def authed_conn(conn) do
    Phoenix.ConnTest.init_test_session(conn, %{admin_pubkey: admin_pubkey()})
  end

  def page(conn, path) do
    conn
    |> authed_conn()
    |> dispatch(@endpoint, :get, path, nil)
    |> html_response(200)
  end

  defp start_endpoint! do
    case Process.whereis(Rss2NostrWeb.Endpoint) do
      nil -> start_supervised!(Rss2NostrWeb.Endpoint)
      _pid -> :ok
    end
  end
end
