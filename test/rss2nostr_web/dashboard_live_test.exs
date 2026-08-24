defmodule Rss2NostrWeb.DashboardLiveTest do
  use Rss2NostrWeb.ConnCase, async: false

  describe "GET /" do
    test "returns HTML for the dashboard", %{conn: conn} do
      html = page(conn, "/")

      assert html =~ "<html"
      assert html =~ "Dashboard"
      assert html =~ "Sources"
      assert html =~ "Posts"
      assert html =~ "Scheduler"
      assert html =~ "Settings"
      assert html =~ "RSS2Nostr"
    end
  end
end
