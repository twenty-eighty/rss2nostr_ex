defmodule Rss2Nostr.Processing.HtmlToMarkdown.SoundcloudPermalink do
  @moduledoc false

  @spec permalink(String.t()) :: String.t() | nil
  def permalink(html) when is_binary(html) do
    hydration_permalink(html) ||
      List.first(track_permalinks_in_html(html)) ||
      player_inner_url(html)
  end

  def permalink(_), do: nil

  @spec player_permalink(String.t()) :: String.t() | nil
  def player_permalink(src) when is_binary(src), do: permalink_from_player(src)
  def player_permalink(_), do: nil

  @spec host?(String.t()) :: boolean()
  def host?(url) when is_binary(url) do
    host = url |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()
    host == "soundcloud.com" or String.ends_with?(host, ".soundcloud.com")
  end

  def host?(_), do: false

  @doc false
  @spec player_color(String.t()) :: String.t() | nil
  def player_color(html) when is_binary(html) do
    html
    |> soundcloud_player_srcs()
    |> Enum.find_value(&color_from_player/1)
  end

  def player_color(_), do: nil

  @doc false
  @spec normalize_color(term()) :: String.t() | nil
  def normalize_color(nil), do: nil
  def normalize_color(""), do: nil

  def normalize_color(value) when is_binary(value) do
    hex =
      value
      |> String.trim()
      |> String.replace_prefix("#", "")
      |> String.downcase()

    cond do
      String.match?(hex, ~r/\A[0-9a-f]{6}\z/) -> "#" <> hex
      String.match?(hex, ~r/\A[0-9a-f]{3}\z/) -> "#" <> expand_short_hex(hex)
      true -> nil
    end
  end

  def normalize_color(_), do: nil

  defp expand_short_hex(<<a, b, c>>), do: <<a, a, b, b, c, c>>

  defp hydration_permalink(html) do
    case Regex.run(~r/window\.__sc_hydration\s*=\s*(\[.*?\])\s*;?/s, html) do
      [_, json] ->
        case Jason.decode(json) do
          {:ok, entries} when is_list(entries) ->
            Enum.find_value(entries, &hydration_sound_url/1)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp hydration_sound_url(%{"hydratable" => "sound", "data" => %{"permalink_url" => url}})
       when is_binary(url) and url != "" do
    url
  end

  defp hydration_sound_url(_), do: nil

  defp track_permalinks_in_html(html) do
    ~r/https?:\/\/(?:www\.)?soundcloud\.com\/[^\s"'<>]+/i
    |> Regex.scan(html)
    |> List.flatten()
    |> Enum.map(&trim_url_punct/1)
    |> Enum.filter(&track_permalink?/1)
    |> Enum.uniq()
  end

  defp player_inner_url(html) do
    html
    |> soundcloud_player_srcs()
    |> Enum.find_value(&permalink_from_player/1)
  end

  defp soundcloud_player_srcs(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        doc
        |> Floki.find("iframe")
        |> Enum.flat_map(fn iframe ->
          [
            iframe |> Floki.attribute("src") |> List.first(),
            iframe |> Floki.attribute("data-src") |> List.first()
          ]
        end)
        |> Enum.filter(&(is_binary(&1) and String.contains?(&1, "w.soundcloud.com/player")))

      _ ->
        []
    end
  end

  defp permalink_from_player(src) when is_binary(src) do
    src = String.replace(src, "&amp;", "&")

    query =
      src
      |> URI.parse()
      |> Map.get(:query)
      |> to_string()
      |> URI.decode_query()

    case query["url"] do
      url when is_binary(url) and url != "" ->
        if host?(url), do: url

      _ ->
        nil
    end
  end

  defp permalink_from_player(_), do: nil

  defp color_from_player(src) when is_binary(src) do
    src = String.replace(src, "&amp;", "&")

    query =
      src
      |> URI.parse()
      |> Map.get(:query)
      |> to_string()
      |> URI.decode_query()

    normalize_color(query["color"])
  end

  defp color_from_player(_), do: nil

  defp track_permalink?(url) when is_binary(url) do
    uri = URI.parse(url)
    host = uri.host |> to_string() |> String.downcase()
    segments = (uri.path || "") |> String.split("/", trim: true)

    host in ["soundcloud.com", "www.soundcloud.com"] and
      length(segments) >= 2 and
      hd(segments) not in ~w(you pages discover stream search groups signin login)
  end

  defp track_permalink?(_), do: false

  defp trim_url_punct(url) do
    String.replace(url, ~r/[\.,;:)\]]+$/, "")
  end
end
