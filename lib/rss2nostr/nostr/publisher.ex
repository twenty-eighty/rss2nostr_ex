defmodule Rss2Nostr.Nostr.Publisher do
  @moduledoc """
  Orchestrates publishing Nostr events to multiple relays.
  Handles:
  - Building and signing events
  - Publishing to multiple relays in parallel
  - Tracking success/failure across relays
  """

  require Logger

  alias Rss2Nostr.Nostr.{Event, Keys, Relay, NIP19}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post

  @type publish_result :: %{
          success: boolean(),
          event_id: String.t() | nil,
          naddr: String.t() | nil,
          successful_relays: [String.t()],
          failed_relays: [String.t()]
        }

  @doc """
  Publishes a post as a NIP-23 long-form article to the configured relays.

  Options:
  - :private_key - 32-byte binary private key (required)
  - :relays - List of relay URLs (required)
  - :min_success - Minimum number of successful publishes (default: 1)
  """
  def publish_post(%Post{} = post, opts) do
    private_key = Keyword.fetch!(opts, :private_key)
    relays = Keyword.fetch!(opts, :relays)
    min_success = Keyword.get(opts, :min_success, 1)

    # Derive public key
    pubkey_bin = Keys.derive_public_key(private_key)
    pubkey_hex = Keys.to_hex(pubkey_bin)

    # Build the event
    event =
      Event.build_long_form(pubkey_hex, post.content,
        title: post.title,
        summary: post.summary,
        image: post.image,
        published_at: post.published_at && DateTime.to_unix(post.published_at),
        identifier: generate_identifier(post),
        # Could extract from categories
        hashtags: []
      )

    # Sign the event
    case Event.sign_event(event, private_key) do
      {:ok, signed_event} ->
        Logger.info("Publishing event #{signed_event.id} to #{length(relays)} relays")
        publish_signed_event(post, signed_event, pubkey_hex, relays, min_success)

      {:error, reason} ->
        Logger.error("Failed to sign event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp publish_signed_event(post, signed_event, pubkey_hex, relays, min_success) do
    # Publish to all relays
    results = Relay.publish_to_relays(relays, signed_event)

    # Analyze results
    {successful, failed} =
      Enum.reduce(results, {[], []}, fn {url, result}, {success, fail} ->
        case result do
          :ok -> {[url | success], fail}
          {:error, _} -> {success, [url | fail]}
        end
      end)

    success = length(successful) >= min_success

    # Generate naddr for the article
    identifier = get_event_identifier(signed_event)
    naddr_result = NIP19.encode_naddr(Event.kind_long_form(), pubkey_hex, identifier, successful)

    naddr =
      case naddr_result do
        {:ok, naddr} -> naddr
        _ -> nil
      end

    result = %{
      success: success,
      event_id: signed_event.id,
      naddr: naddr,
      successful_relays: successful,
      failed_relays: failed
    }

    # Update post with Nostr info if successful
    if success do
      Posts.mark_published(post, signed_event.id, pubkey_hex, naddr)
    end

    {:ok, result}
  end

  @doc """
  Exports a post to Nostr without updating the database.
  Returns the signed event and publishing results.
  """
  def export_post(%Post{} = post, opts) do
    private_key = Keyword.fetch!(opts, :private_key)
    relays = Keyword.get(opts, :relays, [])

    # Derive public key
    pubkey_bin = Keys.derive_public_key(private_key)
    pubkey_hex = Keys.to_hex(pubkey_bin)

    # Build the event
    event =
      Event.build_long_form(pubkey_hex, post.content,
        title: post.title,
        summary: post.summary,
        image: post.image,
        published_at: post.published_at && DateTime.to_unix(post.published_at),
        identifier: generate_identifier(post),
        hashtags: []
      )

    # Sign the event
    case Event.sign_event(event, private_key) do
      {:ok, signed_event} ->
        # Generate naddr
        identifier = get_event_identifier(signed_event)
        {:ok, naddr} = NIP19.encode_naddr(Event.kind_long_form(), pubkey_hex, identifier, relays)

        # Optionally publish
        publish_results =
          if relays != [] do
            Relay.publish_to_relays(relays, signed_event)
          else
            []
          end

        {:ok,
         %{
           event: signed_event,
           naddr: naddr,
           publish_results: publish_results
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Batch publishes multiple posts.
  """
  def publish_posts(posts, opts) do
    Enum.map(posts, fn post ->
      case publish_post(post, opts) do
        {:ok, result} -> {post.id, result}
        {:error, reason} -> {post.id, %{success: false, error: reason}}
      end
    end)
  end

  # Generate a unique identifier for the post (d tag)
  defp generate_identifier(%Post{} = post) do
    # Use URL slug or title-based identifier
    base =
      if post.source_url do
        post.source_url
        |> URI.parse()
        |> Map.get(:path, "")
        |> String.split("/")
        |> List.last()
        # Remove extension
        |> String.replace(~r/\.[^.]+$/, "")
      else
        post.title
      end

    base
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[äöüß]/, fn
      "ä" -> "ae"
      "ö" -> "oe"
      "ü" -> "ue"
      "ß" -> "ss"
    end)
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 64)
  end

  # Extract identifier from signed event tags
  defp get_event_identifier(event) do
    case Enum.find(event.tags, fn [tag | _] -> tag == "d" end) do
      [_, identifier | _] -> identifier
      _ -> ""
    end
  end
end
