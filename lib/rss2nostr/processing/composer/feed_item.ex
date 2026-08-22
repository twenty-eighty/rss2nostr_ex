defmodule Rss2Nostr.Processing.Composer.FeedItem do
  @moduledoc false

  alias Rss2Nostr.Import.ItemIdentity
  alias Rss2Nostr.Processing.{ImageExtractor, Labels}

  @spec field(map(), atom()) :: term()
  def field(item, key) when is_map(item) do
    blank_to_nil(item[key] || item[Atom.to_string(key)])
  end

  @spec html(map()) :: String.t() | nil
  def html(item) do
    content = field(item, :content)
    summary = field(item, :summary)

    cond do
      not blank?(content) -> content
      not blank?(summary) -> summary
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
    {:ok, enclosure_prefix(item, html, language) <> to_string(html || ""), source}
  end

  def with_enclosure_html(other, _item, _language), do: other

  defp enclosure_prefix(item, html, language) do
    url = field(item, :enclosure_url)
    html = to_string(html || "")

    cond do
      ItemIdentity.page_url(item) ->
        ""

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

  defp enclosure_title(item) do
    parts =
      [field(item, :duration), field(item, :enclosure_length)]
      |> Enum.map(&to_string_or_nil/1)
      |> Enum.reject(&is_nil/1)

    if parts == [], do: nil, else: Enum.join(parts, " ")
  end

  defp to_string_or_nil(value) when is_integer(value) and value > 0, do: Integer.to_string(value)
  defp to_string_or_nil(value) when is_binary(value) and value != "", do: value
  defp to_string_or_nil(_), do: nil

  defp html_attr(value) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
  end

  defp blank?(value), do: blank_to_nil(value) == nil

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
