defmodule Rss2Nostr.HTTPTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.HTTP
  alias Rss2Nostr.Processing.ImageExtractor

  test "encode_http_url percent-encodes spaces left in redirect-style paths" do
    spaced =
      "https://www.mediatenor.com/images/library/reports/Freiheitsindex_2023.indd - Freiheitsindex_2023_web.pdf"

    encoded =
      "https://www.mediatenor.com/images/library/reports/Freiheitsindex_2023.indd%20-%20Freiheitsindex_2023_web.pdf"

    assert ImageExtractor.encode_http_url(spaced) == encoded
    assert ImageExtractor.encode_http_url(encoded) == encoded
  end

  defmodule RedirectStub do
    @moduledoc false
    @behaviour Plug

    def init(opts), do: opts

    def call(%Plug.Conn{request_path: "/start"} = conn, _opts) do
      conn
      |> Plug.Conn.put_resp_header(
        "location",
        "/files/Scholars Under Fire - report.pdf"
      )
      |> Plug.Conn.send_resp(301, "")
    end

    def call(%Plug.Conn{request_path: "/files/Scholars%20Under%20Fire%20-%20report.pdf"} = conn, _opts) do
      conn
      |> Plug.Conn.put_resp_content_type("application/pdf")
      |> Plug.Conn.send_resp(200, "%PDF-stub")
    end

    def call(conn, _opts) do
      Plug.Conn.send_resp(conn, 404, "missing #{conn.request_path}")
    end
  end

  test "get/2 returns the final percent-encoded URL after redirects with spaces" do
    bandit =
      start_supervised!({Bandit, plug: RedirectStub, port: 0, ip: {127, 0, 0, 1}})

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    start = "http://127.0.0.1:#{port}/start"

    assert {:ok, %{status: 200, body: "%PDF-stub", url: final}} =
             HTTP.get(start, retry: false)

    assert final == "http://127.0.0.1:#{port}/files/Scholars%20Under%20Fire%20-%20report.pdf"
  end
end
