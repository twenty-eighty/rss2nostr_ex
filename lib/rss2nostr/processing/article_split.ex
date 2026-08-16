defmodule Rss2Nostr.Processing.ArticleSplit do
  @moduledoc """
  Splits long-form Markdown so each published event stays in range.

  When a split is required, parts are cut at equal fractions of the body
  (ATX `#` / `##` / `###` near the target, then a blank line, then the
  target offset). Fenced code blocks are not used as cut points.

  Footnote definitions are taken out before cutting. Each part gets the
  notes it cites; leftover notes stay on the last part.
  """

  alias Rss2Nostr.Processing.Footnotes

  @lookback_min 8_000
  @lookback_ratio 0.2
  @max_parts 200

  @doc """
  Splits `content` into parts where `measure.(part, 1-based-index)` is
  at most `max_size` (default: 65535).

  `measure` must return the size that will be published (the wrap
  `["EVENT", …]` for drafts, the signed event for articles).
  """
  @spec split(String.t(), (String.t(), pos_integer() -> non_neg_integer()), keyword()) :: [
          String.t()
        ]
  def split(content, measure, opts \\ [])
      when is_binary(content) and is_function(measure, 2) do
    max_size = Keyword.get(opts, :max_size, Rss2Nostr.Nostr.Event.max_draft_plaintext_size())
    {body, footnotes} = Footnotes.extract(content)
    body = String.trim_leading(body)

    cond do
      body == "" ->
        [""]

      fits?(body, measure, 1, max_size, footnotes, last: true) ->
        [attach(body, footnotes, last: true)]

      true ->
        equal_parts(body, measure, max_size, footnotes)
    end
  end

  defp equal_parts(body, measure, max_size, footnotes) do
    min_n = min_part_count(body, measure, max_size, footnotes)
    max_n = min(@max_parts, max(min_n, byte_size(body)))

    Enum.find_value(min_n..max_n, fn n ->
      case try_equal_cuts(body, n, measure, max_size, footnotes) do
        {:ok, parts} -> parts
        :error -> nil
      end
    end) || greedy_parts(body, measure, max_size, footnotes)
  end

  defp min_part_count(body, measure, max_size, footnotes) do
    size = measure.(attach(body, footnotes, last: true), 1)
    max(2, div(size + max_size - 1, max_size))
  end

  defp try_equal_cuts(body, n, measure, max_size, footnotes) do
    cuts = equal_cut_offsets(body, n)

    if valid_cuts?(cuts, byte_size(body)) do
      parts = body |> chunks_at(cuts) |> attach_chunks(footnotes)

      if parts_fit?(parts, measure, max_size) do
        {:ok, parts}
      else
        :error
      end
    else
      :error
    end
  end

  defp equal_cut_offsets(body, n) do
    total = byte_size(body)
    part = max(div(total, n), 1)
    window = max(@lookback_min, round(part * @lookback_ratio))
    candidates = candidate_offsets(body)
    fences = fence_ranges(body)

    {cuts, _} =
      Enum.map_reduce(1..(n - 1)//1, 0, fn i, prev ->
        target = utf8_floor(body, round(i * total / n))
        earliest = prev + 1
        latest = max(earliest, total - (n - i))
        cut = choose_cut(body, candidates, fences, target, window, earliest, latest)
        {cut, cut}
      end)

    cuts
  end

  defp choose_cut(body, candidates, fences, target, window, earliest, latest) do
    target =
      target
      |> clamp(earliest, latest)
      |> then(&snap_out_of_fence(&1, fences, earliest, latest))
      |> then(&utf8_floor(body, &1))
      |> clamp(earliest, latest)

    lo = max(earliest, target - window)
    hi = min(latest, target + window)

    nearby =
      Enum.filter(candidates, fn {offset, _type} ->
        offset >= lo and offset <= hi
      end)

    headings = for {offset, :heading} <- nearby, do: offset
    blanks = for {offset, :blank} <- nearby, do: offset

    closest(headings, target) || closest(blanks, target) || target
  end

  defp closest([], _target), do: nil

  defp closest(offsets, target) do
    Enum.min_by(offsets, fn offset ->
      {abs(offset - target), if(offset <= target, do: 0, else: 1)}
    end)
  end

  defp snap_out_of_fence(target, fences, earliest, latest) do
    case Enum.find(fences, fn {start, stop} -> target >= start and target < stop end) do
      nil ->
        target

      {start, stop} ->
        cond do
          start >= earliest and (stop > latest or abs(target - start) <= abs(target - stop)) ->
            start

          stop <= latest ->
            stop

          start >= earliest ->
            start

          true ->
            target
        end
    end
  end

  defp fence_ranges(text) do
    {ranges, open} =
      text
      |> line_scan()
      |> Enum.reduce({[], nil}, fn {offset, line, in_fence}, {ranges, start} ->
        cond do
          fence_marker?(line) and not in_fence ->
            {ranges, offset}

          fence_marker?(line) and in_fence ->
            {[{start, offset + byte_size(line) + 1} | ranges], nil}

          true ->
            {ranges, start}
        end
      end)

    ranges =
      if is_integer(open) do
        [{open, byte_size(text)} | ranges]
      else
        ranges
      end

    Enum.reverse(ranges)
  end

  defp valid_cuts?(cuts, total) do
    cuts != [] and
      Enum.all?(cuts, &(&1 > 0 and &1 < total)) and
      cuts == Enum.sort(Enum.uniq(cuts))
  end

  defp chunks_at(text, cuts) do
    {chunks, last_offset} =
      Enum.map_reduce(cuts, 0, fn cut, prev ->
        {part, _} = split_at(text, cut)
        chunk = part |> binary_part(prev, cut - prev) |> String.trim_trailing()
        {chunk, cut}
      end)

    rest =
      text |> binary_part(last_offset, byte_size(text) - last_offset) |> String.trim_leading()

    chunks ++ [rest]
  end

  defp attach_chunks(chunks, footnotes) do
    total = length(chunks)

    {parts, _} =
      Enum.map_reduce(Enum.with_index(chunks, 1), [], fn {chunk, index}, cited ->
        part =
          attach(chunk, footnotes,
            last: index == total,
            already_cited: cited
          )

        {part, cited ++ Footnotes.cited_ids(chunk)}
      end)

    parts
  end

  defp parts_fit?(parts, measure, max_size) do
    parts
    |> Enum.with_index(1)
    |> Enum.all?(fn {part, index} -> measure.(part, index) <= max_size end)
  end

  defp greedy_parts(body, measure, max_size, footnotes) do
    case take_parts(body, measure, max_size, 1, [], footnotes) |> Enum.reverse() do
      [] -> [""]
      parts -> parts
    end
  end

  defp take_parts(remaining, measure, max_size, index, acc, footnotes) do
    remaining = String.trim_leading(remaining)
    already_cited = cited_in_parts(acc)

    cond do
      remaining == "" ->
        acc

      fits?(remaining, measure, index, max_size, footnotes,
        last: true,
        already_cited: already_cited
      ) ->
        [attach(remaining, footnotes, last: true, already_cited: already_cited) | acc]

      true ->
        cut = max_fitting_bytes(remaining, measure, index, max_size, footnotes)
        {part, rest} = split_at(remaining, cut)
        part = String.trim_trailing(part)

        if part == "" do
          {forced, rest} = force_take(remaining, measure, index, max_size, footnotes)
          take_parts(rest, measure, max_size, index + 1, [forced | acc], footnotes)
        else
          take_parts(
            rest,
            measure,
            max_size,
            index + 1,
            [attach(part, footnotes) | acc],
            footnotes
          )
        end
    end
  end

  defp candidate_offsets(text) do
    text
    |> line_scan()
    |> Enum.flat_map(fn {offset, line, in_fence} ->
      cond do
        in_fence or offset == 0 ->
          []

        heading?(line) ->
          [{offset, :heading}]

        line == "" ->
          [{offset, :blank}]

        true ->
          []
      end
    end)
  end

  defp line_scan(text) do
    {lines, _fence, _offset} =
      text
      |> String.split("\n", trim: false)
      |> Enum.reduce({[], false, 0}, fn line, {acc, fence, offset} ->
        in_fence = fence
        next_fence = if fence_marker?(line), do: not fence, else: fence
        next_offset = offset + byte_size(line) + 1
        {[{offset, line, in_fence} | acc], next_fence, next_offset}
      end)

    Enum.reverse(lines)
  end

  defp fence_marker?(line), do: String.starts_with?(String.trim_leading(line), "```")

  defp heading?(line), do: String.match?(line, ~r/^\#{1,3} \S/)

  defp fits?(chunk, measure, index, max_size, footnotes, attach_opts \\ []) do
    measure.(attach(chunk, footnotes, attach_opts), index) <= max_size
  end

  defp max_fitting_bytes(text, measure, index, max_size, footnotes) do
    total = byte_size(text)

    if fits?(text, measure, index, max_size, footnotes) do
      total
    else
      binsearch_fit(text, measure, index, max_size, footnotes, 0, total)
    end
  end

  defp binsearch_fit(_text, _measure, _index, _max_size, _footnotes, low, high)
       when low >= high do
    low
  end

  defp binsearch_fit(text, measure, index, max_size, footnotes, low, high) do
    mid = utf8_floor(text, div(low + high + 1, 2))

    cond do
      mid <= low ->
        low

      fits?(binary_part(text, 0, mid), measure, index, max_size, footnotes) ->
        binsearch_fit(text, measure, index, max_size, footnotes, mid, high)

      true ->
        binsearch_fit(text, measure, index, max_size, footnotes, low, mid - 1)
    end
  end

  defp utf8_floor(_text, n) when n <= 0, do: 0
  defp utf8_floor(text, n) when n >= byte_size(text), do: byte_size(text)

  defp utf8_floor(text, n) do
    prefix = binary_part(text, 0, n)

    if String.valid?(prefix) do
      n
    else
      utf8_floor(text, n - 1)
    end
  end

  defp clamp(_n, lo, hi) when hi < lo, do: lo
  defp clamp(n, lo, _hi) when n < lo, do: lo
  defp clamp(n, _lo, hi) when n > hi, do: hi
  defp clamp(n, _lo, _hi), do: n

  defp split_at(text, n) when n <= 0, do: {"", text}
  defp split_at(text, n) when n >= byte_size(text), do: {text, ""}
  defp split_at(text, n), do: {binary_part(text, 0, n), binary_part(text, n, byte_size(text) - n)}

  defp force_take(text, measure, index, max_size, footnotes) do
    cut = max(max_fitting_bytes(text, measure, index, max_size, footnotes), next_char_size(text))
    {part, rest} = split_at(text, cut)
    {attach(String.trim_trailing(part), footnotes), rest}
  end

  defp attach(chunk, footnotes, opts \\ []) do
    Footnotes.attach(chunk, footnotes, opts)
  end

  defp cited_in_parts(parts) do
    Enum.flat_map(parts, &Footnotes.cited_ids/1)
  end

  defp next_char_size(""), do: 0

  defp next_char_size(text) do
    case String.next_codepoint(text) do
      {char, _} -> byte_size(char)
      nil -> 0
    end
  end
end
