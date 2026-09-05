defmodule Rss2Nostr.HTTPTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.ImageExtractor

  test "encode_http_url percent-encodes spaces left in redirect-style paths" do
    spaced =
      "https://www.mediatenor.com/images/library/reports/Freiheitsindex_2023.indd - Freiheitsindex_2023_web.pdf"

    encoded =
      "https://www.mediatenor.com/images/library/reports/Freiheitsindex_2023.indd%20-%20Freiheitsindex_2023_web.pdf"

    assert ImageExtractor.encode_http_url(spaced) == encoded
    assert ImageExtractor.encode_http_url(encoded) == encoded
  end
end
