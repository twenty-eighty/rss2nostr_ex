defmodule Rss2Nostr.Web.Views.Scheduler do
  @moduledoc """
  Views for scheduler management.
  """

  alias Rss2Nostr.Web.Views.Layout
  alias Rss2Nostr.Scheduler

  def index do
    status = get_scheduler_status()

    content = """
    <h1>Scheduler</h1>

    <div class="scheduler-status">
      <div class="status-indicator #{if status.running, do: "status-running", else: "status-stopped"}">
        Status: #{if status.running, do: "Running", else: "Stopped"}
      </div>

      <div class="scheduler-controls">
        #{if status.running do
      """
      <form action="/scheduler/stop" method="POST" style="display:inline">
        <button type="submit" class="btn btn-danger">Stop Scheduler</button>
      </form>
      """
    else
      """
      <form action="/scheduler/start" method="POST" style="display:inline">
        <button type="submit" class="btn btn-primary">Start Scheduler</button>
      </form>
      """
    end}
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
            <th>Action</th>
          </tr>
        </thead>
        <tbody>
          #{render_task_row("import", status)}
          #{render_task_row("process", status)}
          #{render_task_row("export", status)}
          #{render_task_row("cleanup", status)}
        </tbody>
      </table>
    </div>

    <div class="scheduler-section">
      <h2>Manual Execution</h2>
      <p>Run individual tasks manually:</p>
      <div class="action-buttons">
        <form action="/scheduler/run/import" method="POST" style="display:inline">
          <button type="submit" class="btn btn-secondary">Run Import</button>
        </form>
        <form action="/scheduler/run/process" method="POST" style="display:inline">
          <button type="submit" class="btn btn-secondary">Run Process</button>
        </form>
        <form action="/scheduler/run/export" method="POST" style="display:inline">
          <button type="submit" class="btn btn-secondary">Run Export</button>
        </form>
        <form action="/scheduler/run/cleanup" method="POST" style="display:inline">
          <button type="submit" class="btn btn-secondary">Run Cleanup</button>
        </form>
      </div>
    </div>

    <div class="scheduler-section">
      <h2>Export Configuration</h2>
      #{if status.export_configured do
      "<p class=\"success\">Export is configured with a private key.</p>"
    else
      """
      <p class=\"warning\">Export is not configured. Set the NOSTR_NSEC environment variable or configure it in settings.</p>
      <p><a href="/settings" class="btn btn-secondary">Configure Settings</a></p>
      """
    end}
    </div>
    """

    Layout.render("Scheduler", content, active_nav: "scheduler")
  end

  defp get_scheduler_status do
    case Process.whereis(Rss2Nostr.Scheduler) do
      nil ->
        %{
          running: false,
          intervals: %{import: "15m", process: "5m", export: "10m", cleanup: "24h"},
          task_status: %{import: :idle, process: :idle, export: :idle, cleanup: :idle},
          last_run: %{},
          export_configured: System.get_env("NOSTR_NSEC") != nil
        }

      _pid ->
        Scheduler.status()
    end
  end

  defp render_task_row(task, status) do
    task_atom = String.to_atom(task)
    interval = status.intervals[task_atom] || status.intervals[task] || "-"
    task_status = status.task_status[task_atom] || :idle
    last_run = format_last_run(status.last_run[task_atom])

    status_class =
      case task_status do
        :completed -> "badge-success"
        :running -> "badge-processing"
        :failed -> "badge-error"
        _ -> "badge-idle"
      end

    """
    <tr>
      <td><strong>#{String.capitalize(task)}</strong></td>
      <td>#{interval}</td>
      <td><span class="badge #{status_class}">#{task_status}</span></td>
      <td>#{last_run}</td>
      <td>
        <form action="/scheduler/run/#{task}" method="POST" style="display:inline">
          <button type="submit" class="btn btn-small">Run Now</button>
        </form>
      </td>
    </tr>
    """
  end

  defp format_last_run(nil), do: "Never"

  defp format_last_run(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end
end
