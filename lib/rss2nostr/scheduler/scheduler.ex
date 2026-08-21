defmodule Rss2Nostr.Scheduler do
  @moduledoc """
  Manages scheduled tasks for automatic RSS feed processing.

  Tasks:
  - import: Fetch new articles from RSS/Atom feeds
  - process: Convert HTML to Markdown
  - export: Publish processed posts to Nostr
  - cleanup: Delete app-signed drafts after a kind 30023 exists

  The scheduler runs as a GenServer and executes tasks at configurable intervals.
  """

  use GenServer
  require Logger

  alias Rss2Nostr.Scheduler.Tasks

  @tasks [:import, :process, :export, :cleanup]

  @default_intervals %{
    import: :timer.minutes(15),
    process: :timer.minutes(5),
    export: :timer.minutes(10),
    cleanup: :timer.hours(1)
  }

  defstruct [
    :intervals,
    :timers,
    :export_config,
    running: false,
    task_status: %{},
    last_run: %{},
    last_result: %{}
  ]

  @type t :: %__MODULE__{}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the scheduler.

  Options:
  - :intervals - Map of task intervals in milliseconds
    - :import - Feed import interval (default: 15 minutes)
    - :process - Processing interval (default: 5 minutes)
    - :export - Export interval (default: 10 minutes)
    - :cleanup - Draft cleanup interval (default: 1 hour)
  - :export_config - Configuration for export task
    - :private_key - Nostr private key (required for export)
    - :relays - Explicit relay URLs (optional; otherwise per-source test/public)
    - :audience - `:test` or `:public` (optional; forces one list for every post)
    - :upload_images - Whether to upload images
  - :auto_start - Start scheduling immediately (default: false)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts all scheduled tasks.
  """
  @spec start() :: :ok | {:error, :already_running}
  def start do
    GenServer.call(__MODULE__, :start)
  end

  @doc """
  Stops all scheduled tasks.
  """
  @spec stop() :: :ok
  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Returns the current scheduler status.
  """
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Manually triggers a specific task.
  """
  @spec run_task(atom() | String.t()) :: {:ok, map()} | {:error, any()}
  def run_task(task) when task in @tasks do
    GenServer.call(__MODULE__, {:run_task, task}, :timer.minutes(5))
  end

  def run_task(task) when task in ["import", "process", "export", "cleanup"] do
    run_task(String.to_existing_atom(task))
  end

  def run_task(_), do: {:error, :invalid_task}

  @doc """
  Updates the interval for a specific task.
  """
  @spec set_interval(atom(), pos_integer()) :: :ok
  def set_interval(task, interval_ms) when task in @tasks do
    GenServer.call(__MODULE__, {:set_interval, task, interval_ms})
  end

  @doc """
  Updates the export configuration.
  """
  @spec set_export_config(map()) :: :ok
  def set_export_config(config) do
    GenServer.call(__MODULE__, {:set_export_config, config})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    config_intervals = Application.get_env(:rss2nostr, __MODULE__, [])[:intervals] || %{}

    intervals =
      @default_intervals
      |> Map.merge(config_intervals)
      |> Map.merge(Keyword.get(opts, :intervals, %{}))

    export_config = Keyword.get(opts, :export_config, %{})
    auto_start = Keyword.get(opts, :auto_start, false)

    state = %__MODULE__{
      intervals: intervals,
      timers: %{},
      export_config: export_config,
      task_status: %{import: :idle, process: :idle, export: :idle, cleanup: :idle},
      last_run: %{},
      last_result: %{}
    }

    if auto_start do
      {:ok, state, {:continue, :start_scheduling}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:start_scheduling, state) do
    {:noreply, do_start(state)}
  end

  @impl true
  def handle_call(:start, _from, state) do
    if state.running do
      {:reply, {:error, :already_running}, state}
    else
      new_state = do_start(state)
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    new_state = do_stop(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      running: state.running,
      intervals: format_intervals(state.intervals),
      task_status: state.task_status,
      last_run: state.last_run,
      last_result: state.last_result,
      export_configured: state.export_config[:private_key] != nil
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:run_task, task}, _from, state) do
    {result, new_state} = execute_task(task, state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:set_interval, task, interval_ms}, _from, state) do
    intervals = Map.put(state.intervals, task, interval_ms)

    # Reschedule if running
    new_state =
      if state.running do
        cancel_timer(state.timers[task])
        timer = schedule_task(task, interval_ms)
        %{state | intervals: intervals, timers: Map.put(state.timers, task, timer)}
      else
        %{state | intervals: intervals}
      end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:set_export_config, config}, _from, state) do
    export_config = Map.merge(state.export_config, config)
    {:reply, :ok, %{state | export_config: export_config}}
  end

  @impl true
  def handle_info({:execute, task}, state) do
    {_result, new_state} = execute_task(task, state)

    # Reschedule
    timer = schedule_task(task, state.intervals[task])
    new_state = %{new_state | timers: Map.put(new_state.timers, task, timer)}

    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_start(state) do
    Logger.info("Starting scheduler...")

    timers =
      Enum.reduce(state.intervals, %{}, fn {task, interval}, acc ->
        # Run immediately, then schedule recurring
        send(self(), {:execute, task})
        timer = schedule_task(task, interval)
        Map.put(acc, task, timer)
      end)

    %{state | running: true, timers: timers}
  end

  defp do_stop(state) do
    Logger.info("Stopping scheduler...")

    Enum.each(state.timers, fn {_task, timer} ->
      cancel_timer(timer)
    end)

    %{state | running: false, timers: %{}}
  end

  defp schedule_task(task, interval) do
    Process.send_after(self(), {:execute, task}, interval)
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    Process.cancel_timer(timer)
  end

  defp execute_task(task, state) do
    Logger.info("Executing scheduled task: #{task}")
    state = %{state | task_status: Map.put(state.task_status, task, :running)}

    result =
      try do
        case task do
          :import -> Tasks.run_import()
          :process -> Tasks.run_process()
          :export -> Tasks.run_export(state.export_config)
          :cleanup -> Tasks.run_cleanup()
        end
      rescue
        e ->
          Logger.error("Task #{task} failed with error: #{inspect(e)}")
          {:error, e}
      end

    status = if match?({:ok, _}, result), do: :completed, else: :failed

    state = %{
      state
      | task_status: Map.put(state.task_status, task, status),
        last_run: Map.put(state.last_run, task, DateTime.utc_now()),
        last_result: Map.put(state.last_result, task, summarize_result(result))
    }

    {result, state}
  end

  defp summarize_result({:ok, stats}) when is_map(stats), do: stats
  defp summarize_result({:error, reason}), do: %{error: inspect(reason)}
  defp summarize_result(other), do: %{result: inspect(other)}

  defp format_intervals(intervals) do
    Enum.map(intervals, fn {task, ms} ->
      {task, format_duration(ms)}
    end)
    |> Map.new()
  end

  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{div(ms, 1000)}s"
  defp format_duration(ms) when ms < 3_600_000, do: "#{div(ms, 60_000)}m"
  defp format_duration(ms), do: "#{div(ms, 3_600_000)}h"
end
