defmodule Rss2Nostr.Nostr.Publisher.Gap do
  @moduledoc false

  @spec publish_gap_ms() :: non_neg_integer()
  def publish_gap_ms do
    Application.get_env(:rss2nostr, :nostr, [])
    |> Keyword.get(:publish_gap_ms, 10_000)
    |> max(0)
  end

  @spec each_with_gap(list(), (term() -> term())) :: list()
  def each_with_gap(items, fun) when is_list(items) and is_function(fun, 1) do
    gap = publish_gap_ms()

    items
    |> Enum.with_index()
    |> Enum.map(fn {item, index} ->
      if index > 0 and gap > 0, do: Process.sleep(gap)
      fun.(item)
    end)
  end
end
