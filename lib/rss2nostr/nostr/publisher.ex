defmodule Rss2Nostr.Nostr.Publisher do
  @moduledoc """
  Orchestrates publishing Nostr events to multiple relays.
  Handles:
  - Building and signing events
  - Publishing to multiple relays in parallel
  - Tracking success/failure across relays
  """

  require Logger

  alias Rss2Nostr.Nostr.{Event, Keys, NIP19, NIP46, Relay, Relays, Signer}
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.ArticleSplit
  alias Rss2Nostr.Repo

  @type relay_failure :: %{url: String.t(), error: String.t()}

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
  - :relays - List of relay URLs (optional; setup sources cannot use public relays)
  - :min_success - Minimum number of successful publishes (default: 1)
  """
  def publish_post(%Post{} = post, opts) do
    post = ensure_source(post)
    relays = Relays.publish_relays(post, opts)
    min_success = Keyword.get(opts, :min_success, 1)

    cond do
      relays == [] ->
        {:error, :no_relays}

      true ->
        with {:ok, signer} <- resolve_signer(post, opts) do
          do_publish_post(post, signer, relays, min_success)
        end
    end
  end

  defp do_publish_post(post, signer, relays, min_success) do
    with {:ok, pubkey_hex, signer} <- pubkey_for_signer(signer),
         {:ok, events} <- prepare_events(post, pubkey_hex, signer),
         {:ok, signed_events} <- sign_all(signer, events) do
      Logger.info("Publishing #{length(signed_events)} event(s) to #{length(relays)} relays")

      results =
        Enum.map(signed_events, fn signed_event ->
          publish_signed_event(
            signed_event,
            published_kind(post),
            pubkey_hex,
            relays,
            min_success
          )
        end)

      close_signer(signer)
      summarize_publish(post, pubkey_hex, results)
    else
      {:error, reason} ->
        close_signer(signer)
        Logger.error("Failed to sign event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp publish_signed_event(signed_event, kind, pubkey_hex, relays, min_success) do
    results = Relay.publish_to_relays(relays, signed_event)

    {successful, failed} =
      Enum.reduce(results, {[], []}, fn {url, result}, {success, fail} ->
        case result do
          :ok ->
            {[url | success], fail}

          {:error, reason} ->
            {success, [%{url: url, error: Relay.format_error(reason)} | fail]}

          reason ->
            {success, [%{url: url, error: Relay.format_error(reason)} | fail]}
        end
      end)

    identifier = get_event_identifier(signed_event)
    naddr_result = NIP19.encode_naddr(kind, pubkey_hex, identifier, successful)

    naddr =
      case naddr_result do
        {:ok, naddr} -> naddr
        _ -> nil
      end

    %{
      success: length(successful) >= min_success,
      event_id: signed_event.id,
      naddr: naddr,
      successful_relays: successful,
      failed_relays: failed
    }
  end

  defp summarize_publish(post, pubkey_hex, results) do
    first = List.first(results) || %{success: false, event_id: nil, naddr: nil}
    success = results != [] and Enum.all?(results, & &1.success)
    successful = results |> Enum.flat_map(& &1.successful_relays) |> Enum.uniq()
    failed = merge_failures(Enum.flat_map(results, & &1.failed_relays))
    report = format_report(successful, failed)

    {:ok, post} =
      if success do
        Posts.mark_published(post, first.event_id, pubkey_hex, first.naddr)
      else
        {:ok, post}
      end

    if failed != [] or not success do
      _ = Posts.update_post(post, %{last_error: report_or_failure(report)})
      Logger.warning("Publish report for post #{post.id}: #{report_or_failure(report)}")
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
  def format_report(successful, failed) do
    accepted =
      case successful do
        [] -> nil
        urls -> "Accepted by #{Enum.join(urls, ", ")}."
      end

    issues =
      Enum.map(failed, fn
        %{url: url, error: error} -> "#{url}: #{error}"
        {url, error} -> "#{url}: #{error}"
      end)

    [accepted | issues]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp report_or_failure(""), do: "Publish failed"
  defp report_or_failure(report), do: report

  defp merge_failures(failures) do
    failures
    |> Enum.reverse()
    |> Enum.uniq_by(& &1.url)
    |> Enum.reverse()
  end

  @doc """
  Builds the unsigned long-form event that would be sent to relays.

  `id` and `sig` are omitted until publish. `created_at` is a preview
  timestamp and is replaced when the event is signed.
  """
  @spec preview_event(Post.t() | map(), keyword()) :: map()
  def preview_event(post_or_attrs, opts \\ []) do
    source = Keyword.get(opts, :source) || source_of(post_or_attrs)
    post_or_attrs = ensure_source_if_post(post_or_attrs)
    pubkey = preview_pubkey(source, post_or_attrs)
    parts = build_inner_events(post_or_attrs, pubkey)
    event = List.first(parts)
    relays = preview_relays(post_or_attrs, source)

    %{
      event: event,
      parts: parts,
      inner: nil,
      encrypted: false,
      draft: encrypted_draft?(post_or_attrs),
      plain_draft: plain_draft?(post_or_attrs),
      json: Jason.encode!(["EVENT", event], pretty: true),
      message: ["EVENT", event],
      relays: relays,
      signed: false
    }
  end

  @doc """
  Exports a post to Nostr without updating the database.
  Returns the signed event and publishing results.
  """
  def export_post(%Post{} = post, opts) do
    post = ensure_source(post)
    relays = Relays.publish_relays(post, Keyword.put_new(opts, :relays, []))

    with {:ok, signer} <- resolve_signer(post, opts),
         {:ok, pubkey_hex, signer} <- pubkey_for_signer(signer),
         {:ok, events} <- prepare_events(post, pubkey_hex, signer),
         {:ok, signed_events} <- sign_all(signer, events) do
      signed_event = hd(signed_events)
      identifier = get_event_identifier(signed_event)
      {:ok, naddr} = NIP19.encode_naddr(published_kind(post), pubkey_hex, identifier, relays)

      publish_results =
        if relays != [] do
          Enum.flat_map(signed_events, &Relay.publish_to_relays(relays, &1))
        else
          []
        end

      close_signer(signer)

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
    Enum.map(posts, fn post ->
      case publish_post(post, opts) do
        {:ok, result} -> {post.id, result}
        {:error, reason} -> {post.id, %{success: false, error: reason}}
      end
    end)
  end

  @doc """
  `d` tag used when publishing this post.
  """
  @spec identifier(Post.t() | map()) :: String.t()
  def identifier(post), do: generate_identifier(post)

  # Generate a unique identifier for the post (d tag)
  defp generate_identifier(post) do
    source_url = field(post, :source_url)
    title = field(post, :title)

    base =
      if source_url do
        source_url
        |> URI.parse()
        |> Map.get(:path, "")
        |> String.split("/")
        |> List.last()
        |> String.replace(~r/\.[^.]+$/, "")
      else
        title
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

  defp long_form_kind(post) do
    if draft_kind?(post) do
      Event.kind_long_form_draft()
    else
      case field(post, :type) do
        kind when kind in [30023, 30024] -> kind
        _ -> Event.kind_long_form()
      end
    end
  end

  defp published_kind(post) do
    cond do
      encrypted_draft?(post) -> Event.kind_draft_wrap()
      plain_draft?(post) -> Event.kind_long_form_draft()
      true -> Event.kind_long_form()
    end
  end

  defp public_article?(post) do
    not draft_kind?(post) and Relays.target_for(post) == :public
  end

  defp draft_kind?(post), do: encrypted_draft?(post) or plain_draft?(post)

  defp encrypted_draft?(post) do
    case source_of(post) do
      %Rss2Nostr.Sources.Source{} = source ->
        Signer.encrypted_draft?(source)

      _ ->
        case field(post, :publish_as) do
          "draft_plain" ->
            false

          "article" ->
            false

          "draft" ->
            true

          _ ->
            case field(post, :type) do
              30023 -> false
              30024 -> true
              31234 -> true
              _ -> true
            end
        end
    end
  end

  defp plain_draft?(post) do
    case source_of(post) do
      %Rss2Nostr.Sources.Source{} = source ->
        Signer.plain_draft?(source)

      _ ->
        field(post, :publish_as) == "draft_plain"
    end
  end

  defp prepare_events(post, pubkey_hex, signer) do
    inners = build_inner_events(post, inner_pubkey(post, pubkey_hex))

    if encrypted_draft?(post) do
      wrap_all(inners, post, signer)
    else
      {:ok, inners}
    end
  end

  defp wrap_all(inners, post, signer) do
    Enum.reduce_while(inners, {:ok, []}, fn inner, {:ok, acc} ->
      case wrap_draft_event(inner, post, signer) do
        {:ok, wrap} -> {:cont, {:ok, acc ++ [wrap]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp sign_all(signer, events) do
    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
      case sign_with(signer, event) do
        {:ok, signed} -> {:cont, {:ok, acc ++ [signed]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp wrap_draft_event(inner, post, {:private_key, key}) do
    Event.wrap_draft(inner, key,
      identifier: get_event_identifier(inner),
      author_pubkey: draft_author(post)
    )
  end

  defp wrap_draft_event(_inner, _post, _), do: {:error, :cannot_encrypt_draft}

  defp draft_author(post, source \\ nil) do
    source = source || source_of(post)

    if draft_kind?(post) do
      # posts.pubkey is the wrap/app signer after publish.
      # The intended author is always the source field.
      field(source, :pubkey)
    end
  end

  defp inner_pubkey(post, signer_pubkey) do
    author = if encrypted_draft?(post), do: draft_author(post)

    if Keys.valid_pubkey?(author) do
      String.downcase(author)
    else
      signer_pubkey
    end
  end

  defp resolve_signer(post, opts) do
    cond do
      Keyword.has_key?(opts, :signer) ->
        {:ok, Keyword.fetch!(opts, :signer)}

      Keyword.has_key?(opts, :private_key) ->
        {:ok, {:private_key, Keyword.fetch!(opts, :private_key)}}

      true ->
        Signer.resolve(post.source)
    end
  end

  defp build_inner_events(post, pubkey_hex) do
    content = field(post, :content) || ""
    chunks = split_content(post, pubkey_hex, content)
    total = length(chunks)

    chunks
    |> Enum.with_index(1)
    |> Enum.map(fn {chunk, index} ->
      build_event(post, pubkey_hex, content: chunk, index: index, total: total)
    end)
  end

  defp split_content(post, pubkey_hex, content) do
    ArticleSplit.split(
      content,
      fn chunk, index ->
        measure_published_size(post, pubkey_hex, chunk, index)
      end,
      max_size: Event.max_event_size()
    )
  end

  defp measure_published_size(post, pubkey_hex, chunk, index) do
    inner = build_event(post, pubkey_hex, content: chunk, index: index, total: 99)

    if encrypted_draft?(post) do
      Event.estimate_wrap_message_size(inner, author_pubkey: draft_author(post))
    else
      Event.estimate_event_message_size(inner)
    end
  end

  defp build_event(post, pubkey_hex, opts) do
    index = Keyword.get(opts, :index, 1)
    total = Keyword.get(opts, :total, 1)
    content = Keyword.get(opts, :content) || field(post, :content) || ""
    title = part_title(field(post, :title) || "Untitled", index, total)
    identifier = part_identifier(generate_identifier(post), index, total)

    Event.build_long_form(pubkey_hex, content,
      title: title,
      summary: field(post, :summary),
      image: field(post, :image),
      published_at: part_published_at(field(post, :published_at), index, total),
      identifier: identifier,
      hashtags: publish_hashtags(post),
      language: field(post, :language),
      canonical_url: field(post, :source_url),
      kind: long_form_kind(post),
      author_pubkey: draft_author(post),
      client: public_article?(post)
    )
  end

  defp part_title(title, _index, 1), do: title
  defp part_title(title, index, total), do: "#{title} (#{index}/#{total})"

  defp part_identifier(identifier, _index, 1), do: identifier

  defp part_identifier(identifier, index, _total) do
    suffix = "-p#{index}"
    max = 64 - byte_size(suffix)
    String.slice(identifier || "", 0, max) <> suffix
  end

  defp preview_pubkey(source, post) do
    author = draft_author(post, source)

    cond do
      encrypted_draft?(post) and Keys.valid_pubkey?(author) ->
        String.downcase(author)

      true ->
        case Signer.resolve(source) do
          {:ok, {:private_key, key}} ->
            key |> Keys.derive_public_key() |> Keys.to_hex()

          _ ->
            field(source, :pubkey) || String.duplicate("0", 64)
        end
    end
  end

  defp preview_relays(%Post{} = post, _source), do: Relays.publish_relays(post)

  defp preview_relays(_attrs, %Rss2Nostr.Sources.Source{} = source),
    do: Relays.publish_relays(source)

  defp preview_relays(_, _), do: Relays.test()

  defp publish_hashtags(post) do
    (fixed_hashtags(post) ++ (field(post, :categories) || []))
    |> Event.normalize_hashtags()
  end

  defp fixed_hashtags(post) do
    case source_of(post) do
      %{fixed_hashtags: tags} when is_list(tags) -> tags
      _ -> []
    end
  end

  defp source_of(%Post{source: %Rss2Nostr.Sources.Source{} = source}), do: source
  defp source_of(%Post{} = post), do: ensure_source(post).source
  defp source_of(_), do: nil

  defp ensure_source_if_post(%Post{} = post), do: ensure_source(post)
  defp ensure_source_if_post(other), do: other

  defp field(%{__struct__: _} = struct, key), do: Map.get(struct, key)
  defp field(map, key) when is_map(map), do: map[key] || map[Atom.to_string(key)]
  defp field(_, _), do: nil

  # Later parts get +1s so clients that sort by published_at keep reading order.
  defp part_published_at(published_at, _index, 1), do: unix_published_at(published_at)

  defp part_published_at(published_at, index, _total) do
    base = unix_published_at(published_at) || System.os_time(:second)
    base + (index - 1)
  end

  defp unix_published_at(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp unix_published_at(unix) when is_integer(unix), do: unix
  defp unix_published_at(_), do: nil

  defp pubkey_for_signer({:private_key, private_key}) do
    pubkey_hex = private_key |> Keys.derive_public_key() |> Keys.to_hex()
    {:ok, pubkey_hex, {:private_key, private_key}}
  end

  defp pubkey_for_signer({:bunker, url}) do
    with {:ok, pid} <- NIP46.start_link(bunker_url: url),
         {:ok, _} <- NIP46.connect(pid),
         {:ok, pubkey} <- NIP46.get_public_key(pid) do
      {:ok, pubkey_hex(pubkey), {:bunker, pid}}
    end
  end

  defp sign_with({:private_key, private_key}, event), do: Event.sign_event(event, private_key)

  defp sign_with({:bunker, pid}, event) do
    case NIP46.sign_event(pid, event) do
      {:ok, signed} -> normalize_signed_event(signed, event)
      error -> error
    end
  end

  defp close_signer({:bunker, pid}) when is_pid(pid) do
    NIP46.disconnect(pid)
    GenServer.stop(pid, :normal)
  rescue
    _ -> :ok
  end

  defp close_signer(_), do: :ok

  defp normalize_signed_event(signed, event) when is_map(signed) do
    {:ok,
     %{
       id: signed["id"] || signed[:id],
       pubkey: signed["pubkey"] || signed[:pubkey] || event.pubkey,
       created_at: signed["created_at"] || signed[:created_at] || event.created_at,
       kind: signed["kind"] || signed[:kind] || event.kind,
       tags: signed["tags"] || signed[:tags] || event.tags,
       content: signed["content"] || signed[:content] || event.content,
       sig: signed["sig"] || signed[:sig]
     }}
  end

  defp normalize_signed_event(signed, event) when is_binary(signed) do
    case Jason.decode(signed) do
      {:ok, map} -> normalize_signed_event(map, event)
      _ -> {:error, :invalid_bunker_signature}
    end
  end

  defp normalize_signed_event(_, _), do: {:error, :invalid_bunker_signature}

  defp pubkey_hex(value) when is_binary(value) do
    String.downcase(value)
  end

  defp ensure_source(%Post{source: %Rss2Nostr.Sources.Source{}} = post), do: post

  defp ensure_source(%Post{} = post) do
    Repo.preload(post, :source)
  end
end
