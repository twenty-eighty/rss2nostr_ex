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

  @type measure :: (String.t(), pos_integer() -> non_neg_integer())
  @type cut_candidate :: {pos_integer(), :heading | :blank}
  @type fence_range :: {pos_integer(), pos_integer()}
  @type line_entry :: {pos_integer(), String.t(), boolean()}

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

  @spec equal_parts(String.t(), measure(), non_neg_integer(), [Footnotes.footnote()]) :: [String.t()]
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

  @spec min_part_count(String.t(), measure(), non_neg_integer(), [Footnotes.footnote()]) :: pos_integer()
  defp min_part_count(body, measure, max_size, footnotes) do
    size = measure.(attach(body, footnotes, last: true), 1)
    max(2, div(size + max_size - 1, max_size))
  end

  @spec try_equal_cuts(String.t(), pos_integer(), measure(), non_neg_integer(), [Footnotes.footnote()]) :: {:ok, [String.t()]} | :error
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

  @spec equal_cut_offsets(String.t(), pos_integer()) :: [pos_integer()]
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

  @spec choose_cut(String.t(), [cut_candidate()], [fence_range()], pos_integer(), pos_integer(), pos_integer(), pos_integer()) :: pos_integer()
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

  @spec closest([pos_integer()], pos_integer()) :: pos_integer() | nil
  defp closest([], _target), do: nil

  defp closest(offsets, target) do
    Enum.min_by(offsets, fn offset ->
      {abs(offset - target), if(offset <= target, do: 0, else: 1)}
    end)
  end

  @spec snap_out_of_fence(pos_integer(), [fence_range()], pos_integer(), pos_integer()) :: pos_integer()
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

  @spec fence_ranges(String.t()) :: [fence_range()]
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

  @spec valid_cuts?([pos_integer()], non_neg_integer()) :: boolean()
  defp valid_cuts?(cuts, total) do
    cuts != [] and
      Enum.all?(cuts, &(&1 > 0 and &1 < total)) and
      cuts == Enum.sort(Enum.uniq(cuts))
  end

  @spec chunks_at(String.t(), [pos_integer()]) :: [String.t()]
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

  @spec attach_chunks([String.t()], [Footnotes.footnote()]) :: [String.t()]
  @spec attach(String.t(), [Footnotes.footnote()], keyword()) :: String.t()
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

  @spec parts_fit?([String.t()], measure(), non_neg_integer()) :: boolean()
  defp parts_fit?(parts, measure, max_size) do
    parts
    |> Enum.with_index(1)
    |> Enum.all?(fn {part, index} -> measure.(part, index) <= max_size end)
  end

  @spec greedy_parts(String.t(), measure(), non_neg_integer(), [Footnotes.footnote()]) :: [String.t()]
  defp greedy_parts(body, measure, max_size, footnotes) do
    case take_parts(body, measure, max_size, 1, [], footnotes) |> Enum.reverse() do
      [] -> [""]
      parts -> parts
    end
  end

  @spec take_parts(String.t(), measure(), non_neg_integer(), pos_integer(), [String.t()], [Footnotes.footnote()]) :: [String.t()]
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

  @spec candidate_offsets(String.t()) :: [cut_candidate()]
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

  @spec line_scan(String.t()) :: [line_entry()]
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

  @spec fence_marker?(String.t()) :: boolean()
  defp fence_marker?(line), do: String.starts_with?(String.trim_leading(line), "```")

  @spec heading?(String.t()) :: boolean()
  defp heading?(line), do: String.match?(line, ~r/^\#{1,3} \S/)

  @spec fits?(String.t(), measure(), pos_integer(), non_neg_integer(), [Footnotes.footnote()], keyword()) :: boolean()
  defp fits?(chunk, measure, index, max_size, footnotes, attach_opts \\ []) do
    measure.(attach(chunk, footnotes, attach_opts), index) <= max_size
  end

  @spec max_fitting_bytes(String.t(), measure(), pos_integer(), non_neg_integer(), [Footnotes.footnote()]) :: non_neg_integer()
  defp max_fitting_bytes(text, measure, index, max_size, footnotes) do
    total = byte_size(text)

    if fits?(text, measure, index, max_size, footnotes) do
      total
    else
      binsearch_fit(text, measure, index, max_size, footnotes, 0, total)
    end
  end

  @spec binsearch_fit(String.t(), measure(), pos_integer(), non_neg_integer(), [Footnotes.footnote()], non_neg_integer(), non_neg_integer()) :: non_neg_integer()
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

  @spec utf8_floor(String.t(), non_neg_integer()) :: non_neg_integer()
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

  @spec clamp(integer(), integer(), integer()) :: integer()
  defp clamp(_n, lo, hi) when hi < lo, do: lo
  defp clamp(n, lo, _hi) when n < lo, do: lo
  defp clamp(n, _lo, hi) when n > hi, do: hi
  defp clamp(n, _lo, _hi), do: n

  @spec split_at(String.t(), non_neg_integer()) :: {String.t(), String.t()}
  defp split_at(text, n) when n <= 0, do: {"", text}
  defp split_at(text, n) when n >= byte_size(text), do: {text, ""}
  defp split_at(text, n), do: {binary_part(text, 0, n), binary_part(text, n, byte_size(text) - n)}

  @spec force_take(String.t(), measure(), pos_integer(), non_neg_integer(), [Footnotes.footnote()]) :: {String.t(), String.t()}
  defp force_take(text, measure, index, max_size, footnotes) do
    cut = max(max_fitting_bytes(text, measure, index, max_size, footnotes), next_char_size(text))
    {part, rest} = split_at(text, cut)
    {attach(String.trim_trailing(part), footnotes), rest}
  end

  defp attach(chunk, footnotes, opts \\ []) do
    Footnotes.attach(chunk, footnotes, opts)
  end

  @spec cited_in_parts([String.t()]) :: [String.t()]
  defp cited_in_parts(parts) do
    Enum.flat_map(parts, &Footnotes.cited_ids/1)
  end

  @spec next_char_size(String.t()) :: non_neg_integer()
  defp next_char_size(""), do: 0

  defp next_char_size(text) do
    case String.next_codepoint(text) do
      {char, _} -> byte_size(char)
      nil -> 0
    end
  end
end
