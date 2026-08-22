defmodule Rss2Nostr.Processing.HtmlToMarkdown.Tables do
  @moduledoc false

  alias Rss2Nostr.Processing.HtmlToMarkdown.Dom

  @spec process(list()) :: String.t()
  def process(children) do
    rows = Dom.find_all_elements(children, "tr")

    if Enum.empty?(rows) do
      ""
    else
      table_rows =
        rows
        |> Enum.map(fn {"tr", _, row_children} ->
          cells = Dom.find_all_elements(row_children, ["td", "th"])

          cells
          |> Enum.map_join(" | ", fn {_, _, cell_children} ->
            Floki.text(cell_children) |> String.trim()
          end)
          |> then(&"| #{&1} |")
        end)

      case table_rows do
        [header | rest] ->
          col_count = header |> String.split("|") |> length() |> Kernel.-(2)

          separator =
            "| " <> Enum.map_join(1..col_count, " | ", fn _ -> "---" end) <> " |"

          "\n\n#{header}\n#{separator}\n#{Enum.join(rest, "\n")}\n\n"

        _ ->
          ""
      end
    end
  end
end
