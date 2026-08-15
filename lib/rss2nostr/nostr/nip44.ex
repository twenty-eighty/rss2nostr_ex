defmodule Rss2Nostr.Nostr.NIP44 do
  @moduledoc """
  NIP-44 v2 encryption used by NIP-37 draft wraps.
  """

  require Logger

  alias Rss2Nostr.Nostr.Keys

  @nip44_script Path.join(:code.priv_dir(:rss2nostr), "nip44.mjs")

  @doc """
  Encrypts plaintext to `recipient_pubkey` using the sender's private key.
  """
  def encrypt(plaintext, private_key, recipient_pubkey)
      when is_binary(plaintext) and byte_size(private_key) == 32 do
    run_nip44("encrypt", private_key, recipient_pubkey, plaintext: plaintext)
  end

  @doc """
  Decrypts a NIP-44 payload produced for this private key and peer pubkey.
  """
  def decrypt(ciphertext, private_key, peer_pubkey)
      when is_binary(ciphertext) and byte_size(private_key) == 32 do
    run_nip44("decrypt", private_key, peer_pubkey, ciphertext: ciphertext)
  end

  defp run_nip44(action, private_key, pubkey, opts) do
    input =
      %{
        action: action,
        privkey: Keys.to_hex(private_key),
        pubkey: pubkey
      }
      |> Map.merge(Map.new(opts))
      |> Jason.encode!()

    tmp_file = Path.join(System.tmp_dir!(), "nip44_#{:rand.uniform(1_000_000)}.json")

    try do
      File.write!(tmp_file, input)

      case System.cmd("node", [@nip44_script],
             cd: Path.dirname(tmp_file),
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
          Logger.error("NIP-44 operation failed: #{error}")
          {:error, :operation_failed}
      end
    after
      File.rm(tmp_file)
    end
  end
end
