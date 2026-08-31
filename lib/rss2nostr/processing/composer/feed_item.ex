defmodule Rss2Nostr.Processing.Composer.FeedItem do
  @moduledoc false

  alias Rss2Nostr.Import.ItemIdentity
  alias Rss2Nostr.Processing.{ImageExtractor, Labels}

  @html_tag ~r/<\/?[a-zA-Z][^>]*>/
  @soundcloud_track_re ~r{\Ahttps?://(?:www\.)?soundcloud\.com/[^/\s]+/[^/\s?#]+}i

  @spec field(map(), atom()) :: term()
  def field(item, key) when is_map(item) do
    blank_to_nil(item[key] || item[Atom.to_string(key)])
  end

  @spec html(map()) :: String.t() | nil
  def html(item) do
    content = field(item, :content)
    summary = field(item, :summary)

    cond do
      not blank?(content) -> normalize_feed_html(content)
      not blank?(summary) -> normalize_feed_html(summary)
      true -> nil
    end
  end

  @spec with_enclosure_html(
          {:ok, String.t(), String.t()} | {:error, term()},
          map(),
          String.t() | nil
        ) ::
          {:ok, String.t(), String.t()} | {:error, term()}
  def with_enclosure_html({:ok, html, source}, item, language) do
    {:ok, media_prefix(item, html, language) <> to_string(html || ""), source}
  end

  def with_enclosure_html(other, _item, _language), do: other

  @spec normalize_feed_html(String.t()) :: String.t()
  defp normalize_feed_html(html) do
    if looks_like_html?(html), do: html, else: plain_text_to_html(html)
  end

  @spec looks_like_html?(String.t()) :: boolean()
  defp looks_like_html?(text), do: Regex.match?(@html_tag, text)

  @spec plain_text_to_html(String.t()) :: String.t()
  defp plain_text_to_html(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.split(~r/\n{2,}/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map_join("", fn paragraph ->
      inner =
        paragraph
        |> Plug.HTML.html_escape()
        |> String.replace("\n", "<br>\n")

      "<p>#{inner}</p>"
    end)
  end

  @spec media_prefix(map(), String.t() | nil, String.t() | nil) :: String.t()
  defp media_prefix(item, html, language) do
    html = to_string(html || "")

    cond do
      prefix = soundcloud_listen_prefix(item, html, language) ->
        prefix

      page = ItemIdentity.page_url(item) ->
        _ = page
        ""

      true ->
        enclosure_prefix(item, html, language)
    end
  end

  @spec soundcloud_listen_prefix(map(), String.t(), String.t() | nil) :: String.t() | nil
  defp soundcloud_listen_prefix(item, html, language) do
    case ItemIdentity.page_url(item) do
      url when is_binary(url) ->
        if soundcloud_track_url?(url) and not String.contains?(html, url) do
          label = Labels.t(:listen_on, language, platform: "SoundCloud")
          ~s(<p><a href="#{html_attr(url)}">#{label}</a></p>\n)
        end

      _ ->
        nil
    end
  end

  @spec soundcloud_track_url?(String.t()) :: boolean()
  defp soundcloud_track_url?(url) do
    Regex.match?(@soundcloud_track_re, String.trim(url))
  end

  @spec enclosure_prefix(map(), String.t(), String.t() | nil) :: String.t()
  defp enclosure_prefix(item, html, language) do
    url = field(item, :enclosure_url)

    cond do
      blank?(url) ->
        ""

      String.contains?(html, url) ->
        ""

      ImageExtractor.video_url?(url) ->
        title = enclosure_title(item)
        title_attr = if title, do: ~s( title="#{html_attr(title)}"), else: ""
        ~s(<p><a href="#{html_attr(url)}"#{title_attr}>#{Labels.t(:video, language)}</a></p>\n)

      ImageExtractor.audio_url?(url) ->
        title = enclosure_title(item)
        title_attr = if title, do: ~s( title="#{html_attr(title)}"), else: ""
        ~s(<p><a href="#{html_attr(url)}"#{title_attr}>#{Labels.t(:audio, language)}</a></p>\n)

      true ->
        ""
    end
  end

  @spec enclosure_title(map()) :: String.t() | nil
  defp enclosure_title(item) do
    parts =
      [field(item, :duration), field(item, :enclosure_length)]
      |> Enum.map(&to_string_or_nil/1)
      |> Enum.reject(&is_nil/1)

    if parts == [], do: nil, else: Enum.join(parts, " ")
  end

  @spec to_string_or_nil(integer() | String.t() | term()) :: String.t() | nil
  defp to_string_or_nil(value) when is_integer(value) and value > 0, do: Integer.to_string(value)
  defp to_string_or_nil(value) when is_binary(value) and value != "", do: value
  defp to_string_or_nil(_), do: nil

  @spec html_attr(String.t()) :: String.t()
  defp html_attr(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
  end

  @spec blank?(term()) :: boolean()
  defp blank?(value), do: blank_to_nil(value) == nil

  @spec blank_to_nil(term()) :: term()
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
