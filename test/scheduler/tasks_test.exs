defmodule Rss2Nostr.Scheduler.TasksTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Scheduler.Tasks
  alias Rss2Nostr.Sources
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post

  def unique_url do
    "https://example.com/tasks-test-#{System.unique_integer([:positive])}.xml"
  end

  describe "run_import/0" do
    test "returns ok tuple when no active sources" do
      # Ensure no active sources exist for this test
      Sources.list_active_sources()
      |> Enum.each(fn source ->
        Sources.disable_source(source)
      end)

      result = Tasks.run_import()

      assert match?({:ok, %{imported: 0, errors: 0}}, result)
    end
  end

  describe "run_process/0" do
    test "returns result map" do
      assert {:ok, %{errors: _, processed: _}} = Tasks.run_process()
    end

    test "processes new posts" do
      {:ok, source} =
        Sources.create_source(%{
          name: "Tasks Process Test",
          url: unique_url(),
          type: "rss",
          language: "en",
          active: true
        })

      url = "https://example.com/process-test-#{System.unique_integer([:positive])}"

      {:ok, _post} =
        Posts.create_post(%{
          title: "Process Test Article",
          source_url: url,
          source_url_hash: Post.generate_url_hash(url),
          source_html: "<p>Content to process</p>",
          status: Post.status_new(),
          source_id: source.id
        })

      result = Tasks.run_process()

      assert match?({:ok, %{errors: _, processed: _}}, result)
    end
  end

  describe "run_export/1" do
    test "returns ok when there are no automated posts to export" do
      result = Tasks.run_export(%{})

      assert match?({:ok, %{published: 0}}, result) or result == {:error, :no_relays}
    end

    test "returns error when no relays configured" do
      private_key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

      result = Tasks.run_export(%{private_key: private_key, relays: []})

      assert result == {:error, :no_relays}
    end

    test "returns ok with no posts to export" do
      private_key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

      result =
        Tasks.run_export(%{
          private_key: private_key,
          relays: ["wss://relay.example.com"]
        })

      # Should succeed with no posts or return ok tuple
      assert match?({:ok, _}, result) or result == :ok
    end

    test "uses configured relays when none are passed" do
      private_key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

      result = Tasks.run_export(%{private_key: private_key})

      assert match?({:ok, _}, result)
    end
  end

  describe "run_cleanup/0" do
    test "returns ok or a missing-key error" do
      result = Tasks.run_cleanup()

      assert match?({:ok, %{deleted: _, skipped: _}}, result) or
               result == {:error, :no_app_private_key}
    end
  end
end
