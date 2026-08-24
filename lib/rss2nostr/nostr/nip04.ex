defmodule Rss2Nostr.Nostr.NIP04 do
  @moduledoc """
  Implements NIP-04 encrypted direct messages.

  Uses ECDH shared secret and AES-256-CBC for encryption.
  This is the encryption method used by NIP-46 Nostr Connect.
  """

  require Logger

  alias Rss2Nostr.Nostr.Keys

  @doc """
  Encrypts a message for a recipient using NIP-04.

  Parameters:
  - plaintext: The message to encrypt
  - private_key: Sender's 32-byte private key binary
  - recipient_pubkey: Recipient's public key as hex string

  Returns {:ok, ciphertext} or {:error, reason}
  """
  def encrypt(plaintext, private_key, recipient_pubkey)
      when is_binary(plaintext) and byte_size(private_key) == 32 do
    run_nip04("encrypt", private_key, recipient_pubkey, plaintext: plaintext)
  end

  @doc """
  Decrypts a NIP-04 encrypted message.

  Parameters:
  - ciphertext: The encrypted message (base64 with IV)
  - private_key: Recipient's 32-byte private key binary
  - sender_pubkey: Sender's public key as hex string

  Returns {:ok, plaintext} or {:error, reason}
  """
  def decrypt(ciphertext, private_key, sender_pubkey)
      when is_binary(ciphertext) and byte_size(private_key) == 32 do
    run_nip04("decrypt", private_key, sender_pubkey, ciphertext: ciphertext)
  end

  defp run_nip04(action, private_key, pubkey, opts) do
    input =
      %{
        action: action,
        privkey: Keys.to_hex(private_key),
        pubkey: pubkey
      }
      |> Map.merge(Map.new(opts))
      |> Jason.encode!()

    tmp_file = Path.join(System.tmp_dir!(), "nip04_#{:rand.uniform(1_000_000)}.json")
    script = nip04_script()

    try do
      File.write!(tmp_file, input)

      case System.cmd("node", [script],
             cd: Path.dirname(script),
             stderr_to_stdout: true,
             env: [{"INPUT_FILE", tmp_file}]
           ) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, %{"result" => result}} ->
              {:ok, result}

            {:ok, %{"error" => error}} ->
              {:error, error}

            {:error, _} ->
              {:error, :json_decode_failed}
          end

        {error, _code} ->
          Logger.error("NIP-04 operation failed: #{error}")
          {:error, :operation_failed}
      end
    after
      File.rm(tmp_file)
    end
  end

  # Resolve at runtime: compile-time :code.priv_dir/1 bakes the Mix _build path
  # into releases and breaks Docker/prod.
  defp nip04_script, do: Path.join(:code.priv_dir(:rss2nostr), "nip04.mjs")
end
