defmodule Rss2NostrWeb.AdminLiveTest do
  use Rss2NostrWeb.ConnCase, async: false

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources

  defp unique_url do
    "https://example.com/feed-#{System.unique_integer([:positive])}.xml"
  end

  defp create_source(attrs \\ %{}) do
    {:ok, source} =
      Sources.create_source(
        Map.merge(
          %{
            name: "Test Source",
            url: unique_url(),
            type: "rss",
            language: "en",
            active: true
          },
          attrs
        )
      )

    source
  end

  defp create_post(source, attrs) do
    url = attrs[:source_url] || "https://example.com/article-#{System.unique_integer([:positive])}"

    {:ok, post} =
      Posts.create_post(
        Map.merge(
          %{
            title: "Test article",
            source_url: url,
            source_url_hash: Post.generate_url_hash(url),
            source_id: source.id,
            status: Post.status_processed()
          },
          attrs
        )
      )

    post
  end

  describe "authentication" do
    test "GET / redirects to login with next path", %{conn: conn} do
      conn = get(conn, "/")

      assert redirected_to(conn) == "/login?next=#{URI.encode_www_form("/")}"
    end

    test "GET /sources/new redirects to login", %{conn: conn} do
      conn = get(conn, "/sources/new")

      assert redirected_to(conn) =~ "/login?next="
      assert redirected_to(conn) =~ "%2Fsources%2Fnew"
    end
  end

  describe "dashboard" do
    test "renders stats and recent posts", %{conn: conn} do
      source = create_source()
      create_post(source, %{title: "Recent headline"})

      {:ok, _view, html} = conn |> authed_conn() |> live("/")

      assert html =~ "Dashboard"
      assert html =~ "Sources"
      assert html =~ "Staging"
      assert html =~ "Recent headline"
      assert html =~ "Add Source"
    end
  end

  describe "sources" do
    test "lists sources and toggles active", %{conn: conn} do
      source = create_source(%{name: "Toggle Me"})

      {:ok, view, html} = conn |> authed_conn() |> live("/sources")

      assert html =~ "Toggle Me"
      assert html =~ "Disable"

      html = render_click(view, "toggle", %{"id" => to_string(source.id)})
      assert html =~ "Enable"
    end

    test "articles tab lists posts and selection events", %{conn: conn} do
      source = create_source(%{name: "Article Source"})
      post = create_post(source, %{title: "Selectable staging post"})

      {:ok, view, html} = conn |> authed_conn() |> live("/sources/#{source.id}?tab=articles")

      assert html =~ "Article Source"
      assert html =~ "Selectable staging post"
      assert html =~ "Import now"
      assert html =~ "Reprocess selected"

      html = render_click(view, "toggle_post", %{"id" => to_string(post.id)})
      assert html =~ "Reprocess selected"
    end

    test "add-source form discovers nothing until submitted complete", %{conn: conn} do
      {:ok, _view, html} = conn |> authed_conn() |> live("/sources/new")

      assert html =~ "Add Source"
      assert html =~ "Find feeds"
      assert html =~ ~s(id="submit-source")
    end

    test "creates a source without hitting the network", %{conn: conn} do
      url = unique_url()
      pubkey = admin_pubkey()

      {:ok, view, _html} = conn |> authed_conn() |> live("/sources/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               render_submit(view, "save", %{
                 "website" => url,
                 "url" => url,
                 "name" => "Live Created Source",
                 "language" => "en",
                 "type" => "rss",
                 "publish_as" => "draft",
                 "pubkey" => pubkey
               })

      assert to =~ ~r"^/sources/\d+$"
      assert Enum.any?(Sources.list_sources(), &(&1.name == "Live Created Source"))
    end
  end

  describe "posts" do
    test "lists posts with filters", %{conn: conn} do
      source = create_source(%{name: "Post Source"})
      create_post(source, %{title: "Listed post"})

      {:ok, _view, html} = conn |> authed_conn() |> live("/posts")

      assert html =~ "Listed post"
      assert html =~ "Staging"
    end

    test "shows a processed post editor", %{conn: conn} do
      source = create_source()
      post = create_post(source, %{title: "Editable post", content: "Hello **world**"})

      {:ok, _view, html} = conn |> authed_conn() |> live("/posts/#{post.id}")

      assert html =~ "Editable post"
      assert html =~ "Hello **world**"
      assert html =~ "Publish to"
    end
  end

  describe "scheduler and settings" do
    test "renders scheduler controls", %{conn: conn} do
      {:ok, _view, html} = conn |> authed_conn() |> live("/scheduler")

      assert html =~ "Scheduler"
      assert html =~ "Task Intervals"
      assert html =~ "Run Now"
    end

    test "renders settings", %{conn: conn} do
      {:ok, _view, html} = conn |> authed_conn() |> live("/settings")

      assert html =~ "Settings"
      assert html =~ "NOSTR_NSEC"
      assert html =~ "Admin access"
    end
  end
end
