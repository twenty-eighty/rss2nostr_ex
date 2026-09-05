defmodule Rss2Nostr.Processing.Sites.WordFootnotes do
  @moduledoc """
  Converts Word-style footnote / endnote anchors to Markdown footnotes.

  Handles `#_ftnN` / `#_ednN` references and `#_ftnrefN` / `#_ednrefN`
  definitions (also without the leading underscore, and absolute URLs that
  only keep the fragment). Visible markers may be Arabic (`[43]`) or Roman
  (`[i]`, `[xiii]`).

  When Word restarts numbering and reuses the same fragment ids, references
  and definitions are paired by occurrence order and renumbered uniquely.
  """

  alias Rss2Nostr.Processing.HtmlToMarkdown

  @spec applies?(map()) :: boolean()
  def applies?(_opts), do: true

  @spec preprocess(String.t()) :: String.t()
  def preprocess(html) when html in [nil, ""], do: html

  def preprocess(html) when is_binary(html) do
    html = HtmlToMarkdown.preserve_inline_spaces(html)

    case Floki.parse_document(html) do
      {:ok, doc} ->
        events = collect_events(doc)

        if events == [] do
          html
        else
          ids = assign_ids(events)
          {rewritten, _} = rewrite_nodes(doc, %{events: events, ids: ids, index: 0})
          Floki.raw_html(rewritten)
        end

      _ ->
        html
    end
  rescue
    _ -> html
  end

  defp collect_events(nodes), do: nodes |> do_collect([]) |> Enum.reverse()

  defp do_collect(nodes, acc) when is_list(nodes), do: Enum.reduce(nodes, acc, &do_collect/2)

  defp do_collect({"a", attrs, children}, acc) do
    case classify_link(attrs, children) do
      {kind, frag, visible} -> [{kind, frag, visible} | do_collect(children, acc)]
      nil -> do_collect(children, acc)
    end
  end

  defp do_collect({_, _, children}, acc), do: do_collect(children, acc)
  defp do_collect(_, acc), do: acc

  defp assign_ids(events) do
    preferred =
      Enum.map(events, fn {kind, frag, visible} ->
        {kind, frag, preferred_id(visible, frag)}
      end)

    def_ids = for {:definition, _, id} <- preferred, do: id

    if length(def_ids) == map_size(Map.new(def_ids, &{&1, true})) do
      Enum.map(preferred, fn {_kind, _frag, id} -> id end)
    else
      remap_ids(events)
    end
  end

  defp remap_ids(events) do
    # Assign unique Markdown ids in reference (reading) order, pairing the
    # nth reference of a fragment with the nth definition of that fragment.
    {pair_ids, _next} =
      Enum.reduce(events, {%{}, 1}, fn
        {:reference, frag, _}, {pairs, next} ->
          {Map.update(pairs, frag, [next], &(&1 ++ [next])), next + 1}

        _, acc ->
          acc
      end)

    # Orphan definitions (more defs than refs) get trailing ids.
    {pair_ids, _next} =
      events
      |> Enum.map(fn {_kind, frag, _} -> frag end)
      |> Enum.uniq()
      |> Enum.reduce({pair_ids, next_after(pair_ids)}, fn frag, {pairs, next} ->
        defs_needed = count_kind(events, :definition, frag)
        refs_have = length(Map.get(pairs, frag, []))

        if defs_needed > refs_have do
          extras = Enum.to_list(next..(next + defs_needed - refs_have - 1))
          {Map.update(pairs, frag, extras, &(&1 ++ extras)), next + length(extras)}
        else
          {pairs, next}
        end
      end)

    {_occ, ids} =
      Enum.reduce(events, {%{}, []}, fn {kind, frag, _}, {occ, ids} ->
        n = Map.get(occ, {kind, frag}, 0)
        id = pair_ids |> Map.get(frag, []) |> Enum.at(n) |> to_string_id()
        {Map.put(occ, {kind, frag}, n + 1), [id | ids]}
      end)

    Enum.reverse(ids)
  end

  defp next_after(pair_ids) do
    pair_ids
    |> Map.values()
    |> List.flatten()
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp count_kind(events, kind, frag) do
    Enum.count(events, fn {k, f, _} -> k == kind and f == frag end)
  end

  defp to_string_id(id) when is_integer(id), do: Integer.to_string(id)
  defp to_string_id(id) when is_binary(id), do: id
  defp to_string_id(_), do: "0"

  defp preferred_id(visible, frag) do
    cond do
      is_binary(visible) and Regex.match?(~r/^\d+$/, visible) ->
        visible

      is_binary(visible) and roman_to_int(visible) > 0 ->
        visible |> roman_to_int() |> Integer.to_string()

      true ->
        frag
    end
  end

  defp rewrite_nodes(nodes, state) when is_list(nodes) do
    Enum.map_reduce(nodes, state, &rewrite_node/2)
  end

  defp rewrite_node({"a", attrs, children}, state) do
    case classify_link(attrs, children) do
      {_kind, _frag, _visible} ->
        id = Enum.at(state.ids, state.index)
        text = footnote_text(Enum.at(state.events, state.index), id)
        {text, %{state | index: state.index + 1}}

      nil ->
        {children, state} = rewrite_nodes(children, state)
        {{"a", attrs, children}, state}
    end
  end

  defp rewrite_node({tag, attrs, children}, state) do
    {children, state} = rewrite_nodes(children, state)
    {{tag, attrs, children}, state}
  end

  defp rewrite_node(other, state), do: {other, state}

  defp classify_link(attrs, children) do
    href = attr(attrs, "href")

    case footnote_fragment(uri_fragment(href)) do
      {kind, frag} -> {kind, frag, visible_footnote_id(children)}
      nil -> nil
    end
  end

  defp uri_fragment(href) when is_binary(href) do
    case URI.parse(href) do
      %URI{fragment: frag} when is_binary(frag) and frag != "" -> frag
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp uri_fragment(_), do: nil

  defp footnote_fragment(frag) when is_binary(frag) do
    cond do
      match = Regex.run(~r/^_?(?:ftnref|fnref|footnoteref|ednref|endnoteref)(\d+)$/i, frag) ->
        {:definition, Enum.at(match, 1)}

      match = Regex.run(~r/^_?(?:ftn|fn|edn|endnote)(\d+)$/i, frag) ->
        {:reference, Enum.at(match, 1)}

      true ->
        nil
    end
  end

  defp footnote_fragment(_), do: nil

  defp visible_footnote_id(children) do
    text = {"a", [], List.wrap(children)} |> Floki.text() |> String.trim()

    cond do
      match = Regex.run(~r/^\[?(\d+)\]?$/, text) ->
        Enum.at(match, 1)

      match = Regex.run(~r/^\[?([ivxlcdm]+)\]?$/i, text) ->
        Enum.at(match, 1) |> String.downcase()

      true ->
        nil
    end
  end

  defp footnote_text({:reference, _, _}, id), do: "[^#{id}]"
  defp footnote_text({:definition, _, _}, id), do: "[^#{id}]: "

  defp attr(attrs, name, default \\ nil) do
    Enum.find_value(attrs, default, fn
      {^name, value} -> value
      _ -> nil
    end)
  end

  defp roman_to_int(roman) when is_binary(roman) do
    roman = String.downcase(roman)

    if roman == "" or not Regex.match?(~r/^[ivxlcdm]+$/, roman) do
      0
    else
      values = %{"i" => 1, "v" => 5, "x" => 10, "l" => 50, "c" => 100, "d" => 500, "m" => 1000}

      roman
      |> String.graphemes()
      |> Enum.map(&Map.fetch!(values, &1))
      |> Enum.chunk_every(2, 1, [0])
      |> Enum.reduce(0, fn
        [a, b], acc when a < b -> acc - a
        [a, _], acc -> acc + a
      end)
    end
  end
end
