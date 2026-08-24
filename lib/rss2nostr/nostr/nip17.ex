defmodule Rss2Nostr.Nostr.NIP17 do
  @moduledoc """
  NIP-17 private DMs: an unsigned kind 14 rumor, NIP-44-sealed (kind 13),
  then gift-wrapped (kind 1059) to the recipient.
  """

  alias Rss2Nostr.Nostr.{Event, Keys, NIP44}

  @kind_dm 14
  @kind_seal 13
  @kind_gift_wrap 1059

  @spec wrap(String.t(), binary(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def wrap(plaintext, sender_key, recipient_hex, opts \\ [])
      when is_binary(plaintext) and byte_size(sender_key) == 32 do
    recipient = String.downcase(recipient_hex)
    sender_pub = sender_key |> Keys.derive_public_key() |> Keys.to_hex()
    created_at = Keyword.get(opts, :created_at, System.os_time(:second))
    subject = Keyword.get(opts, :subject)

    rumor = rumor(sender_pub, recipient, plaintext, created_at, subject)

    with {:ok, rumor_json} <- Jason.encode(rumor_payload(rumor)),
         {:ok, sealed_content} <- NIP44.encrypt(rumor_json, sender_key, recipient),
         seal <- stamp_created_at(Event.build_event(sender_pub, @kind_seal, [], sealed_content)),
         {:ok, signed_seal} <- Event.sign_event(seal, sender_key),
         {:ok, wrap} <- gift_wrap(signed_seal, recipient) do
      {:ok, wrap}
    end
  end

  @spec unwrap(map(), binary()) :: {:ok, map()} | {:error, term()}
  def unwrap(wrap, recipient_key) when is_map(wrap) and byte_size(recipient_key) == 32 do
    with {:ok, seal_json} <-
           NIP44.decrypt(field(wrap, :content), recipient_key, field(wrap, :pubkey)),
         {:ok, seal} <- Jason.decode(seal_json),
         {:ok, rumor_json} <- NIP44.decrypt(seal["content"], recipient_key, seal["pubkey"]),
         {:ok, rumor} <- Jason.decode(rumor_json) do
      {:ok, rumor}
    end
  end

  @spec rumor(String.t(), String.t(), String.t(), integer(), String.t() | nil) :: map()
  defp rumor(sender_pub, recipient, plaintext, created_at, subject) do
    tags = [["p", recipient]]
    tags = if subject, do: tags ++ [["subject", subject]], else: tags

    event = %{
      pubkey: sender_pub,
      created_at: created_at,
      kind: @kind_dm,
      tags: tags,
      content: plaintext
    }

    Map.put(event, :id, Event.compute_id(event))
  end

  @spec rumor_payload(map()) :: map()
  defp rumor_payload(event) do
    %{
      "id" => event.id,
      "pubkey" => event.pubkey,
      "created_at" => event.created_at,
      "kind" => event.kind,
      "tags" => event.tags,
      "content" => event.content
    }
  end

  @spec gift_wrap(map(), String.t()) :: {:ok, map()} | {:error, term()}
  defp gift_wrap(seal, recipient) do
    ephemeral = Keys.generate_private_key()
    ephemeral_pub = ephemeral |> Keys.derive_public_key() |> Keys.to_hex()

    with {:ok, seal_json} <- Jason.encode(signed_payload(seal)),
         {:ok, wrapped} <- NIP44.encrypt(seal_json, ephemeral, recipient) do
      wrap =
        ephemeral_pub
        |> Event.build_event(@kind_gift_wrap, [["p", recipient]], wrapped)
        |> stamp_created_at()

      Event.sign_event(wrap, ephemeral)
    end
  end

  @spec stamp_created_at(map()) :: map()
  defp stamp_created_at(event) do
    %{event | created_at: System.os_time(:second) - :rand.uniform(2 * 24 * 60 * 60)}
  end

  @spec field(map(), atom()) :: term()
  defp field(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  @spec signed_payload(map()) :: map()
  defp signed_payload(event) do
    %{
      "id" => event.id,
      "pubkey" => event.pubkey,
      "created_at" => event.created_at,
      "kind" => event.kind,
      "tags" => event.tags,
      "content" => event.content,
      "sig" => event.sig
    }
  end
end
