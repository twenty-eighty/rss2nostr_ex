defmodule Rss2Nostr.Processing.Footnotes do
  @moduledoc """
  Pulls Markdown footnote definitions out of an article and attaches
  the ones a chunk cites, so a split event still carries its notes.
  """

  @definition ~r/^ {0,3}\[\^([^\]]+)\]:/
  @citation ~r/\[\^([^\]]+)\](?!:)/

  @type footnote :: {String.t(), String.t()}

  @spec extract(String.t()) :: {String.t(), [footnote()]}
  def extract(content) when content in [nil, ""], do: {content || "", []}

  def extract(content) when is_binary(content) do
    lines = String.split(content, "\n")

    case first_definition_index(lines) do
      nil ->
        {content, []}

      index ->
        {body_lines, def_lines} = Enum.split(lines, index)
        body = body_lines |> Enum.join("\n") |> strip_trailing_rule() |> String.trim_trailing()
        {body, parse_definitions(def_lines)}
    end
  end

  @spec cited_ids(String.t()) :: [String.t()]
  def cited_ids(text) when is_binary(text) do
    @citation
    |> Regex.scan(text)
    |> Enum.map(&Enum.at(&1, 1))
    |> Enum.uniq()
  end

  def cited_ids(_), do: []

  @doc """
  Appends footnote definitions this chunk cites.

  Options:
    * `:last` — also keep notes that no earlier part cited
    * `:already_cited` — footnote ids already attached to previous parts
  """
  @spec attach(String.t(), [footnote()], keyword()) :: String.t()
  def attach(chunk, footnotes, opts \\ [])
  def attach(chunk, [], _opts), do: chunk

  def attach(chunk, footnotes, opts) when is_binary(chunk) and is_list(footnotes) do
    cited = MapSet.new(cited_ids(chunk))
    already = MapSet.new(List.wrap(Keyword.get(opts, :already_cited, [])))
    last? = Keyword.get(opts, :last, false)

    selected =
      Enum.filter(footnotes, fn {id, _} ->
        MapSet.member?(cited, id) or (last? and not MapSet.member?(already, id))
      end)

    append(chunk, selected)
  end

  defp append(chunk, []), do: chunk

  defp append(chunk, selected) do
    notes = selected |> Enum.map(&elem(&1, 1)) |> Enum.join("\n\n")
    String.trim_trailing(chunk) <> "\n\n---\n\n" <> notes
  end

  defp first_definition_index(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce_while(false, fn {line, index}, fence ->
      cond do
        fence_marker?(line) ->
          {:cont, not fence}

        fence ->
          {:cont, true}

        definition_line?(line) ->
          {:halt, index}

        true ->
          {:cont, false}
      end
    end)
    |> case do
      index when is_integer(index) -> index
      _ -> nil
    end
  end

  defp parse_definitions(lines) do
    {blocks, acc} =
      Enum.reduce(lines, {[], nil}, fn line, {blocks, acc} ->
        case definition_id(line) do
          {:ok, id} ->
            {flush(blocks, acc), {id, [line]}}

          :error ->
            case acc do
              nil -> {blocks, nil}
              {id, prev} -> {blocks, {id, [line | prev]}}
            end
        end
      end)

    flush(blocks, acc)
    |> Enum.reverse()
    |> Enum.reject(fn {_id, block} -> block == "" end)
  end

  defp flush(blocks, nil), do: blocks

  defp flush(blocks, {id, lines}) do
    block = lines |> Enum.reverse() |> Enum.join("\n") |> String.trim_trailing()
    [{id, block} | blocks]
  end

  defp definition_line?(line), do: match?({:ok, _}, definition_id(line))

  defp definition_id(line) do
    case Regex.run(@definition, line) do
      [_, id] -> {:ok, id}
      _ -> :error
    end
  end

  defp fence_marker?(line), do: String.starts_with?(String.trim_leading(line), "```")

  defp strip_trailing_rule(text) do
    String.replace(text, ~r/\n+---+\s*$/, "")
  end
end
