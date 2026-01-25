defmodule Rss2Nostr.CLI.Commands.Export do
  @moduledoc """
  CLI command for exporting posts to Nostr.
  """

  alias Rss2Nostr.CLI.Output
  alias Rss2Nostr.Posts
  alias Rss2Nostr.Nostr.{Publisher, Keys, NIP19, NIP96}

  @default_relays [
    "wss://relay.damus.io",
    "wss://nos.lol",
    "wss://relay.nostr.band"
  ]

  def run(options) do
    post_id = Map.get(options, :id)
    limit = Map.get(options, :limit, 10)
    dry_run = Map.get(options, :dry_run, false)
    nsec = Map.get(options, :nsec)
    relays = parse_relays(Map.get(options, :relays))
    upload_images = Map.get(options, :upload_images, false)

    Output.info("Exporting posts to Nostr...")

    # Get or prompt for private key
    case get_private_key(nsec) do
      {:ok, private_key, pubkey_hex} ->
        Output.info("  Using pubkey: #{String.slice(pubkey_hex, 0, 8)}...")

        if upload_images do
          Output.info("  Image upload: ENABLED")
        end

        if dry_run do
          Output.info("  Mode: DRY RUN (no publishing)")
          export_dry_run(post_id, limit, private_key, pubkey_hex, relays)
        else
          Output.info("  Relays: #{length(relays)}")
          export_and_publish(post_id, limit, private_key, relays, upload_images)
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

  defp parse_relays(nil), do: @default_relays

  defp parse_relays(relays) when is_binary(relays) do
    relays
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(String.starts_with?(&1, "wss://") or String.starts_with?(&1, "ws://")))
  end

  defp parse_relays(relays) when is_list(relays), do: relays

  defp export_dry_run(post_id, limit, private_key, _pubkey_hex, relays) do
    posts = get_posts_to_export(post_id, limit)

    if Enum.empty?(posts) do
      Output.info("No processed posts to export.")
    else
      Output.info("")
      Output.info("Would export #{length(posts)} posts:")
      Output.info("")

      Enum.each(posts, &preview_post_export(&1, private_key))

      Output.info("Relays that would be used:")

      Enum.each(relays, fn relay ->
        Output.info("  - #{relay}")
      end)
    end
  end

  defp export_and_publish(post_id, limit, private_key, relays, upload_images) do
    posts = get_posts_to_export(post_id, limit)

    if Enum.empty?(posts) do
      Output.info("No processed posts to export.")
    else
      Output.info("Exporting #{length(posts)} posts to #{length(relays)} relays...")
      Output.info("")

      # Optionally upload images first
      posts =
        if upload_images do
          Enum.map(posts, fn post ->
            upload_post_image(post, private_key)
          end)
        else
          posts
        end

      results = Publisher.publish_posts(posts, private_key: private_key, relays: relays)

      # Count results
      {success_count, error_count} =
        Enum.reduce(results, {0, 0}, fn {_id, result}, {s, e} ->
          if result.success, do: {s + 1, e}, else: {s, e + 1}
        end)

      Output.info("")
      Output.info("=== Export Summary ===")
      Output.info("  Published: #{success_count}")
      Output.info("  Errors:    #{error_count}")

      # Show details
      Enum.each(results, &show_result_detail(&1, posts, relays))

      if success_count > 0 do
        Output.success("\nExport completed!")
      else
        Output.error("\nExport failed.")
      end
    end
  end

  defp show_result_detail({post_id, result}, posts, relays) do
    post = Enum.find(posts, &(&1.id == post_id))
    title = if post, do: post.title, else: "Post #{post_id}"

    if result.success do
      Output.success("  ✓ #{title}")
      Output.info("    naddr: #{result.naddr}")
      Output.info("    Relays: #{length(result.successful_relays)}/#{length(relays)}")
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
  end

  defp get_posts_to_export(post_id, _limit) do
    case Posts.get_post(post_id) do
      nil -> []
      post -> [post]
    end
  end

  # Upload post image to NIP-96 server if it's an external URL
  defp upload_post_image(post, private_key) do
    image_url = post.image

    cond do
      is_nil(image_url) or image_url == "" ->
        post

      not should_upload_image?(image_url) ->
        post

      true ->
        do_upload_image(post, image_url, private_key)
    end
  end

  defp do_upload_image(post, image_url, private_key) do
    Output.info("  Uploading image for: #{String.slice(post.title, 0, 40)}...")

    case NIP96.upload_from_url(image_url, private_key: private_key) do
      {:ok, result} ->
        Output.success("    Uploaded: #{result.url}")
        %{post | image: result.url}

      {:error, reason} ->
        Output.error("    Upload failed: #{inspect(reason)}")
        post
    end
  end

  # Check if image should be uploaded (not already on a known NIP-96 server)
  defp should_upload_image?(url) do
    known_hosts = [
      "nostr.build",
      "image.nostr.build",
      "void.cat",
      "nostrcheck.me",
      "cdn.nostrcheck.me",
      "files.sovbit.host",
      "nostpic.com"
    ]

    uri = URI.parse(url)
    host = uri.host || ""

    not Enum.any?(known_hosts, fn known -> String.contains?(host, known) end)
  end
end
