defmodule Rss2Nostr.CLI.Commands.Export do
  @moduledoc """
  CLI command for exporting posts to Nostr.
  """

  alias Rss2Nostr.CLI.Output
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.Processor
  alias Rss2Nostr.Nostr.{Publisher, Relays, Keys, NIP19}
  alias Rss2Nostr.Repo

  def run(options) do
    post_id = Map.get(options, :id)
    limit = Map.get(options, :limit, 10)
    dry_run = Map.get(options, :dry_run, false)
    nsec = Map.get(options, :nsec)
    audience = Relays.parse_audience(Map.get(options, :audience))
    relays_override = parse_relays(Map.get(options, :relays))
    upload_images = Map.get(options, :upload_images, false)

    Output.info("Exporting posts to Nostr...")

    # Get or prompt for private key
    case get_private_key(nsec) do
      {:ok, private_key, pubkey_hex} ->
        Output.info("  Using pubkey: #{String.slice(pubkey_hex, 0, 8)}...")

        if upload_images do
          Output.info("  Image upload: ENABLED")
        end

        describe_relay_target(relays_override, audience)

        if dry_run do
          Output.info("  Mode: DRY RUN (no publishing)")
          export_dry_run(post_id, limit, private_key, relays_override, audience)
        else
          export_and_publish(
            post_id,
            limit,
            private_key,
            relays_override,
            audience,
            upload_images
          )
        end

      {:error, reason} ->
        Output.error("Failed to get private key: #{reason}")
    end
  end

  defp get_private_key(nil) do
    # Check environment variable
    case System.get_env("NOSTR_NSEC") do
      nil ->
        Output.error("No private key provided.")
        Output.info("  Use --nsec flag or set NOSTR_NSEC environment variable")
        {:error, :no_key}

      nsec ->
        decode_nsec(nsec)
    end
  end

  defp get_private_key(nsec), do: decode_nsec(nsec)

  defp decode_nsec(nsec) do
    cond do
      String.starts_with?(nsec, "nsec") ->
        case NIP19.decode(nsec) do
          {:ok, :nsec, privkey_hex} ->
            {:ok, privkey_bin} = Keys.from_hex(privkey_hex)
            pubkey_bin = Keys.derive_public_key(privkey_bin)
            {:ok, privkey_bin, Keys.to_hex(pubkey_bin)}

          _ ->
            {:error, :invalid_nsec}
        end

      String.length(nsec) == 64 ->
        # Hex format
        case Keys.from_hex(nsec) do
          {:ok, privkey_bin} ->
            pubkey_bin = Keys.derive_public_key(privkey_bin)
            {:ok, privkey_bin, Keys.to_hex(pubkey_bin)}

          _ ->
            {:error, :invalid_hex}
        end

      true ->
        {:error, :invalid_format}
    end
  end

  defp parse_relays(nil), do: nil

  defp parse_relays(relays) when is_binary(relays) do
    relays
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(String.starts_with?(&1, "wss://") or String.starts_with?(&1, "ws://")))
  end

  defp parse_relays(relays) when is_list(relays), do: relays

  defp describe_relay_target(relays, _audience) when is_list(relays) do
    Output.info("  Relays: #{length(relays)} (explicit override)")
  end

  defp describe_relay_target(_relays, audience) when audience in [:test, :public] do
    Output.info("  Relays: #{length(Relays.for(audience))} (#{audience} list)")
  end

  defp describe_relay_target(_relays, _audience) do
    Output.info("  Relays: per source (test vs public)")
  end

  defp publish_opts(private_key, relays, _audience) when is_list(relays) do
    [private_key: private_key, relays: relays]
  end

  defp publish_opts(private_key, _relays, audience) when audience in [:test, :public] do
    [private_key: private_key, relays: Relays.for(audience)]
  end

  defp publish_opts(private_key, _relays, _audience) do
    [private_key: private_key]
  end

  defp relays_for_post(_post, relays, _audience) when is_list(relays), do: relays

  defp relays_for_post(_post, _relays, audience) when audience in [:test, :public],
    do: Relays.for(audience)

  defp relays_for_post(post, _relays, _audience), do: Relays.for_post(post)

  defp export_dry_run(post_id, limit, private_key, relays, audience) do
    posts = get_posts_to_export(post_id, limit)

    if Enum.empty?(posts) do
      Output.info("No processed posts to export.")
    else
      Output.info("")
      Output.info("Would export #{length(posts)} posts:")
      Output.info("")

      Enum.each(posts, fn post ->
        preview_post_export(post, private_key)
        used = relays_for_post(post, relays, audience)
        Output.info("    Audience: #{Relays.audience_for_post(post)}")
        Output.info("    Relays:")

        Enum.each(used, fn relay ->
          Output.info("      - #{relay}")
        end)

        Output.info("")
      end)
    end
  end

  defp export_and_publish(post_id, limit, private_key, relays, audience, upload_images) do
    posts = get_posts_to_export(post_id, limit)

    if Enum.empty?(posts) do
      Output.info("No processed posts to export.")
    else
      Output.info("Exporting #{length(posts)} posts...")
      Output.info("")

      {ready, skipped} =
        posts
        |> Enum.map(&prepare_export_post(&1, upload_images, private_key))
        |> Enum.split_with(&match?({:ok, _}, &1))

      ready_posts = Enum.map(ready, fn {:ok, post} -> post end)

      Enum.each(skipped, fn {:error, {post, reason}} ->
        Output.error("  ✗ #{post.title}")
        Output.error("    Image upload failed (will retry): #{inspect(reason)}")
      end)

      results =
        if ready_posts == [] do
          []
        else
          Publisher.publish_posts(ready_posts, publish_opts(private_key, relays, audience))
        end

      {success_count, publish_errors} =
        Enum.reduce(results, {0, 0}, fn {_id, result}, {s, e} ->
          if result.success, do: {s + 1, e}, else: {s, e + 1}
        end)

      error_count = publish_errors + length(skipped)

      Output.info("")
      Output.info("=== Export Summary ===")
      Output.info("  Published: #{success_count}")
      Output.info("  Errors:    #{error_count}")

      Enum.each(results, &show_result_detail(&1, ready_posts, relays, audience))

      if success_count > 0 do
        Output.success("\nExport completed!")
      else
        Output.error("\nExport failed.")
      end
    end
  end

  defp prepare_export_post(post, _upload_images, _private_key) do
    {:ok, updated} = Processor.ensure_images(post)

    if updated.status == Post.status_processed() do
      {:ok, updated}
    else
      {:error, {updated, :images_pending}}
    end
  end

  defp show_result_detail({post_id, result}, posts, relays, audience) do
    post = Enum.find(posts, &(&1.id == post_id))
    title = if post, do: post.title, else: "Post #{post_id}"
    used = if post, do: relays_for_post(post, relays, audience), else: []

    if result.success do
      Output.success("  ✓ #{title}")
      Output.info("    naddr: #{result.naddr}")
      Output.info("    Relays: #{length(result.successful_relays)}/#{length(used)}")
    else
      Output.error("  ✗ #{title}")
      if result[:error], do: Output.error("    Error: #{inspect(result.error)}")
    end
  end

  defp preview_post_export(post, private_key) do
    case Publisher.export_post(post, private_key: private_key, relays: []) do
      {:ok, %{event: event, naddr: naddr}} ->
        Output.info("  #{post.title}")
        Output.info("    Event ID: #{event.id}")
        Output.info("    naddr: #{naddr}")
        Output.info("")

      {:error, reason} ->
        Output.error("  Error: #{inspect(reason)}")
    end
  end

  defp get_posts_to_export(nil, limit) do
    Posts.list_processed_posts(limit: limit)
    |> Repo.preload(:source)
  end

  defp get_posts_to_export(post_id, _limit) do
    case Posts.get_post(post_id, preload: [:source]) do
      nil -> []
      post -> [post]
    end
  end
end
