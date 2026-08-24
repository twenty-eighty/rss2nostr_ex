defmodule Rss2Nostr.Processing.VideoProbe do
  @moduledoc """
  Fills NIP-92 `imeta` fields for remote audio and video without
  requiring a Blossom upload.

  Uses `HEAD` for size and MIME type, and `ffprobe` when present for
  duration, dimensions, and bitrate. RSS caption values are a fallback.
  A local copy can be probed with `probe_binary/2` after download.
  """

  require Logger

  alias Rss2Nostr.HTTP
  alias Rss2Nostr.Processing.ImageExtractor

  @head_ms 15_000
  @ffprobe_ms 30_000

  @type info :: %{
          optional(:size) => integer(),
          optional(:type) => String.t(),
          optional(:duration) => integer(),
          optional(:dim) => String.t(),
          optional(:bitrate) => integer()
        }

  @doc """
  Probes `url`. `opts` may include `:duration` and `:size` already known
  from the feed so a failed HEAD/ffprobe still produces an imeta.
  """
  @spec probe(String.t(), keyword()) :: info()
  def probe(url, opts \\ []) when is_binary(url) do
    known = known_info(opts)

    known
    |> Map.merge(if(head_enabled?(opts), do: head_info(url), else: %{}))
    |> Map.merge(if(ffprobe_enabled?(opts), do: ffprobe_info(url), else: %{}))
  end

  @doc """
  Probes bytes already on disk (after a download) so article audio does
  not need a second HTTP fetch.
  """
  @spec probe_binary(binary(), keyword()) :: info()
  def probe_binary(data, opts \\ []) when is_binary(data) do
    known =
      opts
      |> Keyword.put(:size, byte_size(data))
      |> known_info()

    if ffprobe_enabled?(opts) do
      ext = opts[:ext] || ".bin"
      ext = if String.starts_with?(ext, "."), do: ext, else: "." <> ext

      path =
        Path.join(
          System.tmp_dir!(),
          "rss2nostr-probe-#{System.unique_integer([:positive])}#{ext}"
        )

      File.write!(path, data)

      try do
        Map.merge(known, ffprobe_info(path))
      after
        File.rm(path)
      end
    else
      known
    end
  end

  @spec ffprobe_enabled?(keyword()) :: boolean()
  defp ffprobe_enabled?(opts) do
    Keyword.get(opts, :ffprobe, Application.get_env(:rss2nostr, :video_ffprobe, true))
  end

  @spec head_enabled?(keyword()) :: boolean()
  defp head_enabled?(opts) do
    Keyword.get(opts, :head, Application.get_env(:rss2nostr, :video_head, true))
  end

  @doc false
  @spec parse_head(map() | list()) :: info()
  def parse_head(headers) do
    %{}
    |> maybe_put(:type, media_mime(HTTP.header(headers, "content-type")))
    |> maybe_put(:size, parse_int(HTTP.header(headers, "content-length")))
  end

  @doc false
  @spec parse_ffprobe(map() | String.t()) :: info()
  def parse_ffprobe(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} -> parse_ffprobe(map)
      {:error, _} -> %{}
    end
  end

  def parse_ffprobe(json) when is_map(json) do
    format = json["format"] || %{}
    streams = json["streams"] || []
    video = Enum.find(streams, &(&1["codec_type"] == "video"))
    audio = Enum.find(streams, &(&1["codec_type"] == "audio"))
    stream = video || audio || %{}

    %{}
    |> maybe_put(:duration, parse_duration(stream["duration"] || format["duration"]))
    |> maybe_put(:size, parse_int(format["size"]))
    |> maybe_put(:bitrate, parse_int(stream["bit_rate"] || format["bit_rate"]))
    |> maybe_put(:dim, dimensions(video || %{}))
  end

  def parse_ffprobe(_), do: %{}

  @spec known_info(keyword()) :: info()
  defp known_info(opts) do
    %{}
    |> maybe_put(:duration, opts[:duration])
    |> maybe_put(:size, opts[:size])
    |> maybe_put(:type, opts[:type])
  end

  @spec head_info(String.t()) :: info()
  defp head_info(url) do
    case HTTP.head(url, receive_timeout: @head_ms, retry: false) do
      {:ok, %{status: status, headers: headers}} when status in 200..399 ->
        parse_head(headers)

      other ->
        Logger.debug("Media HEAD failed for #{url}: #{inspect(other)}")
        %{}
    end
  end

  @spec ffprobe_info(String.t()) :: info()
  defp ffprobe_info(url) do
    case Rss2Nostr.HTTP.SafeURL.validate(url) do
      :ok ->
        do_ffprobe(url)

      {:error, reason} ->
        Logger.debug("ffprobe skipped for #{url}: #{inspect(reason)}")
        %{}
    end
  end

  defp do_ffprobe(url) do
    case System.find_executable("ffprobe") do
      nil ->
        %{}

      bin ->
        args = [
          "-v",
          "error",
          "-print_format",
          "json",
          "-show_format",
          "-show_streams",
          "-probesize",
          "2M",
          "-analyzeduration",
          "2M",
          "--",
          url
        ]

        task = Task.async(fn -> System.cmd(bin, args, stderr_to_stdout: true) end)

        case Task.yield(task, @ffprobe_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, {json, 0}} ->
            parse_ffprobe(json)

          other ->
            Logger.debug("ffprobe failed for #{url}: #{inspect(other)}")
            %{}
        end
    end
  end

  @spec media_mime(String.t() | nil) :: String.t() | nil
  defp media_mime(nil), do: nil

  defp media_mime(value) when is_binary(value) do
    type =
      value
      |> String.split(";", parts: 2)
      |> List.first()
      |> String.trim()
      |> String.downcase()

    cond do
      type in ["video/mpeg", "application/octet-stream", ""] -> nil
      String.starts_with?(type, "video/") or String.starts_with?(type, "audio/") -> type
      true -> nil
    end
  end

  @spec dimensions(map()) :: String.t() | nil
  defp dimensions(%{"width" => w, "height" => h})
       when is_integer(w) and is_integer(h) and w > 0 and h > 0 do
    "#{w}x#{h}"
  end

  defp dimensions(_), do: nil

  @spec parse_duration(String.t() | number() | term()) :: integer() | nil
  defp parse_duration(value) when is_binary(value) do
    case Float.parse(value) do
      {n, _} when n > 0 -> round(n)
      _ -> ImageExtractor.clock_to_seconds(value)
    end
  end

  defp parse_duration(value) when is_number(value) and value > 0, do: round(value)
  defp parse_duration(_), do: nil

  @spec parse_int(integer() | String.t() | term()) :: integer() | nil
  defp parse_int(value) when is_integer(value) and value > 0, do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  @spec maybe_put(info(), atom(), term()) :: info()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
