defmodule Rss2Nostr.HTTP.SafeURLTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.HTTP.SafeURL

  setup do
    previous = Application.get_env(:rss2nostr, :http_ssrf_protection)
    Application.put_env(:rss2nostr, :http_ssrf_protection, true)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:rss2nostr, :http_ssrf_protection)
      else
        Application.put_env(:rss2nostr, :http_ssrf_protection, previous)
      end
    end)

    :ok
  end

  test "allows public https URLs" do
    assert :ok = SafeURL.validate("https://example.com/feed.xml")
  end

  test "rejects non-http schemes" do
    assert {:error, :invalid_url} = SafeURL.validate("file:///etc/passwd")
    assert {:error, :invalid_url} = SafeURL.validate("javascript:alert(1)")
  end

  test "rejects loopback and private addresses" do
    assert {:error, :blocked_address} = SafeURL.validate("http://127.0.0.1/")
    assert {:error, :blocked_address} = SafeURL.validate("http://192.168.1.1/")
    assert {:error, :blocked_address} = SafeURL.validate("http://10.0.0.1/")
    assert {:error, :blocked_address} = SafeURL.validate("http://169.254.169.254/")
  end

  test "rejects localhost hostnames" do
    assert {:error, :blocked_host} = SafeURL.validate("http://localhost/feed")
  end
end
