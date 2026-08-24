defmodule Rss2Nostr.Processing.ImageExtractor.Urls do
  @moduledoc false

  require Logger

  @heic_ext ~w(heic heif)
  @substack_cdn_prefix "https://substackcdn.com/image/fetch/f_auto,q_auto:good,fl_progressive:steep/"
  @substack_display_prefix "https://substackcdn.com/image/fetch/f_jpg/"

  @spec normalize(String.t() | nil) :: String.t()
  def normalize(url) when is_binary(url) do
    url
    |> String.trim()
    |> prefix_protocol_relative()
    |> unwrap_encoded_fetch()
  end

  def normalize(nil), do: ""

  @spec display(String.t() | nil) :: String.t()
  def display(url) when is_binary(url) do
    origin = normalize(url)

    cond do
      origin == "" ->
        url

      heic_url?(origin) ->
        substack_display_url(origin) || url

      true ->
        origin
    end
  end

  def display(nil), do: ""

  @spec download_urls(String.t() | nil) :: [String.t()]
  def download_urls(url) when is_binary(url) do
    url = String.trim(url)
    origin = normalize(url)

    [url, origin, substack_cdn_url(origin)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  def download_urls(_), do: []

  @spec valid?(String.t() | nil) :: boolean()
  def valid?(nil), do: false
  def valid?(""), do: false

  def valid?(url) do
    uri = URI.parse(url)

    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
      not tracking_pixel?(url)
  rescue
    e ->
      Logger.debug("Invalid image URL #{inspect(url)}: #{inspect(e)}")
      false
  end

  @doc """
  True for VG Wort / similar 1×1 meter pixels that should never be uploaded.
  """
  @spec tracking_pixel?(String.t() | nil) :: boolean()
  def tracking_pixel?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        host = String.downcase(host)
        host == "vgwort.de" or String.ends_with?(host, ".vgwort.de")

      _ ->
        false
    end
  end

  def tracking_pixel?(_), do: false

  @spec path_ext(String.t()) :: String.t()
  def path_ext(url) when is_binary(url) do
    url
    |> String.trim()
    |> URI.parse()
    |> Map.get(:path, "")
    |> to_string()
    |> Path.extname()
    |> String.downcase()
    |> String.trim_leading(".")
  end

  @spec prefix_protocol_relative(String.t()) :: String.t()
  defp prefix_protocol_relative("//" <> rest), do: "https://" <> rest
  defp prefix_protocol_relative(url), do: url

  @spec substack_cdn_url(String.t()) :: String.t() | nil
  defp substack_cdn_url(origin) when is_binary(origin) and origin != "" do
    if substack_origin?(origin) and not substack_cdn?(origin) do
      @substack_cdn_prefix <> URI.encode(origin, &URI.char_unreserved?/1)
    end
  end

  defp substack_cdn_url(_), do: nil

  @spec substack_display_url(String.t()) :: String.t() | nil
  defp substack_display_url(origin) when is_binary(origin) and origin != "" do
    if substack_origin?(origin) and not substack_cdn?(origin) do
      @substack_display_prefix <> URI.encode(origin, &URI.char_unreserved?/1)
    end
  end

  defp substack_display_url(_), do: nil

  @spec substack_cdn?(String.t()) :: boolean()
  defp substack_cdn?(url) do
    host = url_host(url)
    host == "substackcdn.com" or String.ends_with?(host, ".substackcdn.com")
  end

  @spec substack_origin?(String.t()) :: boolean()
  defp substack_origin?(url) do
    host = url_host(url)

    String.contains?(host, "substack") or
      (String.contains?(host, "amazonaws.com") and String.contains?(url, "/public/images/"))
  end

  @spec url_host(String.t()) :: String.t()
  defp url_host(url) do
    url |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()
  rescue
    _ -> ""
  end

  @spec unwrap_encoded_fetch(String.t()) :: String.t()
  defp unwrap_encoded_fetch(url) do
    case Regex.run(~r/(https?%3A%2F%2F[^\s)]+)/i, url) do
      [_, encoded] ->
        decoded = URI.decode(encoded)
        if valid?(decoded), do: decoded, else: url

      _ ->
        url
    end
  end

  @spec heic_url?(String.t()) :: boolean()
  defp heic_url?(url), do: path_ext(url) in @heic_ext
end
