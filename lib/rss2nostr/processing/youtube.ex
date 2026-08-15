defmodule Rss2Nostr.Processing.Youtube do
  @moduledoc """
  Resolves YouTube video IDs and replaces generic link labels with the
  video title (from the embed, or YouTube oEmbed).
  """

  require Logger

  alias Rss2Nostr.HTTP

  @generic_labels MapSet.new([
                    "",
                    "watch on youtube",
                    "watch youtube",
                    "youtube",
                    "youtube video",
                    "youtube video player",
                    "watch",
                    "video",
                    "link",
                    "click here",
                    "play",
                    "play on youtube"
                  ])

  @link_pattern ~r/\[([^\]]*)\]\((https?:\/\/(?:www\.)?(?:youtube\.com\/(?:watch\?[^)\s]*v=|embed\/|shorts\/)|youtu\.be\/)([A-Za-z0-9_-]{11})[^)\s]*)\)/i

  @spec video_id(String.t() | nil) :: String.t() | nil
  def video_id(url) when is_binary(url) do
    patterns = [
      ~r/youtube\.com\/embed\/([A-Za-z0-9_-]{11})/,
      ~r/youtube\.com\/shorts\/([A-Za-z0-9_-]{11})/,
      ~r/youtube\.com\/watch\?[^)\s]*v=([A-Za-z0-9_-]{11})/,
      ~r/youtu\.be\/([A-Za-z0-9_-]{11})/
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, url) do
        [_, id] -> id
        _ -> nil
      end
    end)
  end

  def video_id(_), do: nil

  @spec generic_label?(String.t() | nil) :: boolean()
  def generic_label?(text) when is_binary(text) do
    normalized =
      text
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, " ")
      |> String.trim()

    MapSet.member?(@generic_labels, normalized)
  end

  def generic_label?(_), do: true

  @spec meaningful_title(String.t() | nil) :: String.t() | nil
  def meaningful_title(title) when is_binary(title) do
    trimmed = String.trim(title)

    if trimmed != "" and not generic_label?(trimmed) do
      trimmed
    end
  end

  def meaningful_title(_), do: nil

  @doc """
  Replaces generic YouTube markdown labels with the video title.

  Options:
    * `:enabled` — defaults to application env `:enrich_youtube_titles` (true)
    * `:fetch` — `(video_id -> String.t() | nil)` for tests
  """
  @spec enrich_markdown(String.t() | nil, keyword()) :: String.t() | nil
  def enrich_markdown(markdown, opts \\ [])
  def enrich_markdown(nil, _opts), do: nil
  def enrich_markdown("", _opts), do: ""

  def enrich_markdown(markdown, opts) when is_binary(markdown) do
    if Keyword.get(opts, :enabled, enabled?()) do
      fetch = Keyword.get(opts, :fetch, &video_title/1)

      Regex.replace(@link_pattern, markdown, fn full, text, url, id ->
        if generic_label?(text) do
          case fetch.(id) do
            title when is_binary(title) and title != "" ->
              "[#{escape_label(title)}](#{url})"

            _ ->
              full
          end
        else
          full
        end
      end)
    else
      markdown
    end
  end

  @spec video_title(String.t()) :: String.t() | nil
  def video_title(video_id) when is_binary(video_id) do
    case cache_get(video_id) do
      {:ok, title} ->
        title

      :miss ->
        title = fetch_oembed_title(video_id)
        cache_put(video_id, title)
        title
    end
  end

  defp fetch_oembed_title(video_id) do
    watch = "https://www.youtube.com/watch?v=#{video_id}"
    url = "https://www.youtube.com/oembed?url=#{URI.encode_www_form(watch)}&format=json"

    case HTTP.get(url, receive_timeout: 5_000, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"title" => title}} -> meaningful_title(title)
          _ -> nil
        end

      other ->
        Logger.debug("YouTube oEmbed failed for #{video_id}: #{inspect(other)}")
        nil
    end
  rescue
    e ->
      Logger.debug("YouTube oEmbed failed for #{video_id}: #{inspect(e)}")
      nil
  end

  defp escape_label(title) do
    title
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
  end

  defp enabled? do
    Application.get_env(:rss2nostr, :enrich_youtube_titles, true)
  end

  defp cache_get(video_id) do
    ensure_cache()

    case :ets.lookup(__MODULE__, video_id) do
      [{^video_id, title}] -> {:ok, title}
      [] -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache_put(video_id, title) do
    ensure_cache()
    true = :ets.insert(__MODULE__, {video_id, title})
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
