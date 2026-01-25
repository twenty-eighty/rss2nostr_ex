defmodule Rss2Nostr.Nostr.Event do
  @moduledoc """
  Nostr event builder with support for:
  - Kind 1: Short text notes
  - Kind 30023: Long-form content (NIP-23)
  """

  alias Rss2Nostr.Nostr.Keys

  # Event kinds
  @kind_text_note 1
  @kind_long_form 30023
  @kind_long_form_draft 30024

  @type event :: %{
          id: String.t(),
          pubkey: String.t(),
          created_at: integer(),
          kind: integer(),
          tags: list(),
          content: String.t(),
          sig: String.t()
        }

  @doc """
  Creates a NIP-23 long-form content event.

  Options:
  - :title - Article title (required)
  - :summary - Article summary/description
  - :image - Featured image URL
  - :published_at - Unix timestamp of original publication
  - :identifier - Unique identifier (d tag), defaults to URL slug
  - :hashtags - List of hashtag strings
  """
  @spec build_long_form(String.t(), String.t(), keyword()) :: map()
  def build_long_form(pubkey, content, opts \\ []) do
    title = Keyword.fetch!(opts, :title)
    summary = Keyword.get(opts, :summary)
    image = Keyword.get(opts, :image)
    published_at = Keyword.get(opts, :published_at)
    identifier = Keyword.get(opts, :identifier) || generate_identifier(title)
    hashtags = Keyword.get(opts, :hashtags, [])

    # Build tags
    tags = [["d", identifier], ["title", title]]

    tags =
      if summary && summary != "" do
        tags ++ [["summary", summary]]
      else
        tags
      end

    tags =
      if image && image != "" do
        tags ++ [["image", image]]
      else
        tags
      end

    tags =
      if published_at do
        tags ++ [["published_at", to_string(published_at)]]
      else
        tags
      end

    # Add hashtags as 't' tags
    tags =
      Enum.reduce(hashtags, tags, fn tag, acc ->
        acc ++ [["t", String.downcase(tag)]]
      end)

    build_event(pubkey, @kind_long_form, tags, content)
  end

  @doc """
  Creates a simple text note (Kind 1).
  """
  @spec build_text_note(String.t(), String.t(), list()) :: map()
  def build_text_note(pubkey, content, tags \\ []) do
    build_event(pubkey, @kind_text_note, tags, content)
  end

  @doc """
  Creates an unsigned event structure.
  """
  @spec build_event(String.t(), integer(), list(), String.t()) :: map()
  def build_event(pubkey, kind, tags, content) do
    created_at = System.os_time(:second)

    %{
      pubkey: pubkey,
      created_at: created_at,
      kind: kind,
      tags: tags,
      content: content
    }
  end

  @doc """
  Computes the event ID (SHA256 of serialized event).
  """
  @spec compute_id(map()) :: String.t()
  def compute_id(event) do
    serialized = serialize_for_id(event)
    Keys.sha256(serialized) |> Keys.to_hex()
  end

  @doc """
  Signs an event with a private key using Node.js nostr-tools.
  Returns the complete signed event.
  """
  @spec sign_event(map(), binary()) :: {:ok, event()} | {:error, any()}
  def sign_event(event, private_key) do
    case Keys.sign_event(event, private_key) do
      {:ok, %{id: id, sig: sig, pubkey: pubkey}} ->
        {:ok,
         %{
           id: id,
           pubkey: pubkey,
           created_at: event.created_at,
           kind: event.kind,
           tags: event.tags,
           content: event.content,
           sig: sig
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Verifies an event's signature.
  """
  @spec verify_event(map()) :: {:ok, map()} | {:error, atom()}
  def verify_event(event) do
    # Recompute event ID
    expected_id = compute_id(event)

    if event.id != expected_id do
      {:error, :invalid_id}
    else
      {:ok, id_bin} = Keys.from_hex(event.id)
      {:ok, sig_bin} = Keys.from_hex(event.sig)
      {:ok, pubkey_bin} = Keys.from_hex(event.pubkey)

      if Keys.verify(id_bin, sig_bin, pubkey_bin) do
        {:ok, event}
      else
        {:error, :invalid_signature}
      end
    end
  end

  @doc """
  Serializes event for ID computation according to NIP-01.
  Returns JSON array: [0, pubkey, created_at, kind, tags, content]
  """
  @spec serialize_for_id(map()) :: String.t()
  def serialize_for_id(event) do
    [
      0,
      event.pubkey,
      event.created_at,
      event.kind,
      event.tags,
      event.content
    ]
    |> Jason.encode!()
  end

  @doc """
  Converts event to JSON string for relay transmission.
  """
  @spec to_json(map()) :: String.t()
  def to_json(event) do
    Jason.encode!(event)
  end

  # Generate a URL-safe identifier from title
  defp generate_identifier(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[äöüß]/, fn
      "ä" -> "ae"
      "ö" -> "oe"
      "ü" -> "ue"
      "ß" -> "ss"
    end)
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 50)
  end

  # Accessors for event kinds
  @spec kind_text_note() :: integer()
  def kind_text_note, do: @kind_text_note

  @spec kind_long_form() :: integer()
  def kind_long_form, do: @kind_long_form

  @spec kind_long_form_draft() :: integer()
  def kind_long_form_draft, do: @kind_long_form_draft
end
