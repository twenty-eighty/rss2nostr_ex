defmodule Rss2Nostr.Nostr.Publisher.Identifiers do
  @moduledoc false

  @spec from_event(map()) :: String.t()
  def from_event(event) do
    case Enum.find(event.tags, fn [tag | _] -> tag == "d" end) do
      [_, identifier | _] -> identifier
      _ -> ""
    end
  end

  @spec from_post(map()) :: String.t()
  def from_post(post) do
    slug_from_url(field(post, :source_url)) ||
      slugify(field(post, :title)) ||
      fallback_identifier(post)
  end

  @spec part_identifier(String.t(), integer(), integer()) :: String.t()
  def part_identifier(identifier, _index, 1), do: identifier

  def part_identifier(identifier, index, _total) do
    suffix = "-p#{index}"
    max = 64 - byte_size(suffix)
    String.slice(identifier || "", 0, max) <> suffix
  end

  @spec part_title(String.t(), integer(), integer()) :: String.t()
  def part_title(title, _index, 1), do: title
  def part_title(title, index, total), do: "#{title} (#{index}/#{total})"

  @spec slugify(String.t() | nil) :: String.t() | nil
  def slugify(nil), do: nil
  def slugify(""), do: nil

  def slugify(text) do
    slug =
      text
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[äöüß]/, fn
        "ä" -> "ae"
        "ö" -> "oe"
        "ü" -> "ue"
        "ß" -> "ss"
      end)
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.slice(0, 64)

    if slug == "", do: nil, else: slug
  end

  defp slug_from_url(url) when is_binary(url) and url != "" do
    path = url |> URI.parse() |> Map.get(:path) || ""

    path
    |> String.split("/", trim: true)
    |> List.last()
    |> case do
      nil ->
        nil

      segment ->
        segment
        |> String.replace(~r/\.[^.]+$/, "")
        |> slugify()
    end
  end

  defp slug_from_url(_), do: nil

  defp fallback_identifier(post) do
    field(post, :source_url_hash) ||
      case field(post, :id) do
        nil -> "post"
        id -> "post-#{id}"
      end
  end

  defp field(%{__struct__: _} = struct, key), do: Map.get(struct, key)
  defp field(map, key) when is_map(map), do: map[key] || map[Atom.to_string(key)]
  defp field(_, _), do: nil
end
