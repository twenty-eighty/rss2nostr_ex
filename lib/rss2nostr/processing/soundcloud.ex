defmodule Rss2Nostr.Processing.Soundcloud do
  @moduledoc """
  SoundCloud oEmbed artwork for articles that have no featured image.

  Resolves `thumbnail_url` for a track permalink. Results (including
  misses) are cached so compose/import do not hammer oEmbed.
  """

  require Logger

  alias Rss2Nostr.HTTP

  @spec artwork_url(String.t() | nil, keyword()) :: String.t() | nil
  def artwork_url(permalink, opts \\ [])

  def artwork_url(permalink, opts) when is_binary(permalink) and permalink != "" do
    if Keyword.get(opts, :enabled, enabled?()) do
      case Keyword.get(opts, :fetch) do
        fun when is_function(fun, 1) ->
          fun.(permalink)

        _ ->
          case cache_get(permalink) do
            {:ok, url} ->
              url

            :miss ->
              url = fetch_oembed_artwork(permalink)
              cache_put(permalink, url)
              url
          end
      end
    end
  end

  def artwork_url(_, _), do: nil

  defp fetch_oembed_artwork(permalink) do
    url =
      "https://soundcloud.com/oembed?format=json&url=#{URI.encode_www_form(permalink)}"

    case HTTP.get(url, receive_timeout: 5_000, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        parse_artwork(body)

      other ->
        Logger.debug("SoundCloud oEmbed failed for #{permalink}: #{inspect(other)}")
        nil
    end
  rescue
    e ->
      Logger.debug("SoundCloud oEmbed failed for #{permalink}: #{inspect(e)}")
      nil
  end

  defp parse_artwork(%{"thumbnail_url" => url}), do: safe_image_url(url)

  defp parse_artwork(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> parse_artwork(data)
      _ -> nil
    end
  end

  defp parse_artwork(_), do: nil

  defp safe_image_url(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      String.trim(url)
    end
  rescue
    _ -> nil
  end

  defp safe_image_url(_), do: nil

  defp enabled? do
    Application.get_env(:rss2nostr, :fetch_soundcloud_artwork, true)
  end

  defp cache_get(permalink) do
    ensure_cache()

    case :ets.lookup(__MODULE__, permalink) do
      [{^permalink, url}] -> {:ok, url}
      [] -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache_put(permalink, url) do
    ensure_cache()
    true = :ets.insert(__MODULE__, {permalink, url})
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp ensure_cache do
    case :ets.whereis(__MODULE__) do
      :undefined ->
        :ets.new(__MODULE__, [:named_table, :public, :set, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end
end
