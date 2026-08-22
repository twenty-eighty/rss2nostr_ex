defmodule Rss2Nostr.Processing.SoundcloudTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.Soundcloud

  describe "artwork_url/2" do
    test "returns nil without a permalink" do
      assert Soundcloud.artwork_url(nil) == nil
      assert Soundcloud.artwork_url("") == nil
    end

    test "returns the injected fetch result" do
      url = "https://i1.sndcdn.com/artworks-x.jpg"
      permalink = "https://soundcloud.com/radiomuenchen/sommerpause"

      assert Soundcloud.artwork_url(permalink, enabled: true, fetch: fn ^permalink -> url end) ==
               url
    end

    test "skips the network when disabled" do
      assert Soundcloud.artwork_url("https://soundcloud.com/a/b",
               enabled: false,
               fetch: fn _ -> flunk("should not fetch") end
             ) == nil
    end
  end
end
