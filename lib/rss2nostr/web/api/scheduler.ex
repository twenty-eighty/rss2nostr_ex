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
          intervals: %{import: "15m", process: "5m", export: "10m", cleanup: "1h"},
          task_status: %{import: :idle, process: :idle, export: :idle, cleanup: :idle},
          last_run: %{},
          last_result: %{},
          export_configured: System.get_env("NOSTR_NSEC") != nil
        }

      _pid ->
        Scheduler.status()
    end
  end

  def start do
    with :ok <- ensure_started() do
      case Scheduler.start() do
        :ok -> {:ok, "Scheduler started"}
        {:error, :already_running} -> {:ok, "Scheduler already running"}
      end
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

  defp ensure_started do
    case Process.whereis(Rss2Nostr.Scheduler) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        # Unlinked: a start_link from the HTTP request would die with the Plug process.
        case GenServer.start(Rss2Nostr.Scheduler, [], name: Rss2Nostr.Scheduler) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

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
