defmodule Rss2Nostr.CLI.Commands.Bunker do
  @moduledoc """
  CLI commands for NIP-46 Nostr Connect (Bunker) operations.
  """

  alias Rss2Nostr.CLI.Output
  alias Rss2Nostr.Nostr.{NIP46, Keys}

  @default_relay "wss://relay.nsec.app"

  @doc """
  Generates a new bunker connection URL.
  This URL can be shared with a remote signer to establish a connection.
  """
  def generate(options) do
    relay = Map.get(options, :relay, @default_relay)

    Output.info("Generating NIP-46 connection URL...")
    Output.info("")

    {:ok, url, privkey, secret} = NIP46.generate_connection_url(relay)

    Output.success("Connection URL generated!")
    Output.info("")
    Output.info("URL: #{url}")
    Output.info("")
    Output.info("Share this URL with your signer app (Amber, nsec.app, etc.)")
    Output.info("")
    Output.info("Client details (save these for later use):")
    Output.info("  Private key: #{Keys.to_hex(privkey)}")
    Output.info("  Secret: #{secret}")
  end

  @doc """
  Tests a bunker connection by connecting and getting the public key.
  """
  def test(options) do
    bunker_url = Map.get(options, :url)

    if is_nil(bunker_url) or bunker_url == "" do
      Output.error("Please provide a bunker:// URL with --url")
      return_error()
    end

    Output.info("Testing NIP-46 bunker connection...")
    Output.info("URL: #{bunker_url}")
    Output.info("")

    case NIP46.parse_bunker_url(bunker_url) do
      {:ok, parsed} ->
        Output.info("Parsed successfully:")
        Output.info("  Remote pubkey: #{String.slice(parsed.pubkey, 0, 16)}...")
        Output.info("  Relay: #{parsed.relay}")

        if parsed.secret do
          Output.info("  Secret: #{String.slice(parsed.secret, 0, 8)}...")
        end

        Output.info("")
        Output.info("Connecting to bunker...")

        test_bunker_connection(bunker_url)

      {:error, reason} ->
        Output.error("Invalid bunker URL: #{inspect(reason)}")
    end
  end

  defp test_bunker_connection(bunker_url) do
    case NIP46.start_link(bunker_url: bunker_url) do
      {:ok, pid} ->
        connect_and_get_pubkey(pid)

      {:error, reason} ->
        Output.error("Failed to start bunker client: #{inspect(reason)}")
    end
  end

  defp connect_and_get_pubkey(pid) do
    case NIP46.connect(pid, 30_000) do
      {:ok, "ack"} ->
        Output.success("Connected!")
        Output.info("Getting public key...")
        get_pubkey_and_disconnect(pid)

      {:error, reason} ->
        Output.error("Connection failed: #{inspect(reason)}")
    end
  end

  defp get_pubkey_and_disconnect(pid) do
    case NIP46.get_public_key(pid, 10_000) do
      {:ok, pubkey} ->
        Output.success("Public key: #{pubkey}")
        NIP46.disconnect(pid)

      {:error, reason} ->
        Output.error("Failed to get public key: #{inspect(reason)}")
        NIP46.disconnect(pid)
    end
  end

  @doc """
  Shows information about available bunker signers.
  """
  def info do
    Output.info("NIP-46 Nostr Connect (Bunker) Support")
    Output.info("")
    Output.info("Supported signers:")
    Output.info("  - Amber (Android): https://github.com/greenart7c3/Amber")
    Output.info("  - nsec.app: https://nsec.app")
    Output.info("  - Nostr Signing Device: Hardware signers")
    Output.info("")
    Output.info("Connection URL format:")
    Output.info("  bunker://<signer-pubkey>?relay=<relay>&secret=<secret>")
    Output.info("")
    Output.info("Usage:")
    Output.info("  1. Generate a connection URL: rss2nostr bunker generate")
    Output.info("  2. Scan/paste the URL in your signer app")
    Output.info("  3. Use the bunker URL for export: rss2nostr export --bunker <url>")
  end

  defp return_error, do: :error
end
