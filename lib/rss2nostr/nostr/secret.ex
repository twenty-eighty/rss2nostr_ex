defmodule Rss2Nostr.Nostr.Secret do
  @moduledoc """
  Encrypts source signing keys at rest using the admin session secret.
  """

  alias Rss2Nostr.Web.Auth

  @aad "rss2nostr-nsec"

  @spec encrypt(String.t()) :: String.t()
  def encrypt(plaintext) when is_binary(plaintext) do
    iv = :crypto.strong_rand_bytes(12)
    key = encryption_key()
    {cipher, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, 16, true)
    Base.encode64(iv <> tag <> cipher)
  end

  @spec decrypt(String.t() | nil) :: {:ok, String.t()} | {:error, atom()}
  def decrypt(ciphertext) when is_binary(ciphertext) and ciphertext != "" do
    with {:ok, raw} <- Base.decode64(ciphertext),
         {:ok, plaintext} <- open(raw) do
      {:ok, plaintext}
    else
      :error -> {:error, :decrypt_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  def decrypt(_), do: {:error, :decrypt_failed}

  @spec open(binary()) :: {:ok, String.t()} | {:error, atom()}
  defp open(<<iv::binary-12, tag::binary-16, cipher::binary>>) do
    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           encryption_key(),
           iv,
           cipher,
           @aad,
           tag,
           false
         ) do
      :error -> {:error, :decrypt_failed}
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
    end
  end

  defp open(_), do: {:error, :decrypt_failed}

  @spec encryption_key() :: binary()
  defp encryption_key do
    :crypto.hash(:sha256, Auth.secret_key_base())
  end
end
