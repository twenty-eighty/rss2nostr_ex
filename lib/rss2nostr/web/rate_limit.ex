defmodule Rss2Nostr.Web.RateLimit do
  @moduledoc false

  @table :rss2nostr_rate_limit

  @spec setup() :: :ok
  def setup do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Returns `true` when `bucket` is under `limit` hits in the rolling `window_ms`.
  """
  @spec allow?(term(), pos_integer(), pos_integer()) :: boolean()
  def allow?(bucket, limit, window_ms)
      when is_integer(limit) and limit > 0 and is_integer(window_ms) and window_ms > 0 do
    setup()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, bucket) do
      [{^bucket, count, started_at}] when now - started_at < window_ms ->
        if count < limit do
          :ets.insert(@table, {bucket, count + 1, started_at})
          true
        else
          false
        end

      _ ->
        :ets.insert(@table, {bucket, 1, now})
        true
    end
  end
end
