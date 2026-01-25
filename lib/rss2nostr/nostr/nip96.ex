defmodule Rss2Nostr.Nostr.NIP96 do
  @moduledoc """
  Implements NIP-96 HTTP File Storage Integration.

  Allows uploading images to NIP-96 compatible servers like:
  - nostr.build
  - void.cat
  - nostrcheck.me

  Flow:
  1. Discover server capabilities via /.well-known/nostr/nip96.json
  2. Create NIP-98 authorization event
  3. Upload file with authorization header
  4. Return the uploaded file URL
  """

  require Logger

  alias Rss2Nostr.Nostr.NIP98

  @default_servers [
    "https://nostr.build",
    "https://nostrcheck.me"
  ]

  @type server_info :: %{
          api_url: String.t(),
          download_url: String.t() | nil,
          supported_nips: [integer()],
          tos_url: String.t() | nil,
          content_types: [String.t()],
          plans: map() | nil
        }

  @type upload_result :: %{
          url: String.t(),
          sha256: String.t() | nil,
          size: integer() | nil,
          type: String.t() | nil,
          dimensions: {integer(), integer()} | nil
        }

  @doc """
  Returns the list of default NIP-96 servers.
  """
  def default_servers, do: @default_servers

  @doc """
  Discovers server capabilities by fetching /.well-known/nostr/nip96.json

  Returns {:ok, server_info} or {:error, reason}
  """
  def discover_server(server_url) do
    well_known_url = URI.merge(server_url, "/.well-known/nostr/nip96.json") |> to_string()

    Logger.debug("Discovering NIP-96 server at #{well_known_url}")

    case HTTPoison.get(well_known_url, [], follow_redirect: true, timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        parse_server_info(body, server_url)

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, {:http_error, code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp parse_server_info(body, server_url) do
    case Jason.decode(body) do
      {:ok, json} ->
        api_url = json["api_url"] || "#{server_url}/upload"

        # Make API URL absolute if relative
        api_url =
          if String.starts_with?(api_url, "/") do
            URI.merge(server_url, api_url) |> to_string()
          else
            api_url
          end

        {:ok,
         %{
           api_url: api_url,
           download_url: json["download_url"],
           supported_nips: json["supported_nips"] || [],
           tos_url: json["tos_url"],
           content_types: json["content_types"] || ["image/*"],
           plans: json["plans"]
         }}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  @doc """
  Uploads an image file to a NIP-96 server.

  Options:
  - :private_key - 32-byte binary private key for NIP-98 auth (required)
  - :server - Server URL (default: first available from default_servers)
  - :content_type - MIME type (auto-detected if not provided)
  - :alt - Alt text for the image
  - :expiration - Expiration timestamp (optional)

  Returns {:ok, upload_result} or {:error, reason}
  """
  def upload_file(file_path, opts \\ []) do
    private_key = Keyword.fetch!(opts, :private_key)
    server_url = Keyword.get(opts, :server)

    # Find a working server if not specified
    case get_server_info(server_url) do
      {:ok, server_info} ->
        do_upload(file_path, server_info, private_key, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Uploads image data (binary) to a NIP-96 server.

  Options are the same as upload_file/2.
  """
  def upload_data(data, filename, opts \\ []) do
    private_key = Keyword.fetch!(opts, :private_key)
    server_url = Keyword.get(opts, :server)

    case get_server_info(server_url) do
      {:ok, server_info} ->
        do_upload_data(data, filename, server_info, private_key, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Downloads an image from a URL and uploads it to a NIP-96 server.

  Options are the same as upload_file/2.
  """
  def upload_from_url(image_url, opts \\ []) do
    Logger.info("Downloading image from #{image_url}")

    case HTTPoison.get(image_url, [], follow_redirect: true, timeout: 30_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: data, headers: headers}} ->
        content_type = get_header(headers, "content-type") || "image/jpeg"
        filename = extract_filename(image_url, content_type)

        opts = Keyword.put_new(opts, :content_type, content_type)
        upload_data(data, filename, opts)

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, {:download_failed, code}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:download_failed, reason}}
    end
  end

  # Try to find a working server
  defp get_server_info(nil) do
    Enum.reduce_while(@default_servers, {:error, :no_server_available}, fn server, _acc ->
      case discover_server(server) do
        {:ok, info} -> {:halt, {:ok, info}}
        {:error, _} -> {:cont, {:error, :no_server_available}}
      end
    end)
  end

  defp get_server_info(server_url) do
    discover_server(server_url)
  end

  defp do_upload(file_path, server_info, private_key, opts) do
    case File.read(file_path) do
      {:ok, data} ->
        filename = Path.basename(file_path)
        content_type = Keyword.get(opts, :content_type) || guess_content_type(file_path)
        opts = Keyword.put(opts, :content_type, content_type)
        do_upload_data(data, filename, server_info, private_key, opts)

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  defp do_upload_data(data, filename, server_info, private_key, opts) do
    api_url = server_info.api_url
    content_type = Keyword.get(opts, :content_type, "image/jpeg")
    alt = Keyword.get(opts, :alt)

    # Create NIP-98 authorization
    case NIP98.create_auth(api_url, "POST", private_key, payload_hash: sha256(data)) do
      {:ok, auth_header} ->
        # Build multipart form
        form_data = build_multipart(data, filename, content_type, alt)

        headers = [
          {"Authorization", auth_header},
          {"Content-Type", "multipart/form-data; boundary=#{form_data.boundary}"}
        ]

        Logger.info("Uploading #{filename} to #{api_url}")

        case HTTPoison.post(api_url, form_data.body, headers, timeout: 60_000) do
          {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
            parse_upload_response(body, server_info)

          {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
            Logger.error("Upload failed with status #{code}: #{body}")
            {:error, {:upload_failed, code, body}}

          {:error, %HTTPoison.Error{reason: reason}} ->
            {:error, {:upload_failed, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_upload_response(body, _server_info) do
    case Jason.decode(body) do
      {:ok, %{"status" => "success", "nip94_event" => event}} ->
        # Extract URL from NIP-94 event tags
        url = find_tag_value(event["tags"], "url")
        sha256 = find_tag_value(event["tags"], "x")
        size = find_tag_value(event["tags"], "size")
        mime = find_tag_value(event["tags"], "m")
        dim = find_tag_value(event["tags"], "dim")

        dimensions = parse_dimensions(dim)

        {:ok,
         %{
           url: url,
           sha256: sha256,
           size: size && String.to_integer(size),
           type: mime,
           dimensions: dimensions
         }}

      {:ok, %{"status" => "error", "message" => message}} ->
        {:error, {:server_error, message}}

      {:ok, %{"url" => url}} ->
        # Simple response format
        {:ok, %{url: url, sha256: nil, size: nil, type: nil, dimensions: nil}}

      {:ok, other} ->
        Logger.warning("Unexpected upload response: #{inspect(other)}")
        {:error, :unexpected_response}

      {:error, _} ->
        {:error, :invalid_response}
    end
  end

  defp find_tag_value(tags, name) when is_list(tags) do
    case Enum.find(tags, fn [tag | _] -> tag == name end) do
      [_, value | _] -> value
      _ -> nil
    end
  end

  defp find_tag_value(_, _), do: nil

  defp parse_dimensions(nil), do: nil

  defp parse_dimensions(dim) do
    case String.split(dim, "x") do
      [w, h] -> {String.to_integer(w), String.to_integer(h)}
      _ -> nil
    end
  end

  defp build_multipart(data, filename, content_type, alt) do
    boundary = "----NostrBoundary#{:rand.uniform(1_000_000_000)}"

    parts = [
      # File part
      "--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n",
      "Content-Type: #{content_type}\r\n",
      "\r\n",
      data,
      "\r\n"
    ]

    # Add alt text if provided
    parts =
      if alt do
        parts ++
          [
            "--#{boundary}\r\n",
            "Content-Disposition: form-data; name=\"alt\"\r\n",
            "\r\n",
            alt,
            "\r\n"
          ]
      else
        parts
      end

    # Close boundary
    parts = parts ++ ["--#{boundary}--\r\n"]

    %{
      boundary: boundary,
      body: IO.iodata_to_binary(parts)
    }
  end

  defp sha256(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp guess_content_type(file_path) do
    case Path.extname(file_path) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      _ -> "application/octet-stream"
    end
  end

  defp extract_filename(url, content_type) do
    # Try to extract filename from URL
    path = URI.parse(url).path || ""
    basename = Path.basename(path)

    if basename != "" and String.contains?(basename, ".") do
      basename
    else
      # Generate filename based on content type
      ext =
        case content_type do
          "image/jpeg" -> ".jpg"
          "image/png" -> ".png"
          "image/gif" -> ".gif"
          "image/webp" -> ".webp"
          _ -> ".bin"
        end

      "image_#{System.system_time(:second)}#{ext}"
    end
  end

  defp get_header(headers, name) do
    name_lower = String.downcase(name)

    case Enum.find(headers, fn {k, _v} -> String.downcase(k) == name_lower end) do
      {_, value} -> value
      nil -> nil
    end
  end
end
