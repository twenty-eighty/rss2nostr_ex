defmodule Rss2NostrWeb.DashboardLive do
  @moduledoc false

  use Rss2NostrWeb, :live_view

  alias Rss2Nostr.{Posts, Sources}
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Web.API.Scheduler

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:active_nav, "dashboard")
     |> assign_stats()}
  end

  @impl true
  def handle_event("run_task", %{"task" => task}, socket) when task in ["import", "process"] do
    case Scheduler.run_task(task) do
      {:ok, message} ->
        {:noreply, socket |> put_flash(:info, message) |> assign_stats()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, to_string(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Dashboard</h1>

    <div class="stats-grid">
      <div class="stat-card">
        <div class="stat-value">{@source_count}</div>
        <div class="stat-label">Sources</div>
        <div class="stat-detail">{@active_sources} active</div>
      </div>
      <div class="stat-card">
        <div class="stat-value">{@new_posts}</div>
        <div class="stat-label">New Posts</div>
        <div class="stat-detail">Awaiting processing</div>
      </div>
      <div class="stat-card">
        <div class="stat-value">{@pending_images}</div>
        <div class="stat-label">Pending images</div>
        <div class="stat-detail">Need Blossom upload</div>
      </div>
      <div class="stat-card">
        <div class="stat-value">{@processed_posts}</div>
        <div class="stat-label">Staging</div>
        <div class="stat-detail">Images uploaded, waiting to publish</div>
      </div>
      <div class="stat-card">
        <div class="stat-value">{@published_posts}</div>
        <div class="stat-label">Published</div>
        <div class="stat-detail">On Nostr</div>
      </div>
    </div>

    <div class="dashboard-section">
      <h2>Scheduler Status</h2>
      <div class={"status-indicator #{if @scheduler_running, do: "status-running", else: "status-stopped"}"}>
        {if @scheduler_running, do: "Running", else: "Stopped"}
      </div>
      <p>
        <a href="/scheduler" class="btn btn-secondary">Manage Scheduler</a>
      </p>
    </div>

    <div class="dashboard-section">
      <h2>Quick Actions</h2>
      <div class="action-buttons">
        <a href="/sources/new" class="btn btn-primary">Add Source</a>
        <button type="button" class="btn btn-secondary" phx-click="run_task" phx-value-task="import">
          Run Import
        </button>
        <button type="button" class="btn btn-secondary" phx-click="run_task" phx-value-task="process">
          Run Process
        </button>
      </div>
    </div>

    <div class="dashboard-section">
      <h2>Recent Posts</h2>
      <%= if @recent_posts == [] do %>
        <p class="empty-state">No posts yet. Add a source and run import.</p>
      <% else %>
        <table class="table">
          <thead>
            <tr>
              <th>Title</th>
              <th>Status</th>
              <th>Imported</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={post <- @recent_posts}>
              <td><a href={"/posts/#{post.id}"}>{truncate(post.title, 50)}</a></td>
              <td><.status_badge status={post.status} /></td>
              <td>{format_datetime(post.inserted_at)}</td>
            </tr>
          </tbody>
        </table>
        <p><a href="/posts">View all posts →</a></p>
      <% end %>
    </div>
    """
  end

  defp assign_stats(socket) do
    sources = Sources.list_sources()

    socket
    |> assign(:source_count, length(sources))
    |> assign(:active_sources, Enum.count(sources, & &1.active))
    |> assign(:new_posts, length(Posts.list_posts_by_status(Post.status_new(), limit: 1000)))
    |> assign(
      :pending_images,
      length(Posts.list_pending_image_posts(limit: 1000))
    )
    |> assign(
      :processed_posts,
      length(Posts.list_processed_posts(limit: 1000))
    )
    |> assign(
      :published_posts,
      length(Posts.list_posts_by_status(Post.status_published(), limit: 1000))
    )
    |> assign(:scheduler_running, Scheduler.status().running)
    |> assign(:recent_posts, Posts.list_recent_posts(limit: 5))
  end
end
