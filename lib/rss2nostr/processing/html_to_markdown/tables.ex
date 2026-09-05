defmodule Rss2Nostr.Processing.HtmlToMarkdown.Tables do
  @moduledoc false

  alias Rss2Nostr.Processing.HtmlToMarkdown.Dom

  @type cell :: {String.t(), pos_integer()}
  @type row :: [cell()]

  @spec process(list()) :: String.t()
  def process(children) do
    rows = children |> collect_rows() |> Enum.map(&row_cells/1)

    if Enum.empty?(rows) do
      ""
    else
      width = rows |> Enum.map(&row_width/1) |> Enum.max()
      {body, notes} = split_full_width_notes(rows, width)

      table =
        case Enum.map(body, &pad_row(&1, width)) do
          [header | rest] ->
            separator =
              "| " <> Enum.map_join(1..width, " | ", fn _ -> "---" end) <> " |"

            "\n\n#{header}\n#{separator}\n#{Enum.join(rest, "\n")}\n\n"

          [] ->
            "\n\n"
        end

      notes_md =
        Enum.map_join(notes, "\n\n", fn text ->
          if text == "", do: "", else: text
        end)

      case String.trim(notes_md) do
        "" -> table
        notes -> table <> notes <> "\n\n"
      end
    end
  end

  @spec collect_rows(term()) :: list()
  defp collect_rows(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &collect_rows/1)
  end

  defp collect_rows({"tr", _, _} = row), do: [row]

  defp collect_rows({tag, _, children}) when tag in ~w(thead tbody tfoot) do
    collect_rows(children)
  end

  defp collect_rows({_, _, children}) when is_list(children), do: collect_rows(children)
  defp collect_rows(_), do: []

  @spec row_cells(Floki.html_node()) :: row()
  defp row_cells({"tr", _, row_children}) do
    row_children
    |> Dom.find_all_elements(["td", "th"])
    |> Enum.map(fn {_, attrs, _} = cell ->
      {cell_text(cell), colspan(attrs)}
    end)
  end

  @spec colspan(list()) :: pos_integer()
  defp colspan(attrs) do
    case Dom.get_attr(attrs, "colspan", "1") |> to_string() |> Integer.parse() do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  @spec row_width(row()) :: pos_integer()
  defp row_width(cells), do: cells |> Enum.map(&elem(&1, 1)) |> Enum.sum() |> max(1)

  # GFM tables cannot span columns. A row that is one cell covering the
  # full width becomes a paragraph after the table instead of a short row.
  @spec split_full_width_notes([row()], pos_integer()) :: {[row()], [String.t()]}
  defp split_full_width_notes(rows, width) do
    {leading, trailing} = Enum.split_while(rows, &(not full_width_note?(&1, width)))
    {notes, rest} = Enum.split_while(trailing, &full_width_note?(&1, width))

    {body, more_notes} = split_full_width_notes_rest(rest, width)
    {leading ++ body, Enum.map(notes ++ more_notes, fn [{text, _}] -> text end)}
  end

  defp split_full_width_notes_rest([], _width), do: {[], []}

  defp split_full_width_notes_rest(rows, width) do
    {body, notes} = split_full_width_notes(rows, width)
    {body, notes}
  end

  @spec full_width_note?(row(), pos_integer()) :: boolean()
  defp full_width_note?([{text, span}], width)
       when is_binary(text) and text != "" and span >= width,
       do: true

  defp full_width_note?(_, _), do: false

  @spec pad_row(row(), pos_integer()) :: String.t()
  defp pad_row(cells, width) do
    texts = Enum.map(cells, &elem(&1, 0))
    used = row_width(cells)
    padded = texts ++ List.duplicate("", max(width - used, 0))
    "| #{Enum.join(padded, " | ")} |"
  end

  @spec cell_text(Floki.html_node()) :: String.t()
  defp cell_text({_, _, children}) do
    children
    |> flatten_cell()
    |> String.replace(~r/[ \t\n\r]+/, " ")
    |> String.trim()
    |> String.replace("|", "\\|")
  end

  @spec flatten_cell(term()) :: String.t()
  defp flatten_cell(nodes) when is_list(nodes), do: Enum.map_join(nodes, "", &flatten_cell/1)
  defp flatten_cell({"br", _, _}), do: " "
  defp flatten_cell({_, _, children}), do: flatten_cell(children)
  defp flatten_cell(text) when is_binary(text), do: text
  defp flatten_cell(_), do: ""
end
