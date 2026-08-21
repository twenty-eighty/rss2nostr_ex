defmodule Rss2Nostr.Web.Views.Dashboard do
  @moduledoc """
  Dashboard view showing overview statistics.
  """

  alias Rss2Nostr.Web.Views.Layout
  alias Rss2Nostr.{Sources, Posts}
  alias Rss2Nostr.Posts.Post

  def render do
    # Gather statistics
    sources = Sources.list_sources()
    active_sources = Enum.count(sources, & &1.active)

    new_posts = length(Posts.list_posts_by_status(Post.status_new(), limit: 1000))
    pending_images = length(Posts.list_pending_image_posts(limit: 1000))
    processed_posts = length(Posts.list_processed_posts(limit: 1000))
    published_posts = length(Posts.list_posts_by_status(Post.status_published(), limit: 1000))

    # Check scheduler status
    scheduler_running = Rss2Nostr.Web.API.Scheduler.status().running

    content = """
    <h1>Dashboard</h1>

    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-value">#{length(sources)}</div>
        <div class="stat-label">Sources</div>
        <div class="stat-detail">#{active_sources} active</div>
      </div>

      <div class="stat-card">
        <div class="stat-value">#{new_posts}</div>
        <div class="stat-label">New Posts</div>
        <div class="stat-detail">Awaiting processing</div>
      </div>

      <div class="stat-card">
        <div class="stat-value">#{pending_images}</div>
        <div class="stat-label">Pending images</div>
        <div class="stat-detail">Need Blossom upload</div>
      </div>

      <div class="stat-card">
        <div class="stat-value">#{processed_posts}</div>
        <div class="stat-label">Staging</div>
        <div class="stat-detail">Images uploaded, waiting to publish</div>
      </div>

      <div class="stat-card">
        <div class="stat-value">#{published_posts}</div>
        <div class="stat-label">Published</div>
        <div class="stat-detail">On Nostr</div>
      </div>
    </div>

    <div class="dashboard-section">
      <h2>Scheduler Status</h2>
      <div class="status-indicator #{if scheduler_running, do: "status-running", else: "status-stopped"}">
        #{if scheduler_running, do: "Running", else: "Stopped"}
      </div>
      <p>
        <a href="/scheduler" class="btn btn-secondary">Manage Scheduler</a>
      </p>
    </div>

    <div class="dashboard-section">
      <h2>Quick Actions</h2>
      <div class="action-buttons">
        <a href="/sources/new" class="btn btn-primary">Add Source</a>
        <form action="/scheduler/run/import" method="POST" style="display:inline">
          <button type="submit" class="btn btn-secondary">Run Import</button>
        </form>
        <form action="/scheduler/run/process" method="POST" style="display:inline">
          <button type="submit" class="btn btn-secondary">Run Process</button>
        </form>
      </div>
    </div>

    <div class="dashboard-section">
      <h2>Recent Posts</h2>
      #{render_recent_posts()}
    </div>
    """

    Layout.render("Dashboard", content, active_nav: "dashboard")
  end

  defp render_recent_posts do
    posts = Posts.list_recent_posts(limit: 5)

    if Enum.empty?(posts) do
      "<p class=\"empty-state\">No posts yet. Add a source and run import.</p>"
    else
      rows =
        Enum.map_join(posts, "", fn post ->
          status_class = status_to_class(post.status)
          status_label = Post.status_label(post.status)

          """
          <tr>
            <td><a href="/posts/#{post.id}">#{escape_html(truncate(post.title, 50))}</a></td>
            <td><span class="badge #{status_class}">#{status_label}</span></td>
            <td>#{format_datetime(post.inserted_at)}</td>
          </tr>
          """
        end)

      """
      <table class="table">
        <thead>
          <tr>
            <th>Title</th>
            <th>Status</th>
            <th>Imported</th>
          </tr>
        </thead>
        <tbody>
          #{rows}
        </tbody>
      </table>
      <p><a href="/posts">View all posts &rarr;</a></p>
      """
    end
  end

  defp status_to_class(status) do
    case status do
      0 -> "badge-new"
      1 -> "badge-processing"
      2 -> "badge-processed"
      6 -> "badge-published"
      9 -> "badge-pending-images"
      _ -> "badge-error"
    end
  end

  defp truncate(nil, _max), do: ""

  defp truncate(str, max) when is_binary(str) do
    if String.length(str) > max do
      String.slice(str, 0, max) <> "..."
    else
      str
    end
  end

  defp escape_html(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp format_datetime(nil), do: "-"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end
end
