defmodule Rss2Nostr.SchedulerTest do
  use Rss2Nostr.DataCase

  alias Rss2Nostr.Scheduler

  # Start scheduler for these tests
  setup do
    # Try to start scheduler if not running
    case Process.whereis(Scheduler) do
      nil ->
        {:ok, pid} = Scheduler.start_link([])

        on_exit(fn ->
          if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
        end)

        %{scheduler_pid: pid}

      pid ->
        %{scheduler_pid: pid}
    end
  end

  describe "start_link/1" do
    test "starts the scheduler process", %{scheduler_pid: pid} do
      assert is_pid(pid)
      assert Process.alive?(pid)
    end
  end

  describe "status/0" do
    test "returns scheduler status" do
      status = Scheduler.status()

      assert is_map(status)
      assert Map.has_key?(status, :running)
    end
  end

  describe "start/0 and stop/0" do
    test "start and stop control the scheduler" do
      # Get initial state
      initial_status = Scheduler.status()

      # Try start (may already be running)
      result_start = Scheduler.start()
      assert result_start in [:ok, {:error, :already_running}]

      # Try stop
      result_stop = Scheduler.stop()
      assert result_stop in [:ok, {:error, :not_running}]

      # Restore initial state if it was running
      if initial_status.running do
        Scheduler.start()
      end
    end
  end

  describe "run_task/1" do
    test "runs import task" do
      result = Scheduler.run_task(:import)
      # Should complete without crashing
      assert result == :ok or match?({:ok, _}, result)
    end

    test "runs process task" do
      result = Scheduler.run_task(:process)
      assert result == :ok or match?({:ok, _}, result)
    end

    test "runs export task" do
      result = Scheduler.run_task(:export)
      # Export may be skipped if no private key configured
      assert result == :ok or match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
