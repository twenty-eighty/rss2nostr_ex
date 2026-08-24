defmodule Rss2Nostr.Nostr.Keys do
  @moduledoc """
  Handles Nostr key operations including:
  - Key generation
  - Public key derivation
  - Event signing with BIP340 Schnorr signatures (via Node.js nostr-tools)
  """

  require Logger

  alias Rss2Nostr.Nostr.NIP19

  @doc """
  Generates a new random private key.
  Returns a 32-byte binary.
  """
  @spec generate_private_key() :: binary()
  def generate_private_key do
    :crypto.strong_rand_bytes(32)
  end

  @doc """
  Derives the public key from a private key.
  Returns the 32-byte x-only public key (for Nostr/BIP340).
  """
  @spec derive_public_key(binary() | String.t()) :: binary() | {:error, atom()}
  def derive_public_key(private_key)
      when is_binary(private_key) and byte_size(private_key) == 32 do
    case K256.Schnorr.verifying_key_from_signing_key(private_key) do
      {:ok, pubkey} -> pubkey
      {:error, reason} -> {:error, reason}
    end
  end

  def derive_public_key(private_key_hex) when is_binary(private_key_hex) do
    case Base.decode16(private_key_hex, case: :mixed) do
      {:ok, private_key} -> derive_public_key(private_key)
      :error -> {:error, :invalid_hex}
    end
  end

  @doc """
  Signs a Nostr event using Node.js nostr-tools.
  Returns {:ok, %{id: ..., sig: ..., pubkey: ...}} or {:error, reason}
  """
  @spec sign_event(map(), binary()) :: {:ok, map()} | {:error, atom() | String.t()}
  def sign_event(event, private_key)
      when is_binary(private_key) and byte_size(private_key) == 32 do
    input =
      Jason.encode!(%{
        event: %{
          kind: event.kind,
          created_at: event.created_at,
          tags: event.tags,
          content: event.content
        },
        privkey: to_hex(private_key)
      })

    # Use a temp file to avoid shell escaping issues with special characters
    tmp_file = Path.join(System.tmp_dir!(), "nostr_sign_#{:rand.uniform(1_000_000)}.json")
    script = sign_script()

    try do
      File.write!(tmp_file, input)

      case System.cmd("node", [script],
             cd: Path.dirname(script),
             stderr_to_stdout: true,
             env: [{"INPUT_FILE", tmp_file}]
           ) do
        {output, 0} ->
          case Jason.decode(output) do
            {:ok, %{"id" => id, "sig" => sig, "pubkey" => pubkey}} ->
              {:ok, %{id: id, sig: sig, pubkey: pubkey}}

            {:ok, %{"error" => error}} ->
              {:error, error}

            {:error, _} ->
              {:error, :json_decode_failed}
          end

        {error, _code} ->
          Logger.error("Node.js signing failed: #{error}")
          {:error, :signing_failed}
      end
    after
      File.rm(tmp_file)
    end
  end

  @doc """
  Signs a message (event id) with a private key using BIP340 Schnorr signature.
  Note: This uses K256 which has issues. Use sign_event/2 instead for Nostr events.
  Returns a 64-byte signature.
  """
  @spec sign(binary(), binary()) :: {:ok, binary()} | {:error, any()}
  def sign(message, private_key) when byte_size(message) == 32 and byte_size(private_key) == 32 do
    case K256.Schnorr.create_signature(message, private_key) do
      {:ok, signature} when byte_size(signature) == 64 ->
        {:ok, signature}

      {:error, reason} ->
        Logger.error("Schnorr signing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Verifies a BIP340 Schnorr signature over a 32-byte message digest
  (a Nostr event id).
  """
  @spec verify(binary(), binary(), binary()) :: boolean()
  def verify(message, signature, public_key)
      when byte_size(message) == 32 and byte_size(signature) == 64 and byte_size(public_key) == 32 do
    case K256.Schnorr.verify_message_digest(message, signature, public_key) do
      :ok -> true
      {:error, _} -> false
    end
  end

  @doc """
  Computes SHA256 hash of data.
  """
  @spec sha256(binary()) :: binary()
  def sha256(data) when is_binary(data) do
    :crypto.hash(:sha256, data)
  end

  @doc """
  Converts a binary to hex string.
  """
  @spec to_hex(binary()) :: String.t()
  def to_hex(binary) when is_binary(binary) do
    Base.encode16(binary, case: :lower)
  end

  @doc """
  Converts a hex string to binary.
  """
  @spec from_hex(String.t()) :: {:ok, binary()} | {:error, :invalid_hex}
  def from_hex(hex) when is_binary(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_hex}
    end
  end

  @doc """
  Validates that a string is a valid 64-character hex pubkey.
  """
  @spec valid_pubkey?(String.t() | any()) :: boolean()
  def valid_pubkey?(pubkey) when is_binary(pubkey) do
    case Base.decode16(pubkey, case: :mixed) do
      {:ok, bin} when byte_size(bin) == 32 -> true
      _ -> false
    end
  end

  def valid_pubkey?(_), do: false

  @doc """
  Parses a public key from either npub (bech32) or hex format.
  Returns {:ok, lowercase hex} or {:error, reason}.
  """
  @spec parse_public_key(String.t() | any()) :: {:ok, String.t()} | {:error, atom()}
  def parse_public_key(input) when is_binary(input) do
    trimmed = String.trim(input)

    cond do
      String.starts_with?(trimmed, "npub") ->
        case NIP19.decode(trimmed) do
          {:ok, :npub, hex} -> {:ok, String.downcase(hex)}
          _ -> {:error, :invalid_npub}
        end

      String.length(trimmed) == 64 ->
        case from_hex(trimmed) do
          {:ok, bin} when byte_size(bin) == 32 -> {:ok, String.downcase(trimmed)}
          _ -> {:error, :invalid_hex}
        end

      true ->
        {:error, :invalid_format}
    end
  end

  def parse_public_key(_), do: {:error, :invalid_input}

  @doc """
  Parses a comma-separated list of npub or hex public keys.
  Invalid entries are dropped.
  """
  @spec parse_pubkey_list(String.t() | nil | [String.t()]) :: [String.t()]
  def parse_pubkey_list(nil), do: []
  def parse_pubkey_list(""), do: []

  def parse_pubkey_list(list) when is_list(list) do
    list
    |> Enum.flat_map(fn key ->
      case parse_public_key(key) do
        {:ok, hex} -> [hex]
        {:error, _} -> []
      end
    end)
    |> Enum.uniq()
  end

  def parse_pubkey_list(str) when is_binary(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> parse_pubkey_list()
  end

  @doc """
  Parses a private key from either nsec (bech32) or hex format.
  Returns {:ok, 32-byte binary} or {:error, reason}
  """
  @spec parse_private_key(String.t() | any()) :: {:ok, binary()} | {:error, atom()}
  def parse_private_key(input) when is_binary(input) do
    cond do
      String.starts_with?(input, "nsec") ->
        case NIP19.decode(input) do
          {:ok, :nsec, privkey_hex} ->
            from_hex(privkey_hex)

          _ ->
            {:error, :invalid_nsec}
        end

      String.length(input) == 64 ->
        from_hex(input)

      true ->
        {:error, :invalid_format}
    end
  end

  def parse_private_key(_), do: {:error, :invalid_input}

  # Resolve at runtime: compile-time :code.priv_dir/1 bakes the Mix _build path
  # into releases and breaks Docker/prod.
  defp sign_script, do: Path.join(:code.priv_dir(:rss2nostr), "sign_event.mjs")
end
