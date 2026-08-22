defmodule Rss2Nostr.Processing.HtmlToMarkdown.Dom do
  @moduledoc false

  @spec get_attr(list(), String.t(), term()) :: term()
  def get_attr(attrs, name, default \\ nil) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> default
    end
  end

  @spec find_element(term(), String.t()) :: term() | nil
  def find_element(nodes, tag) when is_list(nodes) do
    Enum.find_value(nodes, &find_element(&1, tag))
  end

  def find_element({tag, _, _} = node, tag), do: node

  def find_element({_, _, children}, tag) when is_list(children) do
    find_element(children, tag)
  end

  def find_element(_, _), do: nil

  @spec find_all_elements(list(), String.t() | [String.t()]) :: list()
  def find_all_elements(nodes, tag) when is_binary(tag) do
    Enum.filter(nodes, fn
      {^tag, _, _} -> true
      _ -> false
    end)
  end

  def find_all_elements(nodes, tags) when is_list(tags) do
    Enum.filter(nodes, fn
      {tag, _, _} -> tag in tags
      _ -> false
    end)
  end
end
