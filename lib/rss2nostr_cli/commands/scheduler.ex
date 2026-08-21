defmodule Rss2Nostr.CLI.Commands.Scheduler do
  @moduledoc """
  CLI commands for managing the scheduler.
  """

  alias Rss2Nostr.CLI.Output
  alias Rss2Nostr.Scheduler
  alias Rss2Nostr.Nostr.{Keys, NIP19, Relays}

  @doc """
  Starts the scheduler daemon.
  This runs in the foreground and executes tasks on schedule.
  """
  def start(options) do
    nsec = Map.get(options, :nsec)
    relays = parse_relays(Map.get(options, :relays))
    audience = Relays.parse_audience(Map.get(options, :audience))
    upload_images = Map.get(options, :upload_images, false)

    Output.info("Starting RSS2Nostr Scheduler...")
    Output.info("")

    # Get export config
    export_config =
      case get_private_key(nsec) do
        {:ok, private_key, pubkey_hex} ->
          Output.info("Export enabled with pubkey: #{String.slice(pubkey_hex, 0, 8)}...")
          describe_relay_target(relays, audience)

          %{private_key: private_key, upload_images: upload_images}
          |> maybe_put(:relays, relays)
          |> maybe_put(:audience, audience)

        {:error, _reason} ->
          Output.warning("No private key configured - export task will be skipped")
          %{}
      end

    # Get intervals from config
    config = Application.get_env(:rss2nostr, Rss2Nostr.Scheduler, [])
    intervals = config[:intervals] || %{}

    Output.info("")
    Output.info("Task intervals:")
    Output.info("  Import:  #{format_interval(intervals[:import] || :timer.minutes(15))}")
    Output.info("  Process: #{format_interval(intervals[:process] || :timer.minutes(5))}")
    Output.info("  Export:  #{format_interval(intervals[:export] || :timer.minutes(10))}")
    Output.info("  Cleanup: #{format_interval(intervals[:cleanup] || :timer.hours(1))}")
    Output.info("")
    Output.info("Press Ctrl+C to stop")
    Output.info("")

    # Start the scheduler
    case Scheduler.start_link(
           intervals: intervals,
           export_config: export_config,
           auto_start: true
         ) do
      {:ok, _pid} ->
        receive do
          :stop -> :ok
        end

      {:error, {:already_started, _pid}} ->
        Scheduler.set_export_config(export_config)

        case Scheduler.start() do
          :ok -> :ok
          {:error, :already_running} -> :ok
        end

        receive do
          :stop -> :ok
        end

      {:error, reason} ->
        Output.error("Failed to start scheduler: #{inspect(reason)}")
    end
  end

  @doc """
  Shows the current scheduler status.
  """
  def status do
    case Process.whereis(Rss2Nostr.Scheduler) do
      nil ->
        Output.info("Scheduler is not running")

      _pid ->
        status = Scheduler.status()

        Output.info("Scheduler Status")
        Output.info("")

        if status.running do
          Output.success("Status: RUNNING")
        else
          Output.warning("Status: STOPPED")
        end

        Output.info("")
        Output.info("Intervals:")

        Enum.each(status.intervals, fn {task, interval} ->
          Output.info("  #{task}: #{interval}")
        end)

        Output.info("")
        Output.info("Task Status:")

        Enum.each(status.task_status, &show_task_status(&1, status.last_run))

        Output.info("")

        if status.export_configured do
          Output.success("Export: configured")
        else
          Output.warning("Export: not configured (no private key)")
        end
    end
  end

  @doc """
  Runs a single task manually.
  """
  def run_task(task_name) do
    task =
      case task_name do
        "import" ->
          :import

        "process" ->
          :process

        "export" ->
          :export

        "cleanup" ->
          :cleanup

        _ ->
          Output.error("Unknown task: #{task_name}")
          Output.info("Valid tasks: import, process, export, cleanup")
          nil
      end

    if task do
      Output.info("Running task: #{task}...")

      # Start scheduler if not running
      ensure_scheduler_started()

      case Scheduler.run_task(task) do
        {:ok, result} ->
          Output.success("Task completed!")
          Output.info("Result: #{inspect(result)}")

        {:error, reason} ->
          Output.error("Task failed: #{inspect(reason)}")
      end
    end
  end

  defp show_task_status({task, task_status}, last_run_map) do
    last_run =
      case last_run_map[task] do
        nil -> "never"
        dt -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
      end

    Output.info("  #{task}: #{task_status} (last run: #{last_run})")
  end

  defp ensure_scheduler_started do
    case Process.whereis(Rss2Nostr.Scheduler) do
      nil ->
        config = Application.get_env(:rss2nostr, Rss2Nostr.Scheduler, [])
        Scheduler.start_link(intervals: config[:intervals] || %{})

      _pid ->
        :ok
    end
  end

  defp get_private_key(nil) do
    case System.get_env("NOSTR_NSEC") do
      nil -> {:error, :no_key}
      nsec -> decode_nsec(nsec)
    end
  end

  defp get_private_key(nsec), do: decode_nsec(nsec)

  defp decode_nsec(nsec) do
    cond do
      String.starts_with?(nsec, "nsec") ->
        case NIP19.decode(nsec) do
          {:ok, :nsec, privkey_hex} ->
            {:ok, privkey_bin} = Keys.from_hex(privkey_hex)
            pubkey_bin = Keys.derive_public_key(privkey_bin)
            {:ok, privkey_bin, Keys.to_hex(pubkey_bin)}

          _ ->
            {:error, :invalid_nsec}
        end

      String.length(nsec) == 64 ->
        case Keys.from_hex(nsec) do
          {:ok, privkey_bin} ->
            pubkey_bin = Keys.derive_public_key(privkey_bin)
            {:ok, privkey_bin, Keys.to_hex(pubkey_bin)}

          _ ->
            {:error, :invalid_hex}
        end

      true ->
        {:error, :invalid_format}
    end
  end

  defp parse_relays(nil), do: nil

  defp parse_relays(relays) when is_binary(relays) do
    relays
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(String.starts_with?(&1, "wss://") or String.starts_with?(&1, "ws://")))
  end

  defp parse_relays(relays) when is_list(relays), do: relays

  defp describe_relay_target(relays, _audience) when is_list(relays) do
    Output.info("Relays: #{length(relays)} (explicit override)")
  end

  defp describe_relay_target(_relays, audience) when audience in [:test, :public] do
    Output.info("Relays: #{length(Relays.for(audience))} (#{audience} list)")
  end

  defp describe_relay_target(_relays, _audience) do
    Output.info("Relays: per source (draft, test, or public)")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_interval(ms) when ms < 60_000, do: "#{div(ms, 1000)} seconds"
  defp format_interval(ms) when ms < 3_600_000, do: "#{div(ms, 60_000)} minutes"
  defp format_interval(ms), do: "#{div(ms, 3_600_000)} hours"
end
