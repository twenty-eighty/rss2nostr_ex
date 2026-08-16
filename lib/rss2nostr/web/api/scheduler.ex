defmodule Rss2Nostr.Web.API.Scheduler do
  @moduledoc """
  API handlers for scheduler operations.
  """

  alias Rss2Nostr.Nostr.Keys
  alias Rss2Nostr.Scheduler
  alias Rss2Nostr.Scheduler.Tasks

  def status do
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

  def start do
    case Process.whereis(Rss2Nostr.Scheduler) do
      nil ->
        Scheduler.start_link([])
        {:ok, "Scheduler started"}

      _pid ->
        {:ok, "Scheduler already running"}
    end
  end

  def stop do
    case Process.whereis(Rss2Nostr.Scheduler) do
      nil ->
        {:ok, "Scheduler not running"}

      _pid ->
        Scheduler.stop()
        {:ok, "Scheduler stopped"}
    end
  end

  def run_task(task) when task in ["import", "process", "export", "cleanup"] do
    task_atom = String.to_atom(task)

    case Process.whereis(Rss2Nostr.Scheduler) do
      nil ->
        # Run directly without scheduler
        result =
          case task_atom do
            :import -> Tasks.run_import()
            :process -> Tasks.run_process()
            :export -> Tasks.run_export(get_export_config())
            :cleanup -> Tasks.run_cleanup()
          end

        {:ok, "Task #{task} executed: #{inspect(result)}"}

      _pid ->
        Scheduler.run_task(task_atom)
        {:ok, "Task #{task} triggered"}
    end
  end

  def run_task(_task), do: {:error, "Invalid task"}

  defp get_export_config do
    nsec = System.get_env("NOSTR_NSEC")

    private_key =
      if nsec do
        case Keys.parse_private_key(nsec) do
          {:ok, key} -> key
          _ -> nil
        end
      end

    %{private_key: private_key}
  end
end
