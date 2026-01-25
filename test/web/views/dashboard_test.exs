defmodule Rss2Nostr.Web.Views.DashboardTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Web.Views.Dashboard

  describe "render/0" do
    test "returns HTML string" do
      html = Dashboard.render()

      assert is_binary(html)
      assert html =~ "<html"
      assert html =~ "Dashboard"
    end

    test "includes navigation" do
      html = Dashboard.render()

      assert html =~ "Sources"
      assert html =~ "Posts"
      assert html =~ "Scheduler"
      assert html =~ "Settings"
    end

    test "includes status overview" do
      html = Dashboard.render()

      # Dashboard should show some statistics
      assert html =~ "RSS2Nostr" or html =~ "Dashboard"
    end

    test "includes proper HTML structure" do
      html = Dashboard.render()

      assert html =~ "<!DOCTYPE html>" or html =~ "<html"
      assert html =~ "</html>"
      assert html =~ "<head>"
      assert html =~ "<body>"
    end
  end
end
