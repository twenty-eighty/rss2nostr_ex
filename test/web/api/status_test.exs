defmodule Rss2Nostr.Web.API.StatusTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Web.API.Status

  describe "overview/0" do
    test "returns status overview with all required fields" do
      status = Status.overview()

      assert Map.has_key?(status, :sources)
      assert Map.has_key?(status, :posts)
      assert Map.has_key?(status, :scheduler)
      assert Map.has_key?(status, :export_configured)
      assert Map.has_key?(status, :version)
    end

    test "sources contains total and active counts" do
      status = Status.overview()

      assert Map.has_key?(status.sources, :total)
      assert Map.has_key?(status.sources, :active)
      assert is_integer(status.sources.total)
      assert is_integer(status.sources.active)
    end

    test "posts contains all status counts" do
      status = Status.overview()

      assert Map.has_key?(status.posts, :total)
      assert Map.has_key?(status.posts, :new)
      assert Map.has_key?(status.posts, :processing)
      assert Map.has_key?(status.posts, :processed)
      assert Map.has_key?(status.posts, :published)
      assert Map.has_key?(status.posts, :error)
    end

    test "scheduler contains running status" do
      status = Status.overview()

      assert Map.has_key?(status.scheduler, :running)
      assert is_boolean(status.scheduler.running)
    end

    test "export_configured is boolean" do
      status = Status.overview()

      assert is_boolean(status.export_configured)
    end

    test "version is string" do
      status = Status.overview()

      assert is_binary(status.version)
      assert status.version == "0.1.0"
    end
  end
end
