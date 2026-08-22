defmodule Rss2Nostr.Processing.HtmlToMarkdown.Blocks do
  @moduledoc false

  alias Rss2Nostr.Processing.HtmlToMarkdown.{Dom, Embeds, LinkTags, Links}

  @type process_nodes :: (list() -> String.t())

  @spec process_paragraph(list(), process_nodes()) :: String.t()
  def process_paragraph(children, process_nodes) do
    content = process_nodes.(children)

    if String.trim(content) == "*" do
      "\n\n---\n\n"
    else
      "\n\n#{content}\n\n"
    end
  end

  @spec process_div(list(), list(), process_nodes()) :: String.t()
  def process_div(attrs, children, process_nodes) do
    class = Dom.get_attr(attrs, "class", "")

    cond do
      String.contains?(class, "youtube") ->
        case Embeds.process_youtube_div(attrs, children) do
          md when is_binary(md) and md != "" -> md
          _ -> process_nodes.(children)
        end

      String.contains?(class, "powerpress") ->
        Embeds.process_powerpress_div(children)

      String.contains?(String.downcase(class), "pullquote") ->
        process_blockquote(children, process_nodes)

      callout_div?(class) ->
        children
        |> blockify_callout_children()
        |> then(&process_blockquote(&1, process_nodes))

      Links.social_bar_class?(class) ->
        LinkTags.process_social_bar(children)

      Embeds.soundcloud_widget_div?(children) ->
        ""

      true ->
        process_nodes.(children)
    end
  end

  @spec process_list(list(), :ordered | :unordered, process_nodes(), integer()) :: String.t()
  def process_list(children, type, process_nodes, indent \\ 0) do
    children
    |> Enum.filter(fn
      {"li", _, _} -> true
      _ -> false
    end)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {{"li", _, li_children}, index} ->
      prefix = String.duplicate("  ", indent)
      marker = if type == :ordered, do: "#{index}.", else: "-"
      content = process_nodes.(li_children) |> String.trim()
      "#{prefix}#{marker} #{content}"
    end)
  end

  @spec process_blockquote(list(), process_nodes()) :: String.t()
  def process_blockquote(children, process_nodes) do
    content = process_nodes.(children)

    quoted =
      content
      |> String.trim()
      |> String.split("\n")
      |> Enum.map(&("> " <> &1))
      |> collapse_blank_quote_lines()
      |> Enum.join("\n")

    "\n\n#{quoted}\n\n"
  end

  defp collapse_blank_quote_lines(lines) do
    {kept, _} =
      Enum.reduce(lines, {[], false}, fn line, {acc, skipping} ->
        blank? = String.trim(line) in [">", ""]

        cond do
          blank? and skipping ->
            {acc, true}

          true ->
            {acc ++ [line], blank?}
        end
      end)

    kept
  end

  defp callout_div?(class) when is_binary(class) do
    class
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.any?(&callout_class?/1)
  end

  defp callout_class?(token) do
    token in ~w(message notice alert callout infobox) or
      String.starts_with?(token, "message--") or
      String.starts_with?(token, "alert-") or
      String.starts_with?(token, "notice-")
  end

  defp blockify_callout_children(children) do
    Enum.flat_map(List.wrap(children), fn
      {"span", attrs, inner} ->
        [{"p", attrs, inner}]

      {"a", attrs, inner} ->
        [{"p", [], [{"a", attrs, inner}]}]

      text when is_binary(text) ->
        if String.trim(text) == "", do: [], else: [{"p", [], [text]}]

      other ->
        [other]
    end)
  end
end
