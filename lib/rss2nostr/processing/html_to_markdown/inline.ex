defmodule Rss2Nostr.Processing.HtmlToMarkdown.Inline do
  @moduledoc false

  alias Rss2Nostr.Processing.HtmlToMarkdown.{Dom, Links}

  @type process_nodes :: (list() -> String.t())

  @spec merge_adjacent(list()) :: list()
  def merge_adjacent(nodes) do
    Enum.reduce(nodes, [], &merge_next/2)
  end

  @spec process_heading(String.t(), list(), process_nodes()) :: String.t()
  def process_heading(tag, children, process_nodes) do
    level = String.slice(tag, 1, 1)
    prefix = String.duplicate("#", String.to_integer(level))
    "\n\n#{prefix} #{process_nodes.(children)}\n\n"
  end

  @spec process_emphasis(String.t(), list(), list(), process_nodes()) :: String.t()
  def process_emphasis("strong", _attrs, children, process_nodes),
    do: wrap_inline(process_nodes.(unwrap_same_role(children, :strong)), "**")

  def process_emphasis("b", _attrs, children, process_nodes),
    do: wrap_inline(process_nodes.(unwrap_same_role(children, :strong)), "**")

  def process_emphasis("em", attrs, children, process_nodes) do
    if Links.icon_class?(Dom.get_attr(attrs, "class", "")) do
      process_nodes.(children)
    else
      wrap_inline(process_nodes.(unwrap_same_role(children, :em)), "_")
    end
  end

  def process_emphasis("i", attrs, children, process_nodes) do
    if Links.icon_class?(Dom.get_attr(attrs, "class", "")) do
      process_nodes.(children)
    else
      wrap_inline(process_nodes.(unwrap_same_role(children, :em)), "_")
    end
  end

  def process_emphasis("u", _attrs, children, process_nodes),
    do: wrap_inline(process_nodes.(children), "_")

  def process_emphasis("code", _attrs, children, process_nodes),
    do: "`#{process_nodes.(children)}`"

  def process_emphasis("pre", _attrs, children, _process_nodes),
    do: "\n\n```\n#{Floki.text(children)}\n```\n\n"

  def process_emphasis("mark", _attrs, children, process_nodes),
    do: wrap_inline(process_nodes.(children), "==")

  def process_emphasis(_, _attrs, children, process_nodes),
    do: process_nodes.(children)

  defp merge_next(node, acc) do
    last = List.last(acc)

    cond do
      same_inline_role?(last, node) ->
        List.replace_at(acc, -1, concat_inline(last, node))

      whitespace_only?(last) and length(acc) >= 2 and
          same_inline_role?(Enum.at(acc, -2), node) ->
        prev = Enum.at(acc, -2)
        Enum.drop(acc, -2) ++ [concat_inline(prev, last, node)]

      true ->
        acc ++ [node]
    end
  end

  defp concat_inline({tag, attrs, left}, {_, _, right}) do
    {tag, attrs, left ++ right}
  end

  defp concat_inline({tag, attrs, left}, ws, {_, _, right}) when is_binary(ws) do
    {tag, attrs, left ++ [ws] ++ right}
  end

  defp same_inline_role?({left, _, _}, {right, _, _}) do
    role = inline_role(left)
    role != nil and role == inline_role(right)
  end

  defp same_inline_role?(_, _), do: false

  defp inline_role(tag) when tag in ~w(em i), do: :em
  defp inline_role(tag) when tag in ~w(strong b), do: :strong
  defp inline_role(_), do: nil

  defp unwrap_same_role(children, role) do
    Enum.flat_map(children, fn
      {tag, attrs, inner} ->
        if inline_role(tag) == role do
          unwrap_same_role(inner, role)
        else
          [{tag, attrs, unwrap_same_role(inner, role)}]
        end

      other ->
        [other]
    end)
  end

  defp whitespace_only?(text) when is_binary(text), do: String.match?(text, ~r/\A\s*\z/u)
  defp whitespace_only?(_), do: false

  defp wrap_inline(content, marker) do
    case Regex.run(~r/\A(\s*)(.*?)(\s*)\z/us, content) do
      [_, lead, mid, trail] when mid != "" ->
        lead <> marker <> mid <> marker <> trail

      [_, lead, _, trail] ->
        lead <> trail

      _ ->
        content
    end
  end
end
