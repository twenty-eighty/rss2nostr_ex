defmodule Rss2Nostr.Import.FeedDiscovery do
  @moduledoc """
  Finds RSS/Atom feeds from a website URL and previews their articles.
  """

  alias Rss2Nostr.Import.{FeedFetcher, FeedParser}

  @feed_link_types [
    "application/rss+xml",
    "application/atom+xml",
    "application/rdf+xml",
    "application/xml",
    "text/xml"
  ]

  @type feed :: %{
          url: String.t(),
          title: String.t() | nil,
          type: String.t() | nil,
          language: String.t() | nil
        }

  @type item :: %{
          guid: String.t() | nil,
          title: String.t() | nil,
          published_at: String.t() | nil,
          link: String.t() | nil
        }

  @type result :: %{
          page_title: String.t() | nil,
          url: String.t(),
          language: String.t() | nil,
          feeds: [feed()],
          items: [item()],
          direct_feed: boolean()
        }

  @spec discover(String.t()) :: {:ok, result()} | {:error, String.t()}
  def discover(url) when is_binary(url) do
    with {:ok, url} <- normalize_url(url),
         {:ok, body} <- FeedFetcher.fetch(url) do
      discover_from_body(url, body)
    end
  end

  def discover(_), do: {:error, "Invalid URL"}

  @doc """
  Interprets a fetched body as a feed or as an HTML page that lists feeds.

  A direct RSS/Atom URL is recognized even when item descriptions contain HTML.
  """
  @spec discover_from_body(String.t(), String.t()) :: {:ok, result()} | {:error, String.t()}
  def discover_from_body(url, body) when is_binary(url) and is_binary(body) do
    cond do
      type = FeedParser.detect_feed_type(body) ->
        # Never run title/language XPath or Floki on the raw body — huge feeds
        # (full content:encoded) make xmerl take minutes.
        {:ok, feed_result(url, body, type)}

      looks_like_html?(body) ->
        discover_from_html(url, body)

      looks_like_feed_url?(url) ->
        {:error, "This looks like a feed URL, but it is not valid RSS or Atom"}

      true ->
        {:error, "No RSS or Atom feeds found at this URL"}
    end
  end

  @doc """
  True when the path looks like an RSS/Atom feed rather than a website.
  """
  @spec looks_like_feed_url?(String.t()) :: boolean()
  def looks_like_feed_url?(url) when is_binary(url) do
    path =
      url
      |> URI.parse()
      |> Map.get(:path)
      |> to_string()
      |> String.downcase()

    String.ends_with?(path, ".xml") or
      String.ends_with?(path, ".rss") or
      String.ends_with?(path, ".atom") or
      String.contains?(path, "/rss") or
      String.contains?(path, "/atom") or
      String.contains?(path, "/feed")
  end

  def looks_like_feed_url?(_), do: false

  @spec preview(String.t(), keyword()) :: {:ok, result()} | {:error, String.t()}
  def preview(url, opts \\ [])

  def preview(url, opts) when is_binary(url) and is_list(opts) do
    with {:ok, url} <- normalize_url(url),
         {:ok, body} <- FeedFetcher.fetch(url, force: Keyword.get(opts, :force, false)),
         type when not is_nil(type) <- FeedParser.detect_feed_type(body) do
      {:ok, feed_result(url, body, type)}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, "Not an RSS or Atom feed"}
    end
  end

  def preview(_, _), do: {:error, "Invalid URL"}

  @spec page_title(String.t()) :: String.t() | nil
  def page_title(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, doc} -> document_title(doc)
      _ -> nil
    end
  end

  @spec feeds_from_html(String.t(), String.t()) :: [feed()]
  def feeds_from_html(html, base_url) when is_binary(html) and is_binary(base_url) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        doc
        |> Floki.find("link")
        |> Enum.flat_map(&feed_from_link(&1, base_url))
        |> Enum.uniq_by(& &1.url)

      _ ->
        []
    end
  end

  @spec normalize_url(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_url(url) when is_binary(url) do
    trimmed = url |> String.trim() |> maybe_add_scheme()

    case URI.parse(trimmed) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, trimmed}

      _ ->
        {:error, "URL must be http or https"}
    end
  end

  def normalize_url(_), do: {:error, "Invalid URL"}

  @spec discover_from_html(String.t(), String.t()) :: {:ok, result()} | {:error, String.t()}
  defp discover_from_html(url, body) do
    page_title = page_title(body)
    feeds = feeds_from_html(body, url)

    case feeds do
      [] ->
        {:error, "No RSS or Atom feeds found on this page"}

      [feed] ->
        case preview(feed.url) do
          {:ok, preview} ->
            type = feed.type || preview_type(preview)

            {:ok,
             %{
               page_title: page_title || preview.page_title,
               url: url,
               language: preview.language,
               feeds: [
                 %{
                   url: feed.url,
                   title: feed.title || preview.page_title,
                   type: type,
                   language: preview.language
                 }
               ],
               items: preview.items,
               direct_feed: false
             }}

          {:error, _} ->
            {:ok,
             %{
               page_title: page_title,
               url: url,
               language: nil,
               feeds: feeds,
               items: [],
               direct_feed: false
             }}
        end

      feeds ->
        {:ok,
         %{
           page_title: page_title,
           url: url,
           language: nil,
           feeds: feeds,
           items: [],
           direct_feed: false
         }}
    end
  end

  @spec feed_result(String.t(), String.t(), String.t()) :: result()
  defp feed_result(url, body, type) do
    # Strip article bodies once, then derive title/language/items from that.
    listing_body = FeedParser.strip_embedded_content(body)

    items =
      case FeedParser.parse(listing_body, type) do
        {:ok, parsed} -> Enum.map(parsed, &preview_item/1)
        {:error, _} -> []
      end

    title = FeedParser.feed_title(listing_body)
    language = FeedParser.feed_language(listing_body)

    %{
      page_title: title,
      url: url,
      language: language,
      feeds: [%{url: url, title: title, type: type, language: language}],
      items: items,
      direct_feed: true
    }
  end

  @spec preview_item(FeedParser.feed_item()) :: item()
  defp preview_item(item) do
    %{
      guid: item.guid || item.link,
      title: item.title,
      published_at: datetime_to_iso(item.published_at),
      link: item.link
    }
  end

  @spec datetime_to_iso(DateTime.t() | nil) :: String.t() | nil
  defp datetime_to_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime_to_iso(_), do: nil

  @spec document_title(Floki.html_tree()) :: String.t() | nil
  defp document_title(doc) do
    og =
      doc
      |> Floki.find("meta[property='og:site_name']")
      |> Floki.attribute("content")
      |> List.first()
      |> blank_to_nil()

    title =
      doc
      |> Floki.find("title")
      |> Floki.text()
      |> String.trim()
      |> blank_to_nil()

    og || title
  end

  @spec feed_from_link(Floki.html_tree(), String.t()) :: [feed()]
  defp feed_from_link(link, base_url) do
    rel = link |> Floki.attribute("rel") |> List.first() || ""
    type = link |> Floki.attribute("type") |> List.first() || ""
    href = link |> Floki.attribute("href") |> List.first()
    title = link |> Floki.attribute("title") |> List.first() |> blank_to_nil()

    rels = rel |> String.downcase() |> String.split(~r/\s+/, trim: true)
    type_lower = String.downcase(type)

    cond do
      not is_binary(href) or href == "" ->
        []

      "alternate" in rels and feed_mime?(type_lower) ->
        case resolve_url(base_url, href) do
          {:ok, url} -> [%{url: url, title: title, type: type_from_mime(type_lower), language: nil}]
          _ -> []
        end

      true ->
        []
    end
  end

  @spec feed_mime?(String.t()) :: boolean()
  defp feed_mime?(type) do
    Enum.any?(@feed_link_types, &String.starts_with?(type, &1))
  end

  @spec type_from_mime(String.t()) :: String.t() | nil
  defp type_from_mime(type) do
    cond do
      String.contains?(type, "atom") -> "atom"
      String.contains?(type, "rss") -> "rss"
      String.contains?(type, "rdf") -> "rss"
      true -> nil
    end
  end

  @spec looks_like_html?(String.t()) :: boolean()
  defp looks_like_html?(body) do
    prefix =
      body
      |> String.trim_leading()
      |> String.slice(0, 800)
      |> String.downcase()

    String.contains?(prefix, "<html") or String.contains?(prefix, "<!doctype html")
  end

  @spec maybe_add_scheme(String.t()) :: String.t()
  defp maybe_add_scheme(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when is_binary(scheme) and scheme != "" ->
        url

      _ ->
        "https://" <> url
    end
  end

  @spec resolve_url(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp resolve_url(base, href) do
    case URI.merge(base, href) |> URI.to_string() |> normalize_url() do
      {:ok, url} -> {:ok, url}
      error -> error
    end
  rescue
    _ -> {:error, "Invalid feed URL"}
  end

  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @spec preview_type(result()) :: String.t() | nil
  defp preview_type(%{feeds: [%{type: type} | _]}), do: type
  defp preview_type(_), do: nil
end
