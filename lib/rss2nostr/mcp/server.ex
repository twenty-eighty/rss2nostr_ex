defmodule Rss2Nostr.MCP.Server do
  @moduledoc """
  MCP tools and resources for managing RSS2Nostr.
  """

  use ExMCP.Server.Handler
  use ExMCP.Server.DSL, name: "rss2nostr", version: "0.1.0"

  alias Rss2Nostr.MCP.Actions

  tool "get_status", "Overview of sources, posts, and the scheduler" do
    annotations(readOnlyHint: true)
    run(fn _args, state -> reply(Actions.get_status(), state) end)
  end

  tool "get_settings",
       "Non-secret settings: relays, upload endpoint, scheduler intervals, compose presets, follow list" do
    annotations(readOnlyHint: true)
    run(fn _args, state -> reply(Actions.get_settings(), state) end)
  end

  tool "follow_list_status",
       "Follow list cache status (configured pubkey, count, last fetch). Optionally refresh and wait, or include member pubkeys." do
    annotations(readOnlyHint: true)
    param(:refresh, :boolean, description: "Refresh from relays and wait before returning status")
    param(:include_members, :boolean, description: "Include sorted list of followed pubkey hex values")
    run(fn args, state -> reply(Actions.follow_list_status(args), state) end)
  end

  tool "follow_list_refresh",
       "Start a background follow-list refresh from relays (returns current cache immediately)" do
    run(fn _args, state -> reply(Actions.follow_list_refresh(), state) end)
  end

  tool "follow_list_member",
       "Check whether an author pubkey or source is on the configured follow list" do
    annotations(readOnlyHint: true)
    param(:pubkey, :string, description: "Author npub or hex pubkey")
    param(:source_id, :integer, description: "Source id (uses resolved author_pubkey)")
    run(fn args, state -> reply(Actions.follow_list_member(args), state) end)
  end

  tool "list_sources", "List all RSS/Atom sources" do
    annotations(readOnlyHint: true)
    run(fn _args, state -> reply(Actions.list_sources(), state) end)
  end

  tool "get_source", "Get one source by id, including composition options" do
    annotations(readOnlyHint: true)
    param(:source_id, :integer, required: true, description: "Source id")
    run(fn args, state -> reply(Actions.get_source(args), state) end)
  end

  tool "discover_feeds", "Find RSS/Atom feeds on a website URL" do
    annotations(readOnlyHint: true)
    param(:url, :string, required: true, description: "Website or feed URL")
    run(fn args, state -> reply(Actions.discover_feeds(args), state) end)
  end

  tool "preview_feed", "Preview items from a feed URL without importing" do
    annotations(readOnlyHint: true)
    param(:url, :string, required: true, description: "Feed URL")
    run(fn args, state -> reply(Actions.preview_feed(args), state) end)
  end

  tool "preview_compose", "Preview Markdown conversion and Nostr event shape for a feed item" do
    annotations(readOnlyHint: true)
    param(:url, :string, required: true, description: "Feed URL")
    param(:guid, :string, description: "Optional item guid; defaults to the first item")
    param(:type, :string, description: "rss or atom when auto-detection fails")
    param(:source_id, :integer, description: "Existing source to reuse saved settings from")

    param(:fetch_source_from, :string,
      description: "content (feed XML) or fetch_from_url (article page)"
    )

    param(:publish_as, :string,
      description: "draft, draft_plain, article, or video for the event preview"
    )

    param(:pubkey, :string, description: "Author npub or hex for draft previews")
    param(:body_selector, :string, description: "CSS selector for the article body")
    param(:start_at, :string, description: "XPath marker: skip content before this block")
    param(:skip_classes, :string, description: "Comma-separated CSS class fragments to drop")

    param(:body_selector_auto, :string,
      description: "true to auto-pick a body selector when body_selector is empty"
    )

    param(:conversion_rules, :string, description: "Custom HTML conversion rules JSON")

    param(:excluded_hashtags, :string,
      description: "Comma-separated RSS categories dropped from published t tags"
    )

    param(:fixed_hashtags, :string,
      description: "Comma-separated hashtags added to every article"
    )

    param(:mirror_media, :string, description: "For video previews: blossom or original")
    param(:language, :string, description: "ISO 639-1 feed language for generated labels")
    run(fn args, state -> reply(Actions.preview_compose(args), state) end)
  end

  tool "add_source", "Add an RSS/Atom source" do
    param(:name, :string, required: true, description: "Display name")
    param(:url, :string, required: true, description: "Feed URL")
    param(:type, :string, description: "rss or atom (default atom)")
    param(:language, :string, description: "ISO 639-1 language code (default de)")
    param(:active, :boolean, description: "Enable imports for this source (default true)")
    param(:mode, :string, description: "setup or automated (default setup)")
    param(:publish_as, :string, description: "draft, draft_plain, article, or video")
    param(:mirror_media, :string, description: "For video sources: blossom or original")

    param(:pubkey, :string, description: "Author npub or hex pubkey (required for drafts)")

    param(:signing_nsec, :string, description: "Author nsec for article sources")
    param(:bunker_connection, :string, description: "NIP-46 bunker URL for article sources")
    param(:fetch_source_from, :string, description: "content or fetch_from_url")
    param(:body_selector, :string, description: "CSS selector for the article body")
    param(:start_at, :string, description: "XPath marker: skip content before this block")
    param(:skip_classes, :string, description: "Comma-separated CSS class fragments to drop")
    param(:conversion_rules, :string, description: "Custom HTML conversion rules JSON")
    param(:start_guid, :string, description: "Item guid to start importing from, or __future_only__")
    param(:start_published_at, :string, description: "ISO-8601; skip articles older than this")

    param(:staging_hold_minutes, :integer,
      description: "Minutes to wait after staging before auto-publish"
    )

    param(:notify_pubkey, :string,
      description:
        "npub or hex to receive a NIP-17 staging DM (NIP-05 or public, plus NOSTR_RELAYS_INBOX)"
    )

    param(:fixed_hashtags, :string,
      description: "Comma-separated hashtags added to every article"
    )

    param(:excluded_hashtags, :string,
      description: "Comma-separated RSS categories dropped from published t tags"
    )

    param(:public, :boolean, description: "Legacy public flag on the source record")

    run(fn args, state -> reply(Actions.add_source(args), state) end)
  end

  tool "update_source", "Update a source's feed, language, publishing, or composition settings" do
    param(:source_id, :integer, required: true)
    param(:name, :string)
    param(:url, :string)
    param(:language, :string)
    param(:active, :boolean)
    param(:public, :boolean)
    param(:publish_as, :string, description: "draft, draft_plain, article, or video")
    param(:mirror_media, :string, description: "For video sources: blossom or original")
    param(:mode, :string, description: "setup or automated")
    param(:pubkey, :string)
    param(:signing_nsec, :string)
    param(:bunker_connection, :string)
    param(:fetch_source_from, :string)
    param(:body_selector, :string)
    param(:start_at, :string, description: "XPath marker: skip content before this block")
    param(:skip_classes, :string)
    param(:conversion_rules, :string, description: "Custom HTML conversion rules JSON")
    param(:start_guid, :string, description: "Item guid to start importing from")
    param(:start_published_at, :string)

    param(:staging_hold_minutes, :integer,
      description: "Minutes to wait after staging before auto-publish"
    )

    param(:notify_pubkey, :string,
      description:
        "npub or hex to receive a NIP-17 staging DM (NIP-05 or public, plus NOSTR_RELAYS_INBOX)"
    )

    param(:fixed_hashtags, :string,
      description: "Comma-separated hashtags added to every article"
    )

    param(:excluded_hashtags, :string,
      description: "Comma-separated RSS categories dropped from published t tags"
    )

    run(fn args, state -> reply(Actions.update_source(args), state) end)
  end

  tool "toggle_source", "Enable or disable a source" do
    param(:source_id, :integer, required: true)
    run(fn args, state -> reply(Actions.toggle_source(args), state) end)
  end

  tool "duplicate_source", "Duplicate a source (same site, new feed URL can be set afterward)" do
    param(:source_id, :integer, required: true)
    param(:name, :string, description: "Optional name for the copy")
    run(fn args, state -> reply(Actions.duplicate_source(args), state) end)
  end

  tool "delete_source", "Delete a source and all of its articles" do
    param(:source_id, :integer, required: true)
    run(fn args, state -> reply(Actions.delete_source(args), state) end)
  end

  tool "import_source", "Import new articles from a source and process them" do
    param(:source_id, :integer, required: true)
    run(fn args, state -> reply(Actions.import_source(args), state) end)
  end

  tool "reprocess_posts", "Reconvert selected articles from stored HTML" do
    param(:source_id, :integer, required: true)
    param(:post_ids, {:array, :integer}, required: true, description: "Article ids to reprocess")
    run(fn args, state -> reply(Actions.reprocess_posts(args), state) end)
  end

  tool "reprocess_errors",
       "Reconvert all error-status articles, optionally limited to one source (same as bulk Retry on the Error tab)" do
    param(:source_id, :integer, description: "Optional source id to limit retries")
    run(fn args, state -> reply(Actions.reprocess_errors(args), state) end)
  end

  tool "publish_source_posts", "Publish selected staging articles from a source" do
    param(:source_id, :integer, required: true)
    param(:post_ids, {:array, :integer}, required: true)
    run(fn args, state -> reply(Actions.publish_source_posts(args), state) end)
  end

  tool "list_posts", "List articles, optionally filtered by status, source, or search text" do
    annotations(readOnlyHint: true)

    param(:status, :string,
      description: "new, processing, staging, processed, pending_images, published, error"
    )

    param(:source_id, :integer)
    param(:q, :string, description: "Search title, content, summary, or URL")
    param(:page, :integer)
    param(:per_page, :integer)
    run(fn args, state -> reply(Actions.list_posts(args), state) end)
  end

  tool "get_post", "Get one article including Markdown content" do
    annotations(readOnlyHint: true)
    param(:post_id, :integer, required: true)
    run(fn args, state -> reply(Actions.get_post(args), state) end)
  end

  tool "process_post", "Convert an article to Markdown and upload images" do
    param(:post_id, :integer, required: true)
    run(fn args, state -> reply(Actions.process_post(args), state) end)
  end

  tool "upload_post_images",
       "Upload pending images for an article (same as process_post for pending_images status)" do
    param(:post_id, :integer, required: true)
    run(fn args, state -> reply(Actions.upload_post_images(args), state) end)
  end

  tool "reprocess_post", "Reconvert one article from stored HTML" do
    param(:post_id, :integer, required: true)
    run(fn args, state -> reply(Actions.reprocess_post(args), state) end)
  end

  tool "publish_post", "Publish one staging article, or republish a published article" do
    param(:post_id, :integer, required: true)
    run(fn args, state -> reply(Actions.publish_post(args), state) end)
  end

  tool "update_post",
       "Edit a staging or published article (title, summary, hashtags, language, Markdown)" do
    param(:post_id, :integer, required: true)
    param(:title, :string)
    param(:summary, :string)
    param(:content, :string, description: "Markdown body")
    param(:language, :string)
    param(:hashtags, :string, description: "Comma-separated hashtags")
    param(:categories, :string, description: "Alias for hashtags")
    run(fn args, state -> reply(Actions.update_post(args), state) end)
  end

  tool "revise_post",
       "Reconvert a published article from stored HTML, move it back to staging, and restart the hold" do
    param(:post_id, :integer, required: true)
    run(fn args, state -> reply(Actions.revise_post(args), state) end)
  end

  tool "delete_post", "Delete one article" do
    param(:post_id, :integer, required: true)
    run(fn args, state -> reply(Actions.delete_post(args), state) end)
  end

  tool "scheduler_status", "Scheduler running state and last task runs" do
    annotations(readOnlyHint: true)
    run(fn _args, state -> reply(Actions.scheduler_status(), state) end)
  end

  tool "start_scheduler", "Start the import/process/export scheduler" do
    run(fn _args, state -> reply(Actions.start_scheduler(), state) end)
  end

  tool "stop_scheduler", "Stop the scheduler" do
    run(fn _args, state -> reply(Actions.stop_scheduler(), state) end)
  end

  tool "run_scheduler_task", "Run import, process, export, or cleanup once" do
    param(:task, :string, required: true, description: "import, process, export, or cleanup")
    run(fn args, state -> reply(Actions.run_scheduler_task(args), state) end)
  end

  resource "rss2nostr://status", "Current source and post counts" do
    mime_type("application/json")

    read(fn %{uri: uri}, state ->
      {:ok, overview} = Actions.get_status()
      {:ok, %{uri: uri, text: Jason.encode!(overview, pretty: true)}, state}
    end)
  end

  resource "rss2nostr://sources", "All configured sources" do
    mime_type("application/json")

    read(fn %{uri: uri}, state ->
      {:ok, data} = Actions.list_sources()
      {:ok, %{uri: uri, text: Jason.encode!(data, pretty: true)}, state}
    end)
  end

  resource "rss2nostr://settings", "Non-secret application settings" do
    mime_type("application/json")

    read(fn %{uri: uri}, state ->
      {:ok, data} = Actions.get_settings()
      {:ok, %{uri: uri, text: Jason.encode!(data, pretty: true)}, state}
    end)
  end

  resource "rss2nostr://follow_list", "Configured Nostr follow list cache status" do
    mime_type("application/json")

    read(fn %{uri: uri}, state ->
      {:ok, data} = Actions.follow_list_status(%{})
      {:ok, %{uri: uri, text: Jason.encode!(data, pretty: true)}, state}
    end)
  end

  prompt "add_source", "Walk through discovering a feed and adding a source" do
    arg(:website, required: true, description: "Website or feed URL")

    render(fn args, state ->
      website = args[:website] || args["website"]

      {:ok,
       """
       Add this site as an RSS2Nostr source: #{website}

       1. get_settings for compose presets, languages, and relay lists.
       2. discover_feeds with the URL, then preview_feed on the best feed.
       3. preview_compose on a sample item. Try fetch_source_from, body_selector,
          start_at, publish_as, and pubkey before saving.
       4. add_source with name, url, language, publish_as, composition, and publishing
          fields. Drafts need pubkey. Articles need signing_nsec or bunker_connection.
          Set start_guid from preview_feed when limiting the import window.
       5. update_source with mode automated once signing is configured.
       6. import_source, then list_posts. Use upload_post_images for pending_images.
       """, state}
    end)
  end

  prompt "triage_posts", "Review recent articles that need processing or publishing" do
    render(fn _args, state ->
      {:ok,
       """
       Check RSS2Nostr article health:

       1. get_status
       2. list_posts with status pending_images, then processed, then error
       3. reprocess_errors for all error articles, or reprocess_post / reprocess_posts for specific ids
       4. upload_post_images or process_post for pending_images
       5. publish_post only when publishable is true (status processed)
       6. follow_list_status / follow_list_member when NOSTR_AUTHORS_FOLLOW_LIST_PUBKEY is set
       """, state}
    end)
  end

  @spec reply({:ok, term()} | {:error, term()}, term()) ::
          {:ok, String.t(), term()} | {:error, String.t(), term()}
  defp reply({:ok, data}, state), do: {:ok, Jason.encode!(data, pretty: true), state}
  defp reply({:error, reason}, state) when is_binary(reason), do: {:error, reason, state}
  defp reply({:error, reason}, state), do: {:error, inspect(reason), state}
end
