defmodule Rss2Nostr.Nostr.NIP44 do
  @moduledoc """
  NIP-44 v2 encryption used by NIP-37 draft wraps.
  """

  require Logger

  alias Rss2Nostr.Nostr.{Keys, NodeRunner}

  @doc """
  Encrypts plaintext to `recipient_pubkey` using the sender's private key.
  """
  @spec encrypt(String.t(), binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def encrypt(plaintext, private_key, recipient_pubkey)
      when is_binary(plaintext) and byte_size(private_key) == 32 do
    run_nip44("encrypt", private_key, recipient_pubkey, plaintext: plaintext)
  end

  @doc """
  Decrypts a NIP-44 payload produced for this private key and peer pubkey.
  """
  @spec decrypt(String.t(), binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def decrypt(ciphertext, private_key, peer_pubkey)
      when is_binary(ciphertext) and byte_size(private_key) == 32 do
    run_nip44("decrypt", private_key, peer_pubkey, ciphertext: ciphertext)
  end

  # Resolve at runtime: compile-time :code.priv_dir/1 bakes the Mix _build path
  # into releases and breaks Docker/prod.
  @spec nip44_script() :: String.t()
  defp nip44_script, do: Path.join(:code.priv_dir(:rss2nostr), "nip44.mjs")

  @spec run_nip44(String.t(), binary(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defp run_nip44(action, private_key, pubkey, opts) do
    input =
      %{
        action: action,
        privkey: Keys.to_hex(private_key),
        pubkey: pubkey
      }
      |> Map.merge(Map.new(opts))
      |> Jason.encode!()

    case NodeRunner.run(nip44_script(), input) do
      {:ok, output} ->
        case Jason.decode(output) do
          {:ok, %{"result" => result}} ->
            {:ok, result}

          {:ok, %{"error" => error}} ->
            {:error, error}

          {:error, _} ->
            {:error, :json_decode_failed}
        end

      {:error, error} ->
        Logger.error("NIP-44 operation failed: #{error}")
        {:error, :operation_failed}
    end
  end
end
