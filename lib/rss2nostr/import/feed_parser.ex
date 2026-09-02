defmodule Rss2Nostr.Import.FeedParser do
  @moduledoc """
  Parses RSS and Atom feeds into a normalized format.
  """

  import SweetXml, except: [parse: 1, parse: 2]
  require Logger

  @type raw_item :: %{optional(atom()) => String.t() | [String.t()] | nil}

  @type feed_item :: %{
          title: String.t() | nil,
          link: String.t() | nil,
          guid: String.t() | nil,
          author: String.t() | nil,
          published_at: DateTime.t() | nil,
          summary: String.t() | nil,
          content: String.t() | nil,
          image: String.t() | nil,
          enclosure_url: String.t() | nil,
          enclosure_type: String.t() | nil,
          enclosure_length: integer() | nil,
          duration: String.t() | nil,
          categories: [String.t()] | nil
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
  Parses feed metadata without loading full article HTML bodies.

  Huge RSS feeds (e.g. full `content:encoded` for every post) are stripped
  before XML parsing so Compose pickers and `fetch_from_url` imports stay fast.
  Use `hydrate_item/3` when a single item's body is needed afterward.
  """
  @spec parse_listing(String.t(), String.t() | nil) :: {:ok, [feed_item()]} | {:error, String.t()}
  def parse_listing(xml_body, type \\ nil) when is_binary(xml_body) do
    xml_body
    |> strip_embedded_content()
    |> parse(type)
  end

  @doc """
  Removes full-text article bodies from RSS/Atom XML before a listing parse.
  """
  @spec strip_embedded_content(String.t()) :: String.t()
  def strip_embedded_content(xml) when is_binary(xml) do
    xml
    |> strip_elements("content:encoded")
    |> strip_atom_content_elements()
  end

  @doc """
  Fills `content` / `summary` for one listing item from the original feed XML.
  """
  @spec hydrate_item(String.t(), String.t() | nil, feed_item()) :: feed_item()
  def hydrate_item(xml_body, type, item) when is_binary(xml_body) and is_map(item) do
    feed_type = type || detect_feed_type(xml_body)
    key = item.guid || item.link

    with true <- is_binary(key) and key != "",
         chunk when is_binary(chunk) <- extract_entry_xml(xml_body, feed_type, key),
         {:ok, [full | _]} <- parse(wrap_entry_xml(chunk, feed_type), feed_type) do
      %{
        item
        | summary: full.summary || item.summary,
          content: full.content || item.content,
          image: full.image || item.image,
          author: full.author || item.author,
          categories: full.categories || item.categories,
          enclosure_url: full.enclosure_url || item.enclosure_url,
          enclosure_type: full.enclosure_type || item.enclosure_type,
          enclosure_length: full.enclosure_length || item.enclosure_length,
          duration: full.duration || item.duration
      }
    else
      _ -> item
    end
  end

  def hydrate_item(_, _, item), do: item

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

    decode_html(title)
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
  @spec parse_rss(String.t()) :: {:ok, [feed_item()]} | {:error, String.t()}
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
          enclosure_length: ~x"./enclosure/@length"s,
          itunes_duration:
            ~x"./itunes:duration/text()"s
            |> add_namespace("itunes", "http://www.itunes.com/dtds/podcast-1.0.dtd"),
          media_thumbnail:
            ~x"./media:thumbnail/@url"ls |> add_namespace("media", "http://search.yahoo.com/mrss/"),
          media_image:
            ~x"./media:content[@medium='image']/@url"ls
            |> add_namespace("media", "http://search.yahoo.com/mrss/"),
          media_content:
            ~x"./media:content/@url"ls |> add_namespace("media", "http://search.yahoo.com/mrss/"),
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

  @spec normalize_rss_item(raw_item()) :: feed_item()
  defp normalize_rss_item(item) do
    %{
      title: decode_html(item.title),
      link: clean_text(item.link),
      guid: clean_text(item.guid) || clean_text(item.link),
      author: clean_text(item.author),
      published_at: parse_date(item.pub_date),
      summary: decode_html(item.description),
      content: decode_html(item.content_encoded),
      image: extract_rss_image(item),
      enclosure_url: clean_text(item.enclosure_url),
      enclosure_type: clean_text(item.enclosure_type),
      enclosure_length: parse_length(item.enclosure_length),
      duration: clean_text(item.itunes_duration),
      categories: item.categories || []
    }
  end

  @spec extract_rss_image(raw_item()) :: String.t() | nil
  defp extract_rss_image(item) do
    cond do
      # Enclosure with image type
      item.enclosure_url != "" && String.starts_with?(item.enclosure_type || "", "image") ->
        item.enclosure_url

      url = first_url(Map.get(item, :media_thumbnail)) ->
        url

      url = first_url(Map.get(item, :media_image)) ->
        url

      url = first_url(Map.get(item, :media_content)) ->
        url

      item.itunes_image != "" ->
        item.itunes_image

      true ->
        nil
    end
  end

  # SweetXml's string modifier concatenates duplicate attributes; prefer the first URL.
  @spec first_url(term()) :: String.t() | nil
  defp first_url(urls) when is_list(urls) do
    Enum.find_value(urls, &first_url/1)
  end

  defp first_url(url) when is_binary(url) do
    case String.trim(url) do
      "" ->
        nil

      trimmed ->
        case Regex.run(~r/https?:\/\/\S+?(?=https?:\/\/|$)/u, trimmed) do
          [first] -> first
          _ -> trimmed
        end
    end
  end

  defp first_url(_), do: nil

  # Atom Parsing
  @spec parse_atom(String.t()) :: {:ok, [feed_item()]} | {:error, String.t()}
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

  @spec normalize_atom_item(raw_item()) :: feed_item()
  defp normalize_atom_item(item) do
    link = if item.link_href != "", do: item.link_href, else: item.link_default
    published = if item.published != "", do: item.published, else: item.updated

    %{
      title: decode_html(item.title),
      link: clean_text(link),
      guid: clean_text(item.id) || clean_text(link),
      author: clean_text(item.author),
      published_at: parse_date(published),
      summary: decode_html(item.summary),
      content: decode_html(item.content),
      # Atom doesn't typically include images in standard tags
      image: nil,
      enclosure_url: nil,
      enclosure_type: nil,
      enclosure_length: nil,
      duration: nil,
      categories: item.categories || []
    }
  end

  # Helper functions

  @spec atom_feed_language(String.t()) :: String.t()
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

  @spec normalize_feed_language(String.t() | nil) :: String.t() | nil
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

  @spec atom_feed_title(String.t()) :: String.t()
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

  @spec xpath_text(String.t(), term()) :: String.t()
  defp xpath_text(xml_body, spec) do
    try do
      xpath(xml_body, spec)
    rescue
      _ -> ""
    end
  end

  @spec parse_length(String.t() | integer() | nil) :: pos_integer() | nil
  defp parse_length(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_length(n) when is_integer(n) and n > 0, do: n
  defp parse_length(_), do: nil

  @spec clean_text(String.t() | nil) :: String.t() | nil
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

  @spec decode_html(String.t() | nil) :: String.t() | nil
  defp decode_html(nil), do: nil
  defp decode_html(""), do: nil

  defp decode_html(text) when is_binary(text) do
    text
    |> unescape_entities()
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

  @spec unescape_entities(String.t(), non_neg_integer()) :: String.t()
  defp unescape_entities(text, remaining \\ 3)
  defp unescape_entities(text, remaining) when remaining <= 0, do: text

  defp unescape_entities(text, remaining) do
    decoded = HtmlEntities.decode(text)

    if decoded == text do
      text
    else
      unescape_entities(decoded, remaining - 1)
    end
  end

  @spec parse_date(String.t() | nil) :: DateTime.t() | nil
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

  @spec naive_to_utc(DateTime.t() | NaiveDateTime.t()) :: DateTime.t()
  defp naive_to_utc(datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, dt} -> dt
      _ -> Timex.to_datetime(datetime, "Etc/UTC")
    end
  end

  # Binary strip avoids catastrophic regex backtracking on multi-megabyte feeds.
  @spec strip_elements(String.t(), String.t()) :: String.t()
  defp strip_elements(xml, tag) when is_binary(xml) and is_binary(tag) do
    do_strip_elements(xml, "<" <> tag, "</" <> tag <> ">", [])
  end

  @spec do_strip_elements(String.t(), String.t(), String.t(), iodata()) :: String.t()
  defp do_strip_elements(xml, open, close, acc) do
    case :binary.match(xml, open) do
      :nomatch ->
        IO.iodata_to_binary([Enum.reverse(acc), xml])

      {start, _} ->
        before = binary_part(xml, 0, start)
        from_open = binary_part(xml, start, byte_size(xml) - start)

        case :binary.match(from_open, close) do
          :nomatch ->
            IO.iodata_to_binary([Enum.reverse(acc), xml])

          {rel, close_len} ->
            after_close =
              binary_part(from_open, rel + close_len, byte_size(from_open) - rel - close_len)

            do_strip_elements(after_close, open, close, [before | acc])
        end
    end
  end

  # Strip Atom `<content>...</content>` but not RSS namespaced tags like `<content:creator>`.
  @spec strip_atom_content_elements(String.t()) :: String.t()
  defp strip_atom_content_elements(xml), do: do_strip_atom_content(xml, [])

  @spec do_strip_atom_content(String.t(), iodata()) :: String.t()
  defp do_strip_atom_content(xml, acc) do
    case :binary.match(xml, "<content") do
      :nomatch ->
        IO.iodata_to_binary([Enum.reverse(acc), xml])

      {start, open_len} ->
        after_prefix = start + open_len

        next =
          if after_prefix < byte_size(xml) do
            binary_part(xml, after_prefix, 1)
          else
            ""
          end

        cond do
          next == ":" ->
            do_strip_atom_content(
              binary_part(xml, after_prefix, byte_size(xml) - after_prefix),
              [binary_part(xml, 0, after_prefix) | acc]
            )

          next in [" ", ">", "/", "\n", "\r", "\t"] ->
            before = binary_part(xml, 0, start)
            from_open = binary_part(xml, start, byte_size(xml) - start)

            case :binary.match(from_open, "</content>") do
              :nomatch ->
                IO.iodata_to_binary([Enum.reverse(acc), xml])

              {rel, close_len} ->
                after_close =
                  binary_part(from_open, rel + close_len, byte_size(from_open) - rel - close_len)

                do_strip_atom_content(after_close, [before | acc])
            end

          true ->
            do_strip_atom_content(
              binary_part(xml, after_prefix, byte_size(xml) - after_prefix),
              [binary_part(xml, 0, after_prefix) | acc]
            )
        end
    end
  end

  @spec extract_entry_xml(String.t(), String.t(), String.t()) :: String.t() | nil
  defp extract_entry_xml(xml, "rss", key), do: extract_tagged_entry(xml, "item", key)
  defp extract_entry_xml(xml, "atom", key), do: extract_tagged_entry(xml, "entry", key)
  defp extract_entry_xml(_, _, _), do: nil

  @spec extract_tagged_entry(String.t(), String.t(), String.t()) :: String.t() | nil
  defp extract_tagged_entry(xml, tag, key) do
    find_entry_with_key(xml, "<" <> tag, "</" <> tag <> ">", key)
  end

  @spec find_entry_with_key(String.t(), String.t(), String.t(), String.t()) :: String.t() | nil
  defp find_entry_with_key(xml, open, close, key) do
    case :binary.match(xml, open) do
      :nomatch ->
        nil

      {start, _} ->
        from_open = binary_part(xml, start, byte_size(xml) - start)

        case :binary.match(from_open, close) do
          :nomatch ->
            nil

          {rel, close_len} ->
            chunk = binary_part(from_open, 0, rel + close_len)
            rest = binary_part(from_open, rel + close_len, byte_size(from_open) - rel - close_len)

            if String.contains?(chunk, key) do
              chunk
            else
              find_entry_with_key(rest, open, close, key)
            end
        end
    end
  end

  @spec wrap_entry_xml(String.t(), String.t()) :: String.t()
  defp wrap_entry_xml(chunk, "rss") do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:media="http://search.yahoo.com/mrss/">
      <channel>
        #{chunk}
      </channel>
    </rss>
    """
  end

  defp wrap_entry_xml(chunk, "atom") do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      #{chunk}
    </feed>
    """
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

  @spec decode(String.t()) :: String.t()
  def decode(text) when is_binary(text) do
    Enum.reduce(@entities, text, fn {entity, char}, acc ->
      String.replace(acc, entity, char)
    end)
    |> decode_numeric_entities()
  end

  @spec decode_numeric_entities(String.t()) :: String.t()
  defp decode_numeric_entities(text) do
    text
    |> decode_decimal_entities()
    |> decode_hex_entities()
  end

  @spec decode_decimal_entities(String.t()) :: String.t()
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

  @spec decode_hex_entities(String.t()) :: String.t()
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
