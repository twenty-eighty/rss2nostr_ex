defmodule Rss2Nostr.Import.FeedParser do
  @moduledoc """
  Parses RSS and Atom feeds into a normalized format.
  """

  import SweetXml
  require Logger

  @type feed_item :: %{
          title: String.t() | nil,
          link: String.t() | nil,
          guid: String.t() | nil,
          author: String.t() | nil,
          published_at: DateTime.t() | nil,
          summary: String.t() | nil,
          content: String.t() | nil,
          image: String.t() | nil,
          categories: [String.t()]
        }

  @doc """
  Parses a feed and returns a list of items.
  Automatically detects RSS vs Atom format.
  """
  @spec parse(String.t(), String.t() | nil) :: {:ok, [feed_item()]} | {:error, String.t()}
  def parse(xml_body, type \\ nil) when is_binary(xml_body) do
    feed_type = type || detect_feed_type(xml_body)

    case feed_type do
      "rss" -> parse_rss(xml_body)
      "atom" -> parse_atom(xml_body)
      _ -> {:error, "Unknown feed type"}
    end
  end

  @doc """
  Detects whether the feed is RSS or Atom.
  """
  @spec detect_feed_type(String.t()) :: String.t() | nil
  def detect_feed_type(xml_body) do
    cond do
      String.contains?(xml_body, "<rss") ->
        "rss"

      String.contains?(xml_body, "<feed") &&
          String.contains?(xml_body, "xmlns=\"http://www.w3.org/2005/Atom\"") ->
        "atom"

      String.contains?(xml_body, "<feed") ->
        "atom"

      String.contains?(xml_body, "<channel>") ->
        "rss"

      true ->
        nil
    end
  end

  @doc """
  Channel/feed title from RSS or Atom XML, or nil.
  """
  @spec feed_title(String.t()) :: String.t() | nil
  def feed_title(xml_body) when is_binary(xml_body) do
    title =
      case detect_feed_type(xml_body) do
        "rss" -> xpath_text(xml_body, ~x"//channel/title/text()"s)
        "atom" -> atom_feed_title(xml_body)
        _ -> nil
      end

    clean_text(title)
  end

  def feed_title(_), do: nil

  @doc """
  Channel/feed language as a lowercase ISO 639 code, or nil.

  RSS `<language>en-us</language>` and Atom `xml:lang` become `"en"`.
  """
  @spec feed_language(String.t()) :: String.t() | nil
  def feed_language(xml_body) when is_binary(xml_body) do
    raw =
      case detect_feed_type(xml_body) do
        "rss" -> xpath_text(xml_body, ~x"//channel/language/text()"s)
        "atom" -> atom_feed_language(xml_body)
        _ -> nil
      end

    normalize_feed_language(raw)
  end

  def feed_language(_), do: nil

  # RSS Parsing
  defp parse_rss(xml_body) do
    try do
      items =
        xml_body
        |> xpath(
          ~x"//item"l,
          title: ~x"./title/text()"s,
          link: ~x"./link/text()"s,
          guid: ~x"./guid/text()"s,
          author:
            ~x"./dc:creator/text()"s |> add_namespace("dc", "http://purl.org/dc/elements/1.1/"),
          pub_date: ~x"./pubDate/text()"s,
          description: ~x"./description/text()"s,
          content_encoded:
            ~x"./content:encoded/text()"s
            |> add_namespace("content", "http://purl.org/rss/1.0/modules/content/"),
          enclosure_url: ~x"./enclosure/@url"s,
          enclosure_type: ~x"./enclosure/@type"s,
          media_thumbnail:
            ~x"./media:thumbnail/@url"s |> add_namespace("media", "http://search.yahoo.com/mrss/"),
          media_content:
            ~x"./media:content/@url"s |> add_namespace("media", "http://search.yahoo.com/mrss/"),
          itunes_image:
            ~x"./itunes:image/@href"s
            |> add_namespace("itunes", "http://www.itunes.com/dtds/podcast-1.0.dtd"),
          categories: ~x"./category/text()"ls
        )
        |> Enum.map(&normalize_rss_item/1)

      {:ok, items}
    rescue
      e ->
        Logger.error("RSS parsing error: #{inspect(e)}")
        {:error, "Failed to parse RSS: #{inspect(e)}"}
    end
  end

  defp normalize_rss_item(item) do
    %{
      title: clean_text(item.title),
      link: clean_text(item.link),
      guid: clean_text(item.guid) || clean_text(item.link),
      author: clean_text(item.author),
      published_at: parse_date(item.pub_date),
      summary: decode_html(item.description),
      content: decode_html(item.content_encoded),
      image: extract_rss_image(item),
      categories: item.categories || []
    }
  end

  defp extract_rss_image(item) do
    cond do
      # Enclosure with image type
      item.enclosure_url != "" && String.starts_with?(item.enclosure_type || "", "image") ->
        item.enclosure_url

      # Media thumbnail
      item.media_thumbnail != "" ->
        item.media_thumbnail

      # Media content
      item.media_content != "" ->
        item.media_content

      # iTunes image
      item.itunes_image != "" ->
        item.itunes_image

      true ->
        nil
    end
  end

  # Atom Parsing
  defp parse_atom(xml_body) do
    try do
      items =
        xml_body
        |> xpath(
          ~x"//entry"l |> add_namespace("atom", "http://www.w3.org/2005/Atom"),
          title: ~x"./atom:title/text()"s |> add_namespace("atom", "http://www.w3.org/2005/Atom"),
          link_href:
            ~x"./atom:link[@rel='alternate']/@href"s
            |> add_namespace("atom", "http://www.w3.org/2005/Atom"),
          link_default:
            ~x"./atom:link/@href"s |> add_namespace("atom", "http://www.w3.org/2005/Atom"),
          id: ~x"./atom:id/text()"s |> add_namespace("atom", "http://www.w3.org/2005/Atom"),
          author:
            ~x"./atom:author/atom:name/text()"s
            |> add_namespace("atom", "http://www.w3.org/2005/Atom"),
          published:
            ~x"./atom:published/text()"s |> add_namespace("atom", "http://www.w3.org/2005/Atom"),
          updated:
            ~x"./atom:updated/text()"s |> add_namespace("atom", "http://www.w3.org/2005/Atom"),
          summary:
            ~x"./atom:summary/text()"s |> add_namespace("atom", "http://www.w3.org/2005/Atom"),
          content:
            ~x"./atom:content/text()"s |> add_namespace("atom", "http://www.w3.org/2005/Atom"),
          categories:
            ~x"./atom:category/@term"ls |> add_namespace("atom", "http://www.w3.org/2005/Atom")
        )

      # If namespace parsing didn't work, try without namespaces
      items =
        if Enum.empty?(items) || Enum.all?(items, &(&1.title == "")) do
          xml_body
          |> xpath(
            ~x"//entry"l,
            title: ~x"./title/text()"s,
            link_href: ~x"./link[@rel='alternate']/@href"s,
            link_default: ~x"./link/@href"s,
            id: ~x"./id/text()"s,
            author: ~x"./author/name/text()"s,
            published: ~x"./published/text()"s,
            updated: ~x"./updated/text()"s,
            summary: ~x"./summary/text()"s,
            content: ~x"./content/text()"s,
            categories: ~x"./category/@term"ls
          )
        else
          items
        end

      normalized = Enum.map(items, &normalize_atom_item/1)
      {:ok, normalized}
    rescue
      e ->
        Logger.error("Atom parsing error: #{inspect(e)}")
        {:error, "Failed to parse Atom: #{inspect(e)}"}
    end
  end

  defp normalize_atom_item(item) do
    link = if item.link_href != "", do: item.link_href, else: item.link_default
    published = if item.published != "", do: item.published, else: item.updated

    %{
      title: clean_text(item.title),
      link: clean_text(link),
      guid: clean_text(item.id) || clean_text(link),
      author: clean_text(item.author),
      published_at: parse_date(published),
      summary: decode_html(item.summary),
      content: decode_html(item.content),
      # Atom doesn't typically include images in standard tags
      image: nil,
      categories: item.categories || []
    }
  end

  # Helper functions

  defp atom_feed_language(xml_body) do
    with_ns =
      xpath_text(
        xml_body,
        ~x"//atom:feed/@xml:lang"s
        |> add_namespace("atom", "http://www.w3.org/2005/Atom")
      )

    if with_ns == "" do
      xpath_text(xml_body, ~x"//feed/@xml:lang"s)
    else
      with_ns
    end
  end

  defp normalize_feed_language(nil), do: nil
  defp normalize_feed_language(""), do: nil

  defp normalize_feed_language(value) when is_binary(value) do
    code =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace("_", "-")

    case Regex.run(~r/\A([a-z]{2,3})\b/, code) do
      [_, lang] -> lang
      _ -> nil
    end
  end

  defp atom_feed_title(xml_body) do
    titled =
      xml_body
      |> xpath(
        ~x"//atom:feed/atom:title/text()"s
        |> add_namespace("atom", "http://www.w3.org/2005/Atom")
      )

    if titled == "" do
      xpath_text(xml_body, ~x"//feed/title/text()"s)
    else
      titled
    end
  end

  defp xpath_text(xml_body, spec) do
    try do
      xpath(xml_body, spec)
    rescue
      _ -> ""
    end
  end

  defp clean_text(nil), do: nil
  defp clean_text(""), do: nil

  defp clean_text(text) when is_binary(text) do
    text
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp decode_html(nil), do: nil
  defp decode_html(""), do: nil

  defp decode_html(text) when is_binary(text) do
    text
    |> HtmlEntities.decode()
    |> String.trim()
    |> case do
      "" -> nil
      decoded -> decoded
    end
  rescue
    e ->
      Logger.debug("HTML entity decoding failed for text: #{inspect(e)}")
      String.trim(text)
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    # Try various date formats
    parsers = [
      # RFC 2822 (RSS standard)
      fn s -> Timex.parse(s, "{RFC1123}") end,
      fn s -> Timex.parse(s, "{RFC822}") end,
      # ISO 8601 (Atom standard)
      fn s -> Timex.parse(s, "{ISO:Extended}") end,
      fn s -> Timex.parse(s, "{ISO:Extended:Z}") end,
      fn s -> Timex.parse(s, "{YYYY}-{0M}-{0D}T{h24}:{m}:{s}{Z:}") end,
      fn s -> Timex.parse(s, "{YYYY}-{0M}-{0D}T{h24}:{m}:{s}") end,
      # Common variations
      fn s -> Timex.parse(s, "{YYYY}-{0M}-{0D} {h24}:{m}:{s}") end,
      fn s -> Timex.parse(s, "{0D} {Mshort} {YYYY} {h24}:{m}:{s} {Z}") end,
      fn s -> Timex.parse(s, "{WDshort}, {0D} {Mshort} {YYYY} {h24}:{m}:{s} {Z}") end,
      fn s -> Timex.parse(s, "{WDshort}, {0D} {Mshort} {YYYY} {h24}:{m}:{s} {Zabbr}") end
    ]

    Enum.find_value(parsers, nil, fn parser ->
      case parser.(date_string) do
        {:ok, datetime} -> naive_to_utc(datetime)
        _ -> nil
      end
    end)
  end

  defp naive_to_utc(datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, dt} -> dt
      _ -> Timex.to_datetime(datetime, "Etc/UTC")
    end
  end
end

# Simple HTML entity decoder (fallback if HtmlEntities not available)
defmodule HtmlEntities do
  @moduledoc false

  @entities %{
    "&amp;" => "&",
    "&lt;" => "<",
    "&gt;" => ">",
    "&quot;" => "\"",
    "&apos;" => "'",
    "&nbsp;" => " ",
    "&#39;" => "'"
  }

  def decode(text) when is_binary(text) do
    Enum.reduce(@entities, text, fn {entity, char}, acc ->
      String.replace(acc, entity, char)
    end)
    |> decode_numeric_entities()
  end

  defp decode_numeric_entities(text) do
    text
    |> decode_decimal_entities()
    |> decode_hex_entities()
  end

  defp decode_decimal_entities(text) do
    Regex.replace(~r/&#(\d+);/, text, fn _, code ->
      try do
        <<String.to_integer(code)::utf8>>
      rescue
        ArgumentError -> "?"
        _ -> "?"
      end
    end)
  end

  defp decode_hex_entities(text) do
    Regex.replace(~r/&#x([0-9a-fA-F]+);/, text, fn _, code ->
      try do
        <<String.to_integer(code, 16)::utf8>>
      rescue
        ArgumentError -> "?"
        _ -> "?"
      end
    end)
  end
end
