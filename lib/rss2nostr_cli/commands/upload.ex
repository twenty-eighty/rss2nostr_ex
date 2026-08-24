defmodule Rss2Nostr.CLI.Commands.Upload do
  @moduledoc """
  CLI command for uploading images to Blossom servers.
  """

  alias Rss2Nostr.CLI.Output
  alias Rss2Nostr.Nostr.{Blossom, NIP19, Keys}

  @spec run(map()) :: :ok
  def run(options) do
    file_or_url = Map.get(options, :file)
    nsec = Map.get(options, :nsec)
    server = Map.get(options, :server)
    alt = Map.get(options, :alt)

    Output.info("Uploading image to Blossom...")

    case get_private_key(nsec) do
      {:ok, private_key, pubkey_hex} ->
        Output.info("  Using pubkey: #{String.slice(pubkey_hex, 0, 8)}...")

        if server do
          Output.info("  Server: #{server}")
        else
          case Blossom.configured_server() do
            nil -> Output.info("  Server: auto-detect")
            endpoint -> Output.info("  Server: #{endpoint}")
          end
        end

        upload_opts = [private_key: private_key]
        upload_opts = if server, do: Keyword.put(upload_opts, :server, server), else: upload_opts
        upload_opts = if alt, do: Keyword.put(upload_opts, :alt, alt), else: upload_opts

        result =
          cond do
            String.starts_with?(file_or_url || "", "http://") or
                String.starts_with?(file_or_url || "", "https://") ->
              Output.info("  Downloading from URL...")
              Blossom.upload_from_url(file_or_url, upload_opts)

            file_or_url && File.exists?(file_or_url) ->
              Output.info("  Uploading local file...")
              Blossom.upload_file(file_or_url, upload_opts)

            file_or_url ->
              {:error, "File not found: #{file_or_url}"}

            true ->
              {:error, "No file or URL specified"}
          end

        show_upload_result(result)

      {:error, reason} ->
        Output.error("Failed to get private key: #{reason}")
    end
  end

  @doc """
  Lists configured Blossom servers and whether they respond.
  """
  @spec list_servers() :: :ok
  def list_servers do
    servers = Blossom.servers()

    if servers == [] do
      Output.error("No Blossom server configured. Set NOSTR_UPLOAD_ENDPOINT.")
    else
      Output.info("Checking Blossom server...")
      Output.info("")
      Enum.each(servers, &check_server/1)
    end
  end

  @spec show_upload_result({:ok, map()} | {:error, term()}) :: :ok
  defp show_upload_result({:ok, upload_result}) do
    Output.success("\nUpload successful!")
    Output.info("  URL: #{upload_result.url}")
    if upload_result.sha256, do: Output.info("  SHA256: #{upload_result.sha256}")
    if upload_result.size, do: Output.info("  Size: #{format_size(upload_result.size)}")
    if upload_result.type, do: Output.info("  Type: #{upload_result.type}")

    if upload_result.dimensions do
      {w, h} = upload_result.dimensions
      Output.info("  Dimensions: #{w}x#{h}")
    end
  end

  defp show_upload_result({:error, reason}) do
    Output.error("Upload failed: #{inspect(reason)}")
  end

  @spec check_server(String.t()) :: :ok
  defp check_server(server) do
    case Blossom.probe_server(server) do
      {:ok, status} ->
        Output.success("✓ #{server} (HTTP #{status})")

      {:error, reason} ->
        Output.error("✗ #{server} - #{inspect(reason)}")
    end

    Output.info("")
  end

  @spec get_private_key(String.t() | nil) :: {:ok, binary(), String.t()} | {:error, atom()}
  defp get_private_key(nil) do
    case System.get_env("NOSTR_NSEC") do
      nil ->
        Output.error("No private key provided.")
        Output.info("  Use --nsec flag or set NOSTR_NSEC environment variable")
        {:error, :no_key}

      nsec ->
        decode_nsec(nsec)
    end
  end

  defp get_private_key(nsec), do: decode_nsec(nsec)

  @spec decode_nsec(String.t()) :: {:ok, binary(), String.t()} | {:error, atom()}
  defp decode_nsec(nsec) do
    cond do
      String.starts_with?(nsec, "nsec") ->
        case NIP19.decode(nsec) do
          {:ok, :nsec, privkey_hex} ->
            {:ok, privkey_bin} = Keys.from_hex(privkey_hex)
            pubkey_bin = Keys.derive_public_key(privkey_bin)
            {:ok, privkey_bin, Keys.to_hex(pubkey_bin)}

          _ ->
            {:error, :invalid_nsec}
        end

      String.length(nsec) == 64 ->
        case Keys.from_hex(nsec) do
          {:ok, privkey_bin} ->
            pubkey_bin = Keys.derive_public_key(privkey_bin)
            {:ok, privkey_bin, Keys.to_hex(pubkey_bin)}

          _ ->
            {:error, :invalid_hex}
        end

      true ->
        {:error, :invalid_format}
    end
  end

  @spec format_size(number()) :: String.t()
  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024, 2)} MB"
end
