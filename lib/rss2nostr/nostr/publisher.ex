defmodule Rss2Nostr.Nostr.Publisher do
  @moduledoc """
  Orchestrates publishing Nostr events to multiple relays.
  Handles:
  - Building and signing events
  - Publishing to multiple relays in parallel
  - Tracking success/failure across relays
  """

  require Logger

  alias Rss2Nostr.Nostr.{NIP19, Relays}

  alias Rss2Nostr.Nostr.Publisher.{
    Gap,
    Identifiers,
    PostKind,
    PostLoader,
    Preview,
    RelayPublish,
    Report,
    Signing
  }

  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post

  @type relay_failure :: Report.relay_failure()

  @type publish_result :: %{
          success: boolean(),
          event_id: String.t() | nil,
          naddr: String.t() | nil,
          successful_relays: [String.t()],
          failed_relays: [relay_failure()],
          report: String.t()
        }

  @doc """
  Publishes a post as a NIP-23 long-form article to the configured relays.

  Options:
  - :signer - `{:private_key, key}` or `{:bunker, url}`
  - :private_key - 32-byte binary or hex/nsec (legacy; used when `:signer` is absent)
  - :relays - List of relay URLs (optional; unknown sources cannot use public relays)
  - :min_success - Minimum number of successful publishes (default: 1)
  """
  def publish_post(%Post{} = post, opts) do
    post = PostLoader.ensure_source(post)
    relays = Relays.publish_relays(post, opts)
    min_success = Keyword.get(opts, :min_success, 1)

    cond do
      relays == [] ->
        {:error, :no_relays}

      true ->
        with {:ok, signer} <- Signing.resolve_signer(post, opts) do
          do_publish_post(post, signer, relays, min_success)
        end
    end
  end

  defp do_publish_post(post, signer, relays, min_success) do
    with {:ok, pubkey_hex, signer} <- Signing.pubkey_for_signer(signer),
         {:ok, events} <- Signing.prepare_events(post, pubkey_hex, signer),
         {:ok, signed_events} <- Signing.sign_all(signer, events) do
      Logger.info("Publishing #{length(signed_events)} event(s) to #{length(relays)} relays")

      results =
        Enum.map(signed_events, fn signed_event ->
          RelayPublish.publish_signed_event(
            signed_event,
            PostKind.published_kind(post),
            pubkey_hex,
            relays,
            min_success
          )
        end)

      Signing.close_signer(signer)
      summarize_publish(post, pubkey_hex, results)
    else
      {:error, reason} ->
        Signing.close_signer(signer)
        Logger.error("Failed to sign event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp summarize_publish(post, pubkey_hex, results) do
    first = List.first(results) || %{success: false, event_id: nil, naddr: nil}
    success = results != [] and Enum.all?(results, & &1.success)
    successful = results |> Enum.flat_map(& &1.successful_relays) |> Enum.uniq()
    failed = Report.merge_failures(Enum.flat_map(results, & &1.failed_relays))
    report = Report.format_report(successful, failed)

    {:ok, post} =
      if success do
        case Posts.mark_published(post, first.event_id, pubkey_hex, first.naddr) do
          {:ok, published} ->
            {:ok, published}

          {:error, reason} ->
            Logger.error("Failed to store publish result for post #{post.id}: #{inspect(reason)}")
            {:ok, post}
        end
      else
        {:ok, post}
      end

    if failed != [] or not success do
      _ = Posts.update_post(post, %{last_error: Report.report_or_failure(report)})
      Logger.warning("Publish report for post #{post.id}: #{Report.report_or_failure(report)}")
    end

    {:ok,
     %{
       success: success,
       event_id: first.event_id,
       naddr: first.naddr,
       successful_relays: successful,
       failed_relays: failed,
       report: report,
       parts: length(results)
     }}
  end

  @spec format_report([String.t()], [relay_failure()]) :: String.t()
  def format_report(successful, failed), do: Report.format_report(successful, failed)

  @doc """
  Builds the unsigned long-form event that would be sent to relays.

  `id` and `sig` are omitted until publish. `created_at` is a preview
  timestamp and is replaced when the event is signed.
  """
  @spec preview_event(Post.t() | map(), keyword()) :: map()
  def preview_event(post_or_attrs, opts \\ []), do: Preview.preview_event(post_or_attrs, opts)

  @doc """
  Exports a post to Nostr without updating the database.
  Returns the signed event and publishing results.
  """
  def export_post(%Post{} = post, opts) do
    post = PostLoader.ensure_source(post)
    relays = Relays.publish_relays(post, Keyword.put_new(opts, :relays, []))

    with {:ok, signer} <- Signing.resolve_signer(post, opts),
         {:ok, pubkey_hex, signer} <- Signing.pubkey_for_signer(signer),
         {:ok, events} <- Signing.prepare_events(post, pubkey_hex, signer),
         {:ok, signed_events} <- Signing.sign_all(signer, events) do
      signed_event = hd(signed_events)
      identifier = Identifiers.from_event(signed_event)

      {:ok, naddr} =
        NIP19.encode_naddr(PostKind.published_kind(post), pubkey_hex, identifier, relays)

      publish_results =
        if relays != [] do
          Enum.flat_map(signed_events, &RelayPublish.publish_with_rate_limit_retry(relays, &1))
        else
          []
        end

      Signing.close_signer(signer)

      {:ok,
       %{
         event: signed_event,
         naddr: naddr,
         publish_results: publish_results
       }}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Batch publishes multiple posts.
  """
  def publish_posts(posts, opts) do
    each_with_gap(posts, fn post ->
      case publish_post(post, opts) do
        {:ok, result} -> {post.id, result}
        {:error, reason} -> {post.id, %{success: false, error: reason}}
      end
    end)
  end

  @doc """
  Milliseconds to wait between articles and before retrying a rate-limited relay.
  """
  @spec publish_gap_ms() :: non_neg_integer()
  def publish_gap_ms, do: Gap.publish_gap_ms()

  @doc """
  Maps `fun` over `items`, sleeping `publish_gap_ms/0` between calls.
  """
  @spec each_with_gap(list(), (term() -> term())) :: list()
  def each_with_gap(items, fun), do: Gap.each_with_gap(items, fun)

  @doc """
  `d` tag used when publishing this post.
  """
  @spec identifier(Post.t() | map()) :: String.t()
  def identifier(post), do: Identifiers.from_post(post)
end
