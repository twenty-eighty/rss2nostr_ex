defmodule Rss2Nostr.Nostr.Event do
  @moduledoc """
  Nostr event builder with support for:
  - Kind 1: Short text notes
  - Kind 30023: Long-form content (NIP-23)
  - Kind 34235: Addressable video (NIP-71)
  - Kind 31234: Encrypted draft wraps (NIP-37)
  """

  alias Rss2Nostr.Nostr.{Keys, NIP44, NIP92}

  # Event kinds
  @kind_text_note 1
  @kind_deletion 5
  @kind_long_form 30023
  @kind_long_form_draft 30024
  @kind_video 34235
  @kind_draft_wrap 31234
  @draft_ttl_seconds 90 * 24 * 60 * 60
  @max_draft_plaintext_size 65_535
  @max_event_size 65_535
  @pareto_client_tag [
    "client",
    "Pareto",
    "31990:0f479c7dff7bb53dae53f3bb32ad1109edbb07ba562bdd5168044b3f4364e7b5:8020802080208020"
  ]

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
  - :hashtags - List of hashtag strings (`t` tags)
  - :language - ISO language code (`L`/`l` NIP-32 labels)
  - :canonical_url - Original article URL (`r` tag)
  - :imeta - NIP-92 tags (`["imeta", "url …", …]`) or pair lists
  - :author_pubkey - Intended author (added as a `p` tag on drafts)
  - :client - when true, adds the Pareto NIP-89 `client` tag (kind 30023 only)
  """
  @spec build_long_form(String.t(), String.t(), keyword()) :: map()
  def build_long_form(pubkey, content, opts \\ []) do
    title = Keyword.fetch!(opts, :title)
    summary = Keyword.get(opts, :summary)
    image = Keyword.get(opts, :image)
    published_at = Keyword.get(opts, :published_at)
    identifier = Keyword.get(opts, :identifier) || generate_identifier(title)
    hashtags = Keyword.get(opts, :hashtags, [])
    language = Keyword.get(opts, :language)
    canonical_url = Keyword.get(opts, :canonical_url)
    imeta = Keyword.get(opts, :imeta, [])
    kind = Keyword.get(opts, :kind, @kind_long_form)
    author_pubkey = Keyword.get(opts, :author_pubkey)
    client? = Keyword.get(opts, :client, false)

    tags =
      [["d", identifier], ["title", title]]
      |> maybe_summary_or_alt(kind, summary)
      |> maybe_tag("image", image)
      |> maybe_published_at(published_at)
      |> maybe_hashtag_tags(hashtags)
      |> maybe_language_tags(language)
      |> maybe_canonical_url(canonical_url)
      |> maybe_imeta_tags(imeta)
      |> maybe_author_tag(author_pubkey)
      |> maybe_client_tag(client?, kind)

    build_event(pubkey, kind, tags, content)
  end

  @doc """
  Wraps an unsigned long-form event as a NIP-37 kind 31234 draft.

  The inner event is JSON-stringified and NIP-44-encrypted to the
  signer's own public key. Tags: `d`, `k` (inner kind), `expiration`
  (now + 90 days), and `p` when an intended author is given.
  """
  @spec wrap_draft(map(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def wrap_draft(inner_event, private_key, opts \\ [])
      when is_map(inner_event) and byte_size(private_key) == 32 do
    with {:ok, signer_pubkey} <- signer_pubkey_hex(private_key),
         {:ok, plaintext} <- Jason.encode(inner_payload(inner_event)),
         {:ok, ciphertext} <- NIP44.encrypt(plaintext, private_key, signer_pubkey) do
      identifier = Keyword.get(opts, :identifier) || event_identifier(inner_event)
      expiration = Keyword.get(opts, :expiration) || System.os_time(:second) + @draft_ttl_seconds
      inner_kind = inner_event[:kind] || inner_event["kind"] || @kind_long_form
      author_pubkey = Keyword.get(opts, :author_pubkey)

      tags =
        [
          ["d", identifier || ""],
          ["k", to_string(inner_kind)],
          ["expiration", to_string(expiration)]
        ]
        |> maybe_author_tag(author_pubkey)

      {:ok, build_event(signer_pubkey, @kind_draft_wrap, tags, ciphertext)}
    end
  end

  @doc """
  Decrypts a NIP-37 wrap back to the inner unsigned event map.
  """
  @spec unwrap_draft(map(), binary()) :: {:ok, map()} | {:error, term()}
  def unwrap_draft(wrap_event, private_key)
      when is_map(wrap_event) and byte_size(private_key) == 32 do
    content = wrap_event[:content] || wrap_event["content"]
    peer = wrap_event[:pubkey] || wrap_event["pubkey"]

    with {:ok, plaintext} <- NIP44.decrypt(content, private_key, peer),
         {:ok, inner} <- Jason.decode(plaintext) do
      {:ok, inner}
    end
  end

  @doc """
  Creates a simple text note (Kind 1).
  """
  @spec build_text_note(String.t(), String.t(), list()) :: map()
  def build_text_note(pubkey, content, tags \\ []) do
    build_event(pubkey, @kind_text_note, tags, content)
  end

  @doc """
  NIP-09 deletion event. Tags: `e` for event ids, `a` for addressable coords.
  """
  @spec build_deletion(String.t(), keyword()) :: map()
  def build_deletion(pubkey, opts \\ []) do
    event_ids = Keyword.get(opts, :event_ids, [])
    addresses = Keyword.get(opts, :addresses, [])
    reason = Keyword.get(opts, :reason, "")

    tags =
      Enum.map(event_ids, &["e", &1]) ++
        Enum.map(addresses, &["a", &1])

    build_event(pubkey, @kind_deletion, tags, reason)
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
      with {:ok, id_bin} <- Keys.from_hex(event.id),
           {:ok, sig_bin} <- Keys.from_hex(event.sig),
           {:ok, pubkey_bin} <- Keys.from_hex(event.pubkey) do
        if Keys.verify(id_bin, sig_bin, pubkey_bin) do
          {:ok, event}
        else
          {:error, :invalid_signature}
        end
      else
        {:error, _} -> {:error, :invalid_signature}
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

  @spec kind_deletion() :: integer()
  def kind_deletion, do: @kind_deletion

  @spec kind_long_form() :: integer()
  def kind_long_form, do: @kind_long_form

  @spec kind_long_form_draft() :: integer()
  def kind_long_form_draft, do: @kind_long_form_draft

  @spec kind_video() :: integer()
  def kind_video, do: @kind_video

  @spec kind_draft_wrap() :: integer()
  def kind_draft_wrap, do: @kind_draft_wrap

  @doc """
  NIP-44 v2 maximum plaintext size in bytes.
  """
  @spec max_draft_plaintext_size() :: pos_integer()
  def max_draft_plaintext_size, do: @max_draft_plaintext_size

  @doc """
  Common relay limit for a signed EVENT message, in bytes.
  """
  @spec max_event_size() :: pos_integer()
  def max_event_size, do: @max_event_size

  @doc """
  NIP-89 `client` tag used on public kind 30023 articles.
  """
  @spec pareto_client_tag() :: [String.t()]
  def pareto_client_tag, do: @pareto_client_tag

  @doc """
  Estimated size of the `["EVENT", wrap]` JSON published for a NIP-37 draft.

  NIP-44 ciphertext is larger than the inner plaintext (padding + MAC +
  Base64), so an inner event that fits 65535 bytes can still produce a
  wrap the relay rejects.
  """
  @spec estimate_wrap_message_size(map(), keyword()) :: non_neg_integer()
  def estimate_wrap_message_size(inner_event, opts \\ []) when is_map(inner_event) do
    case draft_plaintext(inner_event) do
      {:ok, json} ->
        ciphertext = String.duplicate("A", nip44_base64_len(byte_size(json)))
        identifier = Keyword.get(opts, :identifier) || event_identifier(inner_event)
        author_pubkey = Keyword.get(opts, :author_pubkey)
        inner_kind = inner_event[:kind] || inner_event["kind"] || @kind_long_form

        tags =
          [
            ["d", identifier || ""],
            ["k", to_string(inner_kind)],
            ["expiration", "0000000000"]
          ]
          |> maybe_author_tag(author_pubkey)

        fake_wrap = %{
          id: String.duplicate("0", 64),
          pubkey: String.duplicate("0", 64),
          created_at: 1_000_000_000,
          kind: @kind_draft_wrap,
          tags: tags,
          content: ciphertext,
          sig: String.duplicate("0", 128)
        }

        json_size(["EVENT", fake_wrap])

      {:error, _} ->
        0
    end
  end

  @doc """
  Estimated size of the `["EVENT", event]` JSON published for a long-form article.
  """
  @spec estimate_event_message_size(map()) :: non_neg_integer()
  def estimate_event_message_size(event) when is_map(event) do
    fake = %{
      id: event[:id] || event["id"] || String.duplicate("0", 64),
      pubkey: event[:pubkey] || event["pubkey"] || String.duplicate("0", 64),
      created_at: event[:created_at] || event["created_at"] || 1_000_000_000,
      kind: event[:kind] || event["kind"] || @kind_long_form,
      tags: event[:tags] || event["tags"] || [],
      content: event[:content] || event["content"] || "",
      sig: event[:sig] || event["sig"] || String.duplicate("0", 128)
    }

    json_size(["EVENT", fake])
  end

  @doc false
  @spec nip44_padded_len(non_neg_integer()) :: non_neg_integer()
  def nip44_padded_len(len) when len <= 32, do: 32

  def nip44_padded_len(len) when len > 0 do
    next_power = Integer.pow(2, floor(:math.log2(len - 1)) + 1)
    chunk = if next_power <= 256, do: 32, else: div(next_power, 8)
    chunk * div(len - 1, chunk) + chunk
  end

  @doc """
  JSON payload that NIP-44 encrypts for a NIP-37 wrap.
  """
  @spec draft_plaintext(map()) :: {:ok, String.t()} | {:error, term()}
  def draft_plaintext(event) when is_map(event) do
    Jason.encode(inner_payload(event))
  end

  @doc """
  Byte size of `draft_plaintext/1`, or 0 if it cannot be encoded.
  """
  @spec draft_plaintext_size(map()) :: non_neg_integer()
  def draft_plaintext_size(event) when is_map(event) do
    case draft_plaintext(event) do
      {:ok, json} -> byte_size(json)
      {:error, _} -> 0
    end
  end

  defp maybe_summary_or_alt(tags, @kind_video, summary), do: maybe_tag(tags, "alt", summary)
  defp maybe_summary_or_alt(tags, _kind, summary), do: maybe_tag(tags, "summary", summary)

  defp maybe_tag(tags, _name, value) when value in [nil, ""], do: tags
  defp maybe_tag(tags, name, value) when is_binary(value), do: tags ++ [[name, value]]

  defp maybe_published_at(tags, published_at) when is_integer(published_at) do
    tags ++ [["published_at", to_string(published_at)]]
  end

  defp maybe_published_at(tags, _), do: tags

  @doc """
  Normalizes hashtags for `t` tags: trim, strip a leading `#`, downcase,
  collapse inner whitespace, drop blanks, and uniq.
  """
  @spec normalize_hashtags(term()) :: [String.t()]
  def normalize_hashtags(nil), do: []

  def normalize_hashtags(text) when is_binary(text) do
    text
    |> String.split(",")
    |> normalize_hashtags()
  end

  def normalize_hashtags(hashtags) when is_list(hashtags) do
    hashtags
    |> Enum.flat_map(&hashtag_tokens/1)
    |> Enum.uniq()
  end

  def normalize_hashtags(_), do: []

  defp maybe_hashtag_tags(tags, hashtags) do
    hashtags
    |> normalize_hashtags()
    |> Enum.reduce(tags, fn tag, acc -> acc ++ [["t", tag]] end)
  end

  defp maybe_language_tags(tags, language) do
    case normalize_language(language) do
      {code, namespace} -> tags ++ [["L", namespace], ["l", code, namespace]]
      nil -> tags
    end
  end

  defp maybe_canonical_url(tags, url) when is_binary(url) do
    trimmed = String.trim(url)

    if String.starts_with?(trimmed, "http://") or String.starts_with?(trimmed, "https://") do
      tags ++ [["r", trimmed]]
    else
      tags
    end
  end

  defp maybe_canonical_url(tags, _), do: tags

  defp maybe_imeta_tags(tags, imeta) when is_list(imeta) do
    tags ++
      Enum.flat_map(imeta, fn item ->
        case normalize_imeta_tag(item) do
          nil -> []
          tag -> [tag]
        end
      end)
  end

  defp maybe_imeta_tags(tags, _), do: tags

  defp normalize_imeta_tag(["imeta" | pairs]), do: NIP92.tag(pairs)

  defp normalize_imeta_tag(pairs) when is_list(pairs) do
    if Enum.all?(pairs, &is_binary/1), do: NIP92.tag(pairs)
  end

  defp normalize_imeta_tag(_), do: nil

  defp hashtag_tokens(tag) when is_binary(tag) do
    normalized =
      tag
      |> String.trim()
      |> String.trim_leading("#")
      |> String.downcase()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    if normalized == "", do: [], else: [normalized]
  end

  defp hashtag_tokens(_), do: []

  defp normalize_language(language) when is_binary(language) do
    code =
      language
      |> String.trim()
      |> String.downcase()
      |> String.replace("_", "-")

    cond do
      String.match?(code, ~r/^[a-z]{2}$/) ->
        {code, "ISO-639-1"}

      String.match?(code, ~r/^[a-z]{2}-[a-z]{2}$/) ->
        {String.slice(code, 0, 2), "ISO-639-1"}

      String.match?(code, ~r/^[a-z]{3}$/) ->
        {code, "ISO-639-3"}

      true ->
        nil
    end
  end

  defp normalize_language(_), do: nil

  defp maybe_author_tag(tags, author_pubkey)
       when is_binary(author_pubkey) and author_pubkey != "" do
    tags ++ [["p", String.downcase(author_pubkey)]]
  end

  defp maybe_author_tag(tags, _), do: tags

  defp maybe_client_tag(tags, true, @kind_long_form), do: tags ++ [@pareto_client_tag]
  defp maybe_client_tag(tags, _, _), do: tags

  defp signer_pubkey_hex(private_key) do
    case Keys.derive_public_key(private_key) do
      pubkey when is_binary(pubkey) -> {:ok, Keys.to_hex(pubkey)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp nip44_base64_len(plaintext_len) do
    payload_len = nip44_padded_len(plaintext_len) + 65
    4 * div(payload_len + 2, 3)
  end

  defp json_size(value) do
    case Jason.encode(value) do
      {:ok, json} -> byte_size(json)
      {:error, _} -> 0
    end
  end

  defp inner_payload(event) do
    %{
      "kind" => event[:kind] || event["kind"] || @kind_long_form,
      "created_at" => event[:created_at] || event["created_at"],
      "tags" => event[:tags] || event["tags"] || [],
      "content" => event[:content] || event["content"] || "",
      "pubkey" => event[:pubkey] || event["pubkey"] || ""
    }
  end

  defp event_identifier(event) do
    tags = event[:tags] || event["tags"] || []

    case Enum.find(tags, fn [tag | _] -> tag == "d" end) do
      [_, identifier | _] -> identifier
      _ -> ""
    end
  end
end
