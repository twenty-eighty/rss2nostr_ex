defmodule Rss2NostrWeb.SchedulerLive do
  @moduledoc false

  use Rss2NostrWeb, :live_view

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Web.API.Scheduler

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Scheduler")
     |> assign(:active_nav, "scheduler")
     |> assign_status()}
  end

  @impl true
  def handle_event("start", _params, socket) do
    case Scheduler.start() do
      {:ok, message} -> {:noreply, socket |> put_flash(:info, message) |> assign_status()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, to_string(reason))}
    end
  end

  def handle_event("stop", _params, socket) do
    {:ok, message} = Scheduler.stop()
    {:noreply, socket |> put_flash(:info, message) |> assign_status()}
  end

  def handle_event("run_task", %{"task" => task}, socket)
      when task in ["import", "process", "export", "cleanup"] do
    case Scheduler.run_task(task) do
      {:ok, message} -> {:noreply, socket |> put_flash(:info, message) |> assign_status()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, to_string(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Scheduler</h1>

    <div class="scheduler-status">
      <div class={"status-indicator #{if @status.running, do: "status-running", else: "status-stopped"}"}>
        Status: {if @status.running, do: "Running", else: "Stopped"}
      </div>
      <div class="scheduler-controls">
        <button
          :if={@status.running}
          type="button"
          class="btn btn-danger"
          phx-click="stop"
        >
          Stop Scheduler
        </button>
        <button
          :if={not @status.running}
          type="button"
          class="btn btn-primary"
          phx-click="start"
        >
          Start Scheduler
        </button>
      </div>
    </div>

    <div class="scheduler-section">
      <h2>Task Intervals</h2>
      <table class="table">
        <thead>
          <tr>
            <th>Task</th>
            <th>Interval</th>
            <th>Status</th>
            <th>Last Run</th>
            <th>Last Result</th>
            <th>Action</th>
          </tr>
        </thead>
        <tbody>
          <.task_row :for={task <- ["import", "process", "export", "cleanup"]} task={task} status={@status} />
        </tbody>
      </table>
    </div>

    <div class="scheduler-section">
      <h2>Draft cleanup</h2>
      <p class="help-text">
        Finds kind 30024 / 31234 drafts signed by the app key
        (<code>NOSTR_NSEC</code>) and deletes them when a kind 30023 with the
        same <code>d</code> tag has been published by the author named in the
        draft’s <code>p</code> tag. This includes drafts that did not come from
        an imported RSS feed. It runs every hour.
      </p>
      <table class="table">
        <tr>
          <th>Drafts deleted</th>
          <td>{@status.cleanup_stats.deleted}</td>
        </tr>
        <tr>
          <th>Published, drafts still pending</th>
          <td>{@status.cleanup_stats.pending}</td>
        </tr>
        <tr>
          <th>Last cleanup run</th>
          <td>{cleanup_last(@status)}</td>
        </tr>
      </table>
    </div>

    <div class="scheduler-section">
      <h2>Export Configuration</h2>
      <%= if @status.export_configured do %>
        <p class="success">Export is configured with a private key.</p>
      <% else %>
        <p class="warning">
          Export is not configured. Set the NOSTR_NSEC environment variable or configure it in settings.
        </p>
        <p><a href="/settings" class="btn btn-secondary">Configure Settings</a></p>
      <% end %>
    </div>
    """
  end

  defp task_row(assigns) do
    task_atom = String.to_atom(assigns.task)
    status = assigns.status
    interval = status.intervals[task_atom] || status.intervals[assigns.task] || "-"
    task_status = status.task_status[task_atom] || :idle

    assigns =
      assigns
      |> assign(:interval, format_interval(interval))
      |> assign(:task_status, task_status)
      |> assign(:last_run, format_last_run(status.last_run[task_atom]))
      |> assign(:last_result, format_last_result(Map.get(status, :last_result, %{})[task_atom]))
      |> assign(:status_class, scheduler_status_class(task_status))

    ~H"""
    <tr>
      <td><strong>{String.capitalize(@task)}</strong></td>
      <td>{@interval}</td>
      <td><span class={"badge #{@status_class}"}>{@task_status}</span></td>
      <td>{@last_run}</td>
      <td>{@last_result}</td>
      <td>
        <button type="button" class="btn btn-small" phx-click="run_task" phx-value-task={@task}>
          Run Now
        </button>
      </td>
    </tr>
    """
  end

  defp assign_status(socket) do
    status =
      Scheduler.status()
      |> Map.put(:cleanup_stats, %{
        deleted: Posts.count_draft_cleaned(),
        pending: Posts.count_draft_cleanup_candidates()
      })

    assign(socket, :status, status)
  end

  defp cleanup_last(status) do
    last_run = format_last_run(status.last_run[:cleanup])
    result = format_last_result(Map.get(status, :last_result, %{})[:cleanup])

    if result == "—" do
      last_run
    else
      "#{last_run} — #{result}"
    end
  end
end
