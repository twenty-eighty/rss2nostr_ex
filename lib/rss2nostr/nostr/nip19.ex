defmodule Rss2Nostr.Nostr.NIP19 do
  @moduledoc """
  Implements NIP-19 for encoding Nostr identifiers in Bech32 format.

  Supports:
  - npub: Public keys
  - nsec: Private keys
  - note: Event IDs
  - naddr: Parameterized replaceable events (NIP-23 articles)
  - nevent: Event references with relay hints
  - nprofile: Profile references with relay hints
  """

  # Human-readable prefixes
  @npub_hrp "npub"
  @nsec_hrp "nsec"
  @note_hrp "note"
  @naddr_hrp "naddr"
  @nevent_hrp "nevent"
  @nprofile_hrp "nprofile"

  # TLV types
  @tlv_special 0
  @tlv_relay 1
  @tlv_author 2
  @tlv_kind 3

  @doc """
  Encodes a public key as npub.
  """
  @spec encode_npub(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def encode_npub(pubkey_hex) when is_binary(pubkey_hex) do
    pubkey_hex = String.downcase(pubkey_hex)

    case Base.decode16(pubkey_hex, case: :lower) do
      {:ok, pubkey_bin} when byte_size(pubkey_bin) == 32 ->
        encode_bech32(@npub_hrp, pubkey_bin)

      _ ->
        {:error, :invalid_pubkey}
    end
  end

  @doc """
  Encodes a private key as nsec.
  """
  @spec encode_nsec(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def encode_nsec(privkey_hex) when is_binary(privkey_hex) do
    privkey_hex = String.downcase(privkey_hex)

    case Base.decode16(privkey_hex, case: :lower) do
      {:ok, privkey_bin} when byte_size(privkey_bin) == 32 ->
        encode_bech32(@nsec_hrp, privkey_bin)

      _ ->
        {:error, :invalid_privkey}
    end
  end

  @doc """
  Encodes an event ID as note.
  """
  @spec encode_note(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def encode_note(event_id_hex) when is_binary(event_id_hex) do
    event_id_hex = String.downcase(event_id_hex)

    case Base.decode16(event_id_hex, case: :lower) do
      {:ok, event_id_bin} when byte_size(event_id_bin) == 32 ->
        encode_bech32(@note_hrp, event_id_bin)

      _ ->
        {:error, :invalid_event_id}
    end
  end

  @doc """
  Encodes a NIP-23 article reference as naddr.

  Parameters:
  - kind: Event kind (30023 for long-form)
  - pubkey_hex: Author's public key
  - identifier: The 'd' tag value
  - relays: Optional list of relay URLs
  """
  @spec encode_naddr(integer() | String.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, String.t()} | {:error, atom()}
  def encode_naddr(kind, pubkey_hex, identifier, relays \\ []) do
    pubkey_hex = String.downcase(pubkey_hex)

    case Base.decode16(pubkey_hex, case: :lower) do
      {:ok, pubkey_bin} when byte_size(pubkey_bin) == 32 ->
        # Build TLV data (order: identifier, relays, author, kind)
        id_bin = to_string(identifier)
        tlv_data = <<@tlv_special, byte_size(id_bin)>> <> id_bin

        # Add relays
        tlv_data =
          Enum.reduce(relays, tlv_data, fn relay, acc ->
            relay_str = to_string(relay)
            acc <> <<@tlv_relay, byte_size(relay_str)>> <> relay_str
          end)

        # Add author (pubkey)
        tlv_data = tlv_data <> <<@tlv_author, 32>> <> pubkey_bin

        # Add kind (32-bit big-endian)
        kind_int = if is_integer(kind), do: kind, else: String.to_integer(to_string(kind))
        tlv_data = tlv_data <> <<@tlv_kind, 4, kind_int::unsigned-big-integer-size(32)>>

        encode_bech32(@naddr_hrp, tlv_data)

      _ ->
        {:error, :invalid_pubkey}
    end
  end

  @doc """
  Encodes an event reference as nevent with optional relay hints.
  """
  @spec encode_nevent(String.t(), [String.t()], String.t() | nil) ::
          {:ok, String.t()} | {:error, atom()}
  def encode_nevent(event_id_hex, relays \\ [], author_pubkey \\ nil) do
    event_id_hex = String.downcase(event_id_hex)

    case Base.decode16(event_id_hex, case: :lower) do
      {:ok, event_id_bin} when byte_size(event_id_bin) == 32 ->
        # Build TLV data
        tlv_data = <<@tlv_special, 32>> <> event_id_bin

        # Add relays
        tlv_data =
          Enum.reduce(relays, tlv_data, fn relay, acc ->
            relay_str = to_string(relay)
            acc <> <<@tlv_relay, byte_size(relay_str)>> <> relay_str
          end)

        tlv_data = maybe_add_author(tlv_data, author_pubkey)

        encode_bech32(@nevent_hrp, tlv_data)

      _ ->
        {:error, :invalid_event_id}
    end
  end

  @doc """
  Encodes a profile reference as nprofile with optional relay hints.
  """
  @spec encode_nprofile(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, atom()}
  def encode_nprofile(pubkey_hex, relays \\ []) do
    pubkey_hex = String.downcase(pubkey_hex)

    case Base.decode16(pubkey_hex, case: :lower) do
      {:ok, pubkey_bin} when byte_size(pubkey_bin) == 32 ->
        # Build TLV data
        tlv_data = <<@tlv_special, 32>> <> pubkey_bin

        # Add relays
        tlv_data =
          Enum.reduce(relays, tlv_data, fn relay, acc ->
            relay_str = to_string(relay)
            acc <> <<@tlv_relay, byte_size(relay_str)>> <> relay_str
          end)

        encode_bech32(@nprofile_hrp, tlv_data)

      _ ->
        {:error, :invalid_pubkey}
    end
  end

  @doc """
  Decodes a NIP-19 encoded string.
  Returns {:ok, type, data} or {:error, reason}.
  """
  @spec decode(String.t()) :: {:ok, atom(), any()} | {:error, any()}
  def decode(encoded) when is_binary(encoded) do
    case Bech32.decode(encoded) do
      {:ok, hrp, data} ->
        # Bech32 library returns data already as 8-bit binary
        decode_by_hrp(hrp, data)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Decodes based on HRP type
  defp decode_by_hrp(@npub_hrp, data) when byte_size(data) >= 32 do
    pubkey = binary_part(data, 0, 32)
    {:ok, :npub, Base.encode16(pubkey, case: :lower)}
  end

  defp decode_by_hrp(@nsec_hrp, data) when byte_size(data) >= 32 do
    privkey = binary_part(data, 0, 32)
    {:ok, :nsec, Base.encode16(privkey, case: :lower)}
  end

  defp decode_by_hrp(@note_hrp, data) when byte_size(data) >= 32 do
    event_id = binary_part(data, 0, 32)
    {:ok, :note, Base.encode16(event_id, case: :lower)}
  end

  defp decode_by_hrp(@nprofile_hrp, data) do
    case extract_tlv_pubkey_and_relays(data) do
      {:ok, pubkey, relays} ->
        {:ok, :nprofile, %{pubkey: pubkey, relays: relays}}

      error ->
        error
    end
  end

  defp decode_by_hrp(@nevent_hrp, data) do
    case extract_tlv_event_data(data) do
      {:ok, event_id, author, relays} ->
        {:ok, :nevent, %{event_id: event_id, author: author, relays: relays}}

      error ->
        error
    end
  end

  defp decode_by_hrp(@naddr_hrp, data) do
    case extract_tlv_naddr_data(data) do
      {:ok, kind, pubkey, identifier, relays} ->
        {:ok, :naddr, %{kind: kind, pubkey: pubkey, identifier: identifier, relays: relays}}

      error ->
        error
    end
  end

  defp decode_by_hrp(hrp, _data) do
    {:error, {:unsupported_hrp, hrp}}
  end

  defp maybe_add_author(tlv_data, nil), do: tlv_data

  defp maybe_add_author(tlv_data, author_pubkey) do
    case Base.decode16(String.downcase(author_pubkey), case: :lower) do
      {:ok, author_bin} when byte_size(author_bin) == 32 ->
        tlv_data <> <<@tlv_author, 32>> <> author_bin

      _ ->
        tlv_data
    end
  end

  # TLV extraction helpers
  defp extract_tlv_pubkey_and_relays(<<@tlv_special, 32, pubkey::binary-size(32), rest::binary>>) do
    relays = extract_relays(rest)
    {:ok, Base.encode16(pubkey, case: :lower), relays}
  end

  defp extract_tlv_pubkey_and_relays(_), do: {:error, :invalid_tlv}

  defp extract_tlv_event_data(<<@tlv_special, 32, event_id::binary-size(32), rest::binary>>) do
    {author, relays} = extract_author_and_relays(rest)
    {:ok, Base.encode16(event_id, case: :lower), author, relays}
  end

  defp extract_tlv_event_data(_), do: {:error, :invalid_tlv}

  defp extract_tlv_naddr_data(data) do
    case extract_naddr_fields(data, nil, nil, nil, []) do
      {identifier, pubkey, kind, relays}
      when identifier != nil and pubkey != nil and kind != nil ->
        {:ok, kind, pubkey, identifier, relays}

      _ ->
        {:error, :incomplete_naddr}
    end
  end

  defp extract_naddr_fields(<<>>, id, pubkey, kind, relays), do: {id, pubkey, kind, relays}

  defp extract_naddr_fields(<<type, len, rest::binary>>, id, pubkey, kind, relays) do
    if byte_size(rest) >= len do
      value = binary_part(rest, 0, len)
      remaining = binary_part(rest, len, byte_size(rest) - len)

      case type do
        @tlv_special ->
          extract_naddr_fields(remaining, to_string(value), pubkey, kind, relays)

        @tlv_relay ->
          extract_naddr_fields(remaining, id, pubkey, kind, [to_string(value) | relays])

        @tlv_author when len == 32 ->
          extract_naddr_fields(remaining, id, Base.encode16(value, case: :lower), kind, relays)

        @tlv_kind when len == 4 ->
          <<kind_int::unsigned-big-integer-size(32)>> = value
          extract_naddr_fields(remaining, id, pubkey, kind_int, relays)

        _ ->
          extract_naddr_fields(remaining, id, pubkey, kind, relays)
      end
    else
      {id, pubkey, kind, relays}
    end
  end

  defp extract_naddr_fields(_, id, pubkey, kind, relays), do: {id, pubkey, kind, relays}

  defp extract_relays(<<@tlv_relay, len, rest::binary>>) when byte_size(rest) >= len do
    relay = binary_part(rest, 0, len)
    remaining = binary_part(rest, len, byte_size(rest) - len)
    [to_string(relay) | extract_relays(remaining)]
  end

  defp extract_relays(_), do: []

  defp extract_author_and_relays(data) do
    extract_author_and_relays(data, nil, [])
  end

  defp extract_author_and_relays(<<>>, author, relays), do: {author, relays}

  defp extract_author_and_relays(<<type, len, rest::binary>>, author, relays) do
    if byte_size(rest) >= len do
      value = binary_part(rest, 0, len)
      remaining = binary_part(rest, len, byte_size(rest) - len)

      case type do
        @tlv_author when len == 32 ->
          extract_author_and_relays(remaining, Base.encode16(value, case: :lower), relays)

        @tlv_relay ->
          extract_author_and_relays(remaining, author, [to_string(value) | relays])

        _ ->
          extract_author_and_relays(remaining, author, relays)
      end
    else
      {author, relays}
    end
  end

  defp extract_author_and_relays(_, author, relays), do: {author, relays}

  # Bech32 encoding helper
  defp encode_bech32(hrp, data) do
    # Convert 8-bit data to 5-bit
    pad = rem(bit_size(data), 5) != 0
    data_5bit = Bech32.convertbits(data, 8, 5, pad)
    encode_bech32_5bit(hrp, data_5bit)
  end

  defp encode_bech32_5bit(hrp, data_5bit) do
    encoded = Bech32.encode_from_5bit(hrp, data_5bit)
    {:ok, encoded}
  end
end
