defmodule Rss2Nostr.Nostr.Blossom.Client do
  @moduledoc false

  require Logger

  alias Rss2Nostr.HTTP
  alias Rss2Nostr.Nostr.{Blossom, Event, Signer}
  alias Rss2Nostr.Processing.{ImageExtractor, VideoProbe}

  @kind_auth 24242
  @auth_ttl_seconds 600
  @image_download_ms 30_000
  @audio_download_ms 180_000
  @image_upload_ms 60_000
  @audio_upload_ms 180_000
  @mirror_min_bytes 5_000_000

  @spec authorization_header(Event.event()) :: String.t()
  def authorization_header(signed_event) do
    json =
      Jason.encode!(%{
        id: signed_event.id,
        pubkey: signed_event.pubkey,
        created_at: signed_event.created_at,
        kind: signed_event.kind,
        tags: signed_event.tags,
        content: signed_event.content,
        sig: signed_event.sig
      })

    "Nostr " <> Base.encode64(json)
  end

  @spec upload_data(binary(), String.t(), keyword()) ::
          {:ok, Blossom.upload_result()} | {:error, term()}
  def upload_data(data, _filename, opts \\ []) do
    signer = upload_signer_from_opts(opts)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    sha256 = sha256_hex(data)

    server =
      case Keyword.get(opts, :server) do
        nil -> Blossom.configured_server()
        "" -> Blossom.configured_server()
        url -> String.trim_trailing(url, "/")
      end

    if is_nil(server) do
      {:error, :no_upload_endpoint}
    else
      store_blob(server, data, sha256, content_type, signer, opts)
    end
  end

  @spec upload_from_url(String.t(), keyword()) ::
          {:ok, Blossom.upload_result()} | {:error, term()}
  def upload_from_url(image_url, opts \\ []) do
    image_url
    |> ImageExtractor.download_urls()
    |> Enum.reduce_while({:error, {:download_failed, :no_url}}, fn url, _acc ->
      kind = download_kind(url)
      Logger.info("Downloading #{kind} from #{url}")

      case HTTP.get(url, receive_timeout: download_timeout(url), retry: false) do
        {:ok, %{status: 200, body: data, headers: headers}} ->
          content_type = content_type_for(url, headers)

          content_type =
            cond do
              ImageExtractor.audio_url?(url) and not audio_content?(content_type) ->
                "audio/mpeg"

              ImageExtractor.video_url?(url) and not video_content?(content_type) ->
                "video/mp4"

              true ->
                content_type
            end

          filename = extract_filename(url, content_type)

          opts =
            opts
            |> Keyword.put_new(:content_type, content_type)
            |> Keyword.put_new(:source_url, public_http_url(url))

          {:halt, enrich_media_upload(upload_data(data, filename, opts), data, url, content_type)}

        {:ok, %{status: code}} ->
          {:cont, {:error, {:download_failed, code}}}

        {:error, exception} ->
          {:cont, {:error, {:download_failed, exception}}}
      end
    end)
  end

  @spec parse_descriptor(map() | String.t()) ::
          {:ok, Blossom.upload_result()} | {:error, atom()}
  def parse_descriptor(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, json} -> parse_descriptor(json)
      {:error, _} -> {:error, :invalid_response}
    end
  end

  def parse_descriptor(%{"url" => url} = json) when is_binary(url) and url != "" do
    url = familiar_blob_url(url)

    size =
      case json["size"] do
        n when is_integer(n) -> n
        n when is_binary(n) -> String.to_integer(n)
        _ -> nil
      end

    {:ok,
     %{
       url: url,
       sha256: json["sha256"],
       size: size,
       type: json["type"],
       nip94: rewrite_nip94_urls(json["nip94"] || []),
       dimensions: nil
     }}
  end

  def parse_descriptor(_), do: {:error, :unexpected_response}

  @spec guess_content_type(String.t()) :: String.t()
  def guess_content_type(file_path) do
    path =
      case URI.parse(file_path) do
        %URI{path: path} when is_binary(path) and path != "" -> path
        _ -> file_path
      end

    case Path.extname(path) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".mp4" -> "video/mp4"
      ".m4v" -> "video/mp4"
      ".webm" -> "video/webm"
      ".mov" -> "video/quicktime"
      ".mkv" -> "video/x-matroska"
      ".mp3" -> "audio/mpeg"
      ".m4a" -> "audio/mp4"
      ".aac" -> "audio/aac"
      ".ogg" -> "audio/ogg"
      ".opus" -> "audio/opus"
      ".wav" -> "audio/wav"
      _ -> "application/octet-stream"
    end
  end

  @spec format_error(term()) :: String.t()
  def format_error(:no_upload_endpoint), do: "NOSTR_UPLOAD_ENDPOINT is not set"

  def format_error({:upload_failed, code, body}) when is_binary(body) do
    "HTTP #{code}: #{String.slice(body, 0, 200)}"
  end

  def format_error({:download_failed, code}) when is_integer(code), do: "download HTTP #{code}"
  def format_error({:download_failed, other}), do: "download failed: #{inspect(other)}"
  def format_error(reason), do: inspect(reason)

  @spec store_blob(String.t(), binary(), String.t(), String.t(), Signer.signer(), keyword()) :: {:ok, Blossom.upload_result()} | {:error, term()}
  defp store_blob(server, data, sha256, content_type, signer, opts) do
    source_url = opts[:source_url] || opts["source_url"]

    if mirrorable?(source_url, data) do
      case mirror_blob(server, source_url, sha256, byte_size(data), signer) do
        {:ok, _} = ok ->
          ok

        {:error, {:upload_failed, code, _}} when code in [404, 405] ->
          Logger.warning(
            "Blossom /mirror is unavailable (HTTP #{code}); falling back to PUT /upload"
          )

          put_blob(server, data, sha256, content_type, signer)

        {:error, reason} ->
          Logger.error("Blossom mirror failed: #{format_error(reason)}")
          {:error, reason}
      end
    else
      put_blob(server, data, sha256, content_type, signer)
    end
  end

  @spec mirrorable?(String.t(), binary()) :: boolean()
  defp mirrorable?(url, data) when is_binary(url) and url != "" do
    byte_size(data) >= @mirror_min_bytes and String.starts_with?(url, "https://")
  end

  defp mirrorable?(_, _), do: false

  @spec public_http_url(String.t()) :: String.t()
  defp public_http_url(url) when is_binary(url) do
    String.replace_prefix(String.trim(url), "http://", "https://")
  end

  @spec mirror_blob(String.t(), String.t(), String.t(), non_neg_integer(), Signer.signer()) :: {:ok, Blossom.upload_result()} | {:error, term()}
  defp mirror_blob(server, source_url, sha256, byte_size, signer) do
    with {:ok, auth_header} <- create_auth(signer, sha256, server) do
      url = Blossom.mirror_url(server)
      timeout = upload_timeout("audio/mpeg", byte_size)
      body = Jason.encode!(%{url: source_url})

      Logger.info(
        "Mirroring blob #{String.slice(sha256, 0, 12)}… #{format_bytes(byte_size)} " <>
          "from #{source_url} timeout=#{timeout}ms to #{url}"
      )

      case HTTP.put(url,
             headers: [
               {"authorization", auth_header},
               {"content-type", "application/json"}
             ],
             body: body,
             receive_timeout: timeout,
             retry: false
           ) do
        {:ok, %{status: code, body: resp}} when code in [200, 201] ->
          parse_descriptor(resp)

        {:ok, %{status: code, body: resp}} ->
          Logger.error("Blossom mirror failed with status #{code}: #{resp}")
          {:error, {:upload_failed, code, resp}}

        {:error, exception} ->
          {:error, {:upload_failed, exception}}
      end
    end
  end

  @spec put_blob(String.t(), binary(), String.t(), String.t(), Signer.signer()) :: {:ok, Blossom.upload_result()} | {:error, term()}
  defp put_blob(server, data, sha256, content_type, signer) do
    with {:ok, auth_header} <- create_auth(signer, sha256, server) do
      url = Blossom.upload_url(server)
      timeout = upload_timeout(content_type, byte_size(data))

      Logger.info(
        "Uploading blob #{String.slice(sha256, 0, 12)}… #{format_bytes(byte_size(data))} " <>
          "#{normalize_content_type(content_type)} timeout=#{timeout}ms to #{url}"
      )

      case HTTP.put(url,
             headers: [
               {"authorization", auth_header},
               {"content-type", normalize_content_type(content_type)},
               {"content-length", Integer.to_string(byte_size(data))},
               {"x-sha-256", sha256}
             ],
             body: data,
             receive_timeout: timeout,
             retry: false
           ) do
        {:ok, %{status: code, body: body}} when code in [200, 201] ->
          parse_descriptor(body)

        {:ok, %{status: code, body: body}} ->
          Logger.error("Blossom upload failed with status #{code}: #{body}")
          {:error, {:upload_failed, code, body}}

        {:error, exception} ->
          {:error, {:upload_failed, exception}}
      end
    end
  end

  @spec create_auth(Signer.signer(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp create_auth(signer, sha256, server_url) do
    with {:ok, pubkey_hex} <- Signer.pubkey_hex(normalize_signer(signer)) do
      now = System.os_time(:second) - 1
      expiration = now + @auth_ttl_seconds
      host = server_host(server_url)

      tags = [
        ["t", "upload"],
        ["expiration", Integer.to_string(expiration)],
        ["x", sha256]
      ]

      tags =
        if host do
          tags ++ [["server", host]]
        else
          tags
        end

      event = %{
        pubkey: pubkey_hex,
        created_at: now,
        kind: @kind_auth,
        tags: tags,
        content: "Upload Blob"
      }

      case Signer.sign_event(normalize_signer(signer), event) do
        {:ok, signed} -> {:ok, authorization_header(signed)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec upload_signer_from_opts(keyword()) :: Signer.signer()
  defp upload_signer_from_opts(opts) do
    cond do
      Keyword.has_key?(opts, :signer) -> normalize_signer(Keyword.fetch!(opts, :signer))
      Keyword.has_key?(opts, :private_key) -> {:private_key, Keyword.fetch!(opts, :private_key)}
      true -> raise KeyError, key: :signer, term: opts
    end
  end

  @spec normalize_signer(Signer.signer() | binary()) :: Signer.signer()
  defp normalize_signer({:private_key, key}), do: {:private_key, key}
  defp normalize_signer({:bunker, value}), do: {:bunker, value}
  defp normalize_signer(key) when is_binary(key), do: {:private_key, key}

  @spec server_host(String.t() | nil) :: String.t() | nil
  defp server_host(nil), do: nil

  defp server_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> String.downcase(host)
      _ -> nil
    end
  end

  @spec normalize_content_type(term()) :: String.t()
  defp normalize_content_type(value) when is_binary(value) do
    value
    |> String.split(";", parts: 2)
    |> List.first()
    |> String.trim()
    |> case do
      "" -> "application/octet-stream"
      type -> type
    end
  end

  defp normalize_content_type(_), do: "application/octet-stream"

  @spec sha256_hex(binary()) :: String.t()
  defp sha256_hex(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  @spec content_type_for(String.t(), Rss2Nostr.HTTP.headers()) :: String.t()
  defp content_type_for(url, headers) do
    header =
      headers
      |> HTTP.header("content-type")
      |> normalize_content_type()

    cond do
      header not in ["application/octet-stream", "binary/octet-stream"] -> header
      true -> guess_content_type(url)
    end
  end

  @spec download_kind(String.t()) :: String.t()
  defp download_kind(url) do
    cond do
      ImageExtractor.video_url?(url) -> "video"
      ImageExtractor.audio_url?(url) -> "audio"
      true -> "image"
    end
  end

  @spec download_timeout(String.t()) :: non_neg_integer()
  defp download_timeout(url) do
    if ImageExtractor.audio_url?(url) or ImageExtractor.video_url?(url) do
      @audio_download_ms
    else
      @image_download_ms
    end
  end

  @spec upload_timeout(String.t(), non_neg_integer()) :: non_neg_integer()
  defp upload_timeout(content_type, byte_size) when is_integer(byte_size) and byte_size > 0 do
    base =
      if audio_content?(content_type) or video_content?(content_type) do
        @audio_upload_ms
      else
        @image_upload_ms
      end

    sized = @image_upload_ms + div(byte_size, 500_000) * 1_000
    max(base, sized)
  end

  defp upload_timeout(content_type, _byte_size), do: upload_timeout(content_type, 1)

  @spec audio_content?(term()) :: boolean()
  defp audio_content?(type) when is_binary(type) do
    String.starts_with?(normalize_content_type(type), "audio/")
  end

  defp audio_content?(_), do: false

  @spec video_content?(term()) :: boolean()
  defp video_content?(type) when is_binary(type) do
    String.starts_with?(normalize_content_type(type), "video/")
  end

  defp video_content?(_), do: false

  @spec familiar_blob_url(String.t()) :: String.t()
  defp familiar_blob_url(url) when is_binary(url) do
    uri = URI.parse(url)
    path = uri.path || ""
    ext = Path.extname(path)

    if String.downcase(ext) == ".mpga" do
      URI.to_string(%{uri | path: String.replace_suffix(path, ext, ".mp3")})
    else
      url
    end
  end

  @spec rewrite_nip94_urls(list()) :: list()
  defp rewrite_nip94_urls(tags) when is_list(tags) do
    Enum.map(tags, fn
      ["url", url] when is_binary(url) -> ["url", familiar_blob_url(url)]
      other -> other
    end)
  end

  defp rewrite_nip94_urls(_), do: []

  @spec format_bytes(non_neg_integer()) :: String.t()
  defp format_bytes(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}MB"
  defp format_bytes(n) when n >= 1_000, do: "#{div(n, 1_000)}KB"
  defp format_bytes(n), do: "#{n}B"

  @spec enrich_media_upload({:ok, Blossom.upload_result()} | {:error, term()}, binary(), String.t(), String.t()) :: {:ok, Blossom.upload_result()} | {:error, term()}
  defp enrich_media_upload({:ok, result}, data, url, content_type)
       when is_binary(data) do
    if ImageExtractor.audio_url?(url) or ImageExtractor.video_url?(url) do
      ext =
        url
        |> extract_filename(content_type)
        |> Path.extname()

      probed =
        VideoProbe.probe_binary(data,
          ext: ext,
          type: content_type,
          size: byte_size(data)
        )

      {:ok, Map.merge(result, Map.take(probed, [:duration, :bitrate, :dim]))}
    else
      {:ok, result}
    end
  end

  defp enrich_media_upload(other, _data, _url, _content_type), do: other

  @spec extract_filename(String.t(), String.t()) :: String.t()
  defp extract_filename(url, content_type) do
    path = URI.parse(url).path || ""
    basename = Path.basename(path)

    if basename != "" and String.contains?(basename, ".") do
      basename
    else
      ext =
        case content_type do
          "image/jpeg" -> ".jpg"
          "image/png" -> ".png"
          "image/gif" -> ".gif"
          "image/webp" -> ".webp"
          "video/mp4" -> ".mp4"
          "video/webm" -> ".webm"
          "video/quicktime" -> ".mov"
          "audio/mpeg" -> ".mp3"
          "audio/mp4" -> ".m4a"
          "audio/aac" -> ".aac"
          "audio/ogg" -> ".ogg"
          "audio/opus" -> ".opus"
          "audio/wav" -> ".wav"
          _ -> ".bin"
        end

      prefix = if String.starts_with?(content_type, "audio/"), do: "audio", else: "image"
      "#{prefix}_#{System.system_time(:second)}#{ext}"
    end
  end
end
