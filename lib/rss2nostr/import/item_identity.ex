defmodule Rss2Nostr.Import.ItemIdentity do
  @moduledoc """
  Page vs media identity for a feed item.

  Dedup keys come from `<link>` and `<guid>`. Items that only point at
  audio/video (enclosure or media URL) and have no HTML page URL are skipped.
  """

  @media_ext ~w(mp3 mp4 m4a m4v aac ogg opus wav webm mov)

  @type feed_item :: %{
          optional(:link) => String.t() | nil,
          optional(:guid) => String.t() | nil,
          optional(:enclosure_url) => String.t() | nil,
          optional(:enclosure_type) => String.t() | nil,
          optional(atom()) => any()
        }

  @doc """
  True when the item references audio/video and has no HTML page URL.
  """
  @spec media_without_page?(feed_item()) :: boolean()
  def media_without_page?(item) when is_map(item) do
    media_ref?(item) and is_nil(page_url(item))
  end

  @doc """
  First HTML page URL from `<link>`, then `<guid>`.
  """
  @spec page_url(feed_item()) :: String.t() | nil
  def page_url(item) when is_map(item) do
    cond do
      page_url?(field(item, :link)) -> field(item, :link)
      page_url?(field(item, :guid)) -> field(item, :guid)
      true -> nil
    end
  end

  @doc """
  Distinct `<link>` / `<guid>` values used to recognize the same article.
  """
  @spec identity_values(feed_item()) :: [String.t()]
  def identity_values(item) when is_map(item) do
    [field(item, :link), field(item, :guid)]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @doc """
  Lookup keys for an identity value, including http(s) URL variants.
  """
  @spec lookup_keys(String.t() | [String.t()]) :: [String.t()]
  def lookup_keys(values) when is_list(values) do
    values
    |> Enum.flat_map(&lookup_keys/1)
    |> Enum.uniq()
  end

  def lookup_keys(value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      []
    else
      [trimmed | url_variants(trimmed)]
      |> Enum.uniq()
    end
  end

  def lookup_keys(_), do: []

  @doc """
  Canonical form of an http(s) URL for comparison.
  """
  @spec normalize_url(String.t()) :: String.t() | nil
  def normalize_url(url) when is_binary(url) do
    trimmed = String.trim(url)

    cond do
      trimmed == "" ->
        nil

      not http_url?(trimmed) ->
        nil

      true ->
        uri = trimmed |> String.downcase() |> URI.parse()
        host = uri.host && String.replace_prefix(uri.host, "www.", "")
        path = uri.path |> to_string() |> String.trim_trailing("/")

        %URI{scheme: "https", host: host, path: path, query: nil, fragment: nil}
        |> URI.to_string()
    end
  end

  def normalize_url(_), do: nil

  defp media_ref?(item) do
    media_type?(field(item, :enclosure_type)) or
      media_url?(field(item, :enclosure_url)) or
      media_url?(field(item, :guid)) or
      media_url?(field(item, :link))
  end

  defp page_url?(value), do: http_url?(value) and not media_url?(value)

  defp media_type?(type) when is_binary(type) do
    type = String.downcase(type)
    String.starts_with?(type, "audio/") or String.starts_with?(type, "video/")
  end

  defp media_type?(_), do: false

  defp media_url?(url) when is_binary(url) do
    ext =
      url
      |> String.trim()
      |> URI.parse()
      |> Map.get(:path, "")
      |> to_string()
      |> String.downcase()
      |> Path.extname()
      |> String.trim_leading(".")

    ext in @media_ext
  end

  defp media_url?(_), do: false

  defp http_url?(value) when is_binary(value) do
    trimmed = String.trim(value)
    String.starts_with?(trimmed, "http://") or String.starts_with?(trimmed, "https://")
  end

  defp http_url?(_), do: false

  defp url_variants(value) do
    case normalize_url(value) do
      nil ->
        []

      normalized ->
        host = URI.parse(normalized).host

        www =
          if is_binary(host) and host != "" do
            String.replace(normalized, "://#{host}", "://www.#{host}")
          end

        [normalized, normalized <> "/", www]
        |> Enum.reject(&is_nil/1)
    end
  end

  defp field(item, key) do
    Map.get(item, key) || Map.get(item, Atom.to_string(key))
  end
end
