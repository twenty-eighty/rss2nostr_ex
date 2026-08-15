defmodule Rss2Nostr.Web.CodeReloaderTest do
  use Rss2Nostr.ConnCase, async: false

  alias Rss2Nostr.Web.CodeReloader

  test "is disabled in the test environment" do
    refute CodeReloader.enabled?()
    assert CodeReloader.reload() == :noop
  end

  test "passes the connection through when disabled" do
    conn = Plug.Test.conn(:get, "/")
    assert CodeReloader.plug(conn, []) == conn
  end

  test "exists_by_url_hash?/2 is exported for import" do
    Code.ensure_loaded!(Rss2Nostr.Posts)
    assert function_exported?(Rss2Nostr.Posts, :exists_by_url_hash?, 2)
  end
end
