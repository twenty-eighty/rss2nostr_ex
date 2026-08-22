defmodule Rss2Nostr.Processing.LabelsTest do
  use ExUnit.Case, async: true

  alias Rss2Nostr.Processing.Labels

  describe "t/3" do
    test "translates listen and watch labels to the feed language" do
      assert Labels.t(:listen_on, "de", platform: "SoundCloud") == "Auf SoundCloud anhören"
      assert Labels.t(:watch_on, "de", platform: "YouTube") == "Auf YouTube ansehen"
      assert Labels.t(:listen_on, "fr", platform: "Podbean") == "Écouter sur Podbean"
    end

    test "falls back to English for an unknown language" do
      assert Labels.t(:listen_on, "xx", platform: "SoundCloud") == "Listen on SoundCloud"
      assert Labels.t(:audio, nil) == "Audio"
      assert Labels.t(:video, "eo") == "Video"
    end

    test "normalizes regional tags" do
      assert Labels.t(:watch_on, "de-DE", platform: "Odysee") == "Auf Odysee ansehen"
      assert Labels.t(:listen_on, "nb", platform: "SoundCloud") == "Lytt på SoundCloud"
    end
  end

  describe "generic_watch_on_youtube?/1" do
    test "recognizes generated YouTube labels" do
      assert Labels.generic_watch_on_youtube?("Watch on YouTube")
      assert Labels.generic_watch_on_youtube?("Auf YouTube ansehen")
      refute Labels.generic_watch_on_youtube?("My interview")
    end
  end
end
