defmodule Rss2Nostr.Processing.ImageExtractor.Media do
  @moduledoc false

  alias Rss2Nostr.Processing.ImageExtractor
  alias Rss2Nostr.Processing.ImageExtractor.Urls

  @audio_ext ~w(mp3 m4a aac ogg opus wav)
  @video_ext ~w(mp4 m4v webm mov mkv)

  @spec audio_url?(String.t() | nil) :: boolean()
  def audio_url?(url) when is_binary(url) do
    Urls.path_ext(url) in @audio_ext
  end

  def audio_url?(_), do: false

  @spec video_url?(String.t() | nil) :: boolean()
  def video_url?(url) when is_binary(url) do
    Urls.path_ext(url) in @video_ext
  end

  def video_url?(_), do: false

  @spec extract_audio(String.t() | nil) :: [ImageExtractor.image_info()]
  def extract_audio(content) when is_binary(content) do
    content
    |> extract_markdown_audio()
    |> Enum.map(fn item -> %{item | url: Urls.normalize(item.url)} end)
    |> Enum.uniq_by(& &1.url)
    |> Enum.filter(&Urls.valid?(&1.url))
  end

  def extract_audio(_), do: []

  @spec extract_markdown_audio(String.t() | any()) :: [ImageExtractor.image_info()]
  def extract_markdown_audio(markdown) when is_binary(markdown) do
    markdown
    |> extract_markdown_links()
    |> Enum.filter(&audio_url?(&1.url))
  end

  def extract_markdown_audio(_), do: []

  @spec extract_video(String.t() | nil) :: [ImageExtractor.image_info()]
  def extract_video(content) when is_binary(content) do
    content
    |> extract_markdown_links()
    |> Enum.map(fn item -> %{item | url: Urls.normalize(item.url)} end)
    |> Enum.uniq_by(& &1.url)
    |> Enum.filter(&video_url?(&1.url))
    |> Enum.filter(&Urls.valid?(&1.url))
  end

  def extract_video(_), do: []

  @spec parse_media_caption(String.t() | nil) :: %{duration: integer() | nil, size: integer() | nil}
  def parse_media_caption(caption) when is_binary(caption) do
    tokens = String.split(caption, ~r/\s+/, trim: true)
    {clocks, rest} = Enum.split_with(tokens, &String.contains?(&1, ":"))

    duration =
      clocks
      |> List.first()
      |> clock_to_seconds()

    integers =
      Enum.flat_map(rest, fn token ->
        case Integer.parse(token) do
          {n, ""} when n > 0 -> [n]
          _ -> []
        end
      end)

    {sizes, seconds} = Enum.split_with(integers, &(&1 >= 10_000))

    %{
      duration: duration || List.first(seconds),
      size: List.first(sizes)
    }
  end

  def parse_media_caption(_), do: %{duration: nil, size: nil}

  @spec clock_to_seconds(String.t() | nil) :: integer() | nil
  def clock_to_seconds(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        nil

      String.match?(trimmed, ~r/^\d+$/) ->
        String.to_integer(trimmed)

      String.match?(trimmed, ~r/^\d+:\d{1,2}(:\d{1,2})?$/) ->
        trimmed
        |> String.split(":")
        |> Enum.map(&String.to_integer/1)
        |> Enum.reduce(0, fn part, acc -> acc * 60 + part end)

      true ->
        parse_media_caption(trimmed).duration
    end
  end

  def clock_to_seconds(_), do: nil

  defp extract_markdown_links(markdown) when is_binary(markdown) do
    pattern = ~r/(?<!!)\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)/

    Regex.scan(pattern, markdown)
    |> Enum.map(fn
      [_full, alt, url, title] ->
        %{url: String.trim(url), alt: String.trim(alt), caption: title}

      [_full, alt, url] ->
        %{url: String.trim(url), alt: String.trim(alt), caption: nil}
    end)
  end
end
