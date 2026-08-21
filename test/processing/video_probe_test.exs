defmodule Rss2Nostr.Processing.VideoProbeTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.VideoProbe

  describe "parse_head/1" do
    test "reads size and video MIME type" do
      headers = %{"content-type" => ["video/mp4"], "content-length" => ["66928694"]}

      assert VideoProbe.parse_head(headers) == %{size: 66_928_694, type: "video/mp4"}
    end

    test "ignores a generic MPEG type so the file extension can win" do
      headers = %{"content-type" => ["video/mpeg"], "content-length" => ["100"]}

      assert VideoProbe.parse_head(headers) == %{size: 100}
    end

    test "reads an audio MIME type" do
      headers = %{"content-type" => ["audio/mpeg"], "content-length" => ["49600123"]}

      assert VideoProbe.parse_head(headers) == %{size: 49_600_123, type: "audio/mpeg"}
    end
  end

  describe "parse_ffprobe/1" do
    test "reads duration, dimensions, and bitrate" do
      json = %{
        "format" => %{"duration" => "1423.088333", "size" => "66928694", "bit_rate" => "376000"},
        "streams" => [
          %{
            "codec_type" => "video",
            "width" => 480,
            "height" => 360,
            "duration" => "1423.088333",
            "bit_rate" => "298803"
          }
        ]
      }

      assert VideoProbe.parse_ffprobe(json) == %{
               duration: 1423,
               size: 66_928_694,
               dim: "480x360",
               bitrate: 298_803
             }
    end

    test "reads duration and bitrate from an audio-only file" do
      json = %{
        "format" => %{"duration" => "2712.048", "size" => "49600123", "bit_rate" => "146200"},
        "streams" => [
          %{
            "codec_type" => "audio",
            "duration" => "2712.048",
            "bit_rate" => "128000"
          }
        ]
      }

      assert VideoProbe.parse_ffprobe(json) == %{
               duration: 2712,
               size: 49_600_123,
               bitrate: 128_000
             }
    end
  end

  describe "probe_binary/2" do
    test "keeps size and type when ffprobe is off" do
      info = VideoProbe.probe_binary(<<0, 1, 2, 3>>, type: "audio/mpeg", ffprobe: false)

      assert info == %{size: 4, type: "audio/mpeg"}
    end
  end

  describe "probe/2" do
    test "keeps feed duration and size when the URL is unreachable" do
      info =
        VideoProbe.probe("https://127.0.0.1:1/nwnw640.mp4",
          duration: 1423,
          size: 66_928_694,
          ffprobe: false
        )

      assert info.duration == 1423
      assert info.size == 66_928_694
    end
  end
end
