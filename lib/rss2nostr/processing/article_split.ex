defmodule Rss2Nostr.Processing.ArticleSplit do
  @moduledoc """
  Splits long-form Markdown so each part's NIP-44 plaintext stays in range.

  Cut order: ATX `#` / `##` / `###` near the size limit, then a blank line,
  then any newline. Fenced code blocks are not used as cut points.
  """

  @lookback_min 8_000
  @lookback_ratio 0.2

  @doc """
  Splits `content` into parts where `measure.(part, 1-based-index)` is
  at most `max_size` (default: NIP-44 65535).

  `measure` must return the encoded inner-event JSON size in bytes.
  """
  @spec split(String.t(), (String.t(), pos_integer() -> non_neg_integer()), keyword()) :: [
          String.t()
        ]
  def split(content, measure, opts \\ [])
      when is_binary(content) and is_function(measure, 2) do
    max_size = Keyword.get(opts, :max_size, Rss2Nostr.Nostr.Event.max_draft_plaintext_size())

    case content |> take_parts(measure, max_size, 1, []) |> Enum.reverse() do
      [] -> [""]
      parts -> parts
    end
  end

  defp take_parts(remaining, measure, max_size, index, acc) do
    remaining = String.trim_leading(remaining)

    cond do
      remaining == "" ->
        acc

      fits?(remaining, measure, index, max_size) ->
        [remaining | acc]

      true ->
        cut = find_cut(remaining, measure, index, max_size)
        {part, rest} = split_at(remaining, cut)
        part = String.trim_trailing(part)

        if part == "" do
          {forced, rest} = force_take(remaining, measure, index, max_size)
          take_parts(rest, measure, max_size, index + 1, [forced | acc])
        else
          take_parts(rest, measure, max_size, index + 1, [part | acc])
        end
    end
  end

  defp find_cut(text, measure, index, max_size) do
    target = max_fitting_bytes(text, measure, index, max_size)

    cond do
      target <= 0 ->
        0

      target >= byte_size(text) ->
        byte_size(text)

      true ->
        window_start = max(1, target - lookback(target))

        preferred =
          text
          |> candidate_offsets()
          |> Enum.filter(fn {offset, _type} -> offset > window_start and offset <= target end)
          |> pick_cut()

        preferred || target
    end
  end

  defp pick_cut(candidates) do
    headings = for {offset, :heading} <- candidates, do: offset
    blanks = for {offset, :blank} <- candidates, do: offset
    List.last(headings) || List.last(blanks)
  end

  defp lookback(target) do
    max(@lookback_min, round(target * @lookback_ratio))
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

  defp fits?(chunk, measure, index, max_size) do
    measure.(chunk, index) <= max_size
  end

  defp max_fitting_bytes(text, measure, index, max_size) do
    total = byte_size(text)

    if fits?(text, measure, index, max_size) do
      total
    else
      binsearch_fit(text, measure, index, max_size, 0, total)
    end
  end

  defp binsearch_fit(_text, _measure, _index, _max_size, low, high) when low >= high do
    low
  end

  defp binsearch_fit(text, measure, index, max_size, low, high) do
    mid = utf8_floor(text, div(low + high + 1, 2))

    cond do
      mid <= low ->
        low

      fits?(binary_part(text, 0, mid), measure, index, max_size) ->
        binsearch_fit(text, measure, index, max_size, mid, high)

      true ->
        binsearch_fit(text, measure, index, max_size, low, mid - 1)
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

  defp split_at(text, n) when n <= 0, do: {"", text}
  defp split_at(text, n) when n >= byte_size(text), do: {text, ""}
  defp split_at(text, n), do: {binary_part(text, 0, n), binary_part(text, n, byte_size(text) - n)}

  defp force_take(text, measure, index, max_size) do
    cut = max(max_fitting_bytes(text, measure, index, max_size), next_char_size(text))
    {part, rest} = split_at(text, cut)
    {String.trim_trailing(part), rest}
  end

  defp next_char_size(""), do: 0

  defp next_char_size(text) do
    case String.next_codepoint(text) do
      {char, _} -> byte_size(char)
      nil -> 0
    end
  end
end
