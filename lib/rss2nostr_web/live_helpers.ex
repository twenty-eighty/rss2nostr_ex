defmodule Rss2NostrWeb.LiveHelpers do
  @moduledoc false

  alias Rss2Nostr.Nostr.{Relays, Signer}
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Sources.Source
  alias Rss2Nostr.Web.Views.Sources.{Helpers, Language}

  @avatar_placeholder "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='32' height='32'%3E%3Crect fill='%23e5e7eb' width='32' height='32' rx='16'/%3E%3C/svg%3E"

  def truncate(value, max), do: Helpers.truncate(value, max)
  def format_datetime(value), do: Helpers.format_datetime(value)
  def status_class(status), do: Helpers.status_class(status)
  def status_label(status), do: Post.status_label(status)
  def option(source, key), do: Helpers.option(source, key)
  def skip_classes_text(source), do: Helpers.skip_classes_text(source)
  def known_body_schema?(selector, source), do: Helpers.known_body_schema?(selector, source)
  def start_label(source, start_guid, start_at), do: Helpers.start_label(source, start_guid, start_at)
  def datetime_value(value), do: Helpers.datetime_value(value)
  def relay_target_label(target), do: Helpers.relay_target_label(target)
  def relay_badge_class(target), do: Helpers.relay_badge_class(target)
  def relay_target_name(target), do: Helpers.relay_target_name(target)
  def avatar_relays, do: Helpers.avatar_relays()
  def avatar_placeholder, do: @avatar_placeholder
  def author_pubkey(source), do: Signer.author_pubkey(source)
  def target_for(source), do: Relays.target_for(source)

  def language_options(selected) do
    selected = selected || "de"
    choices = Language.choices()

    if Enum.any?(choices, fn {code, _} -> code == selected end) do
      choices
    else
      [{selected, selected} | choices]
    end
  end

  def shorten_npub(nil), do: nil

  def shorten_npub(npub) when is_binary(npub) and byte_size(npub) > 16 do
    String.slice(npub, 0, 8) <> "…" <> String.slice(npub, -8, 8)
  end

  def shorten_npub(npub), do: npub

  def error_text(nil), do: nil
  def error_text(msgs) when is_list(msgs), do: Enum.join(msgs, ", ")
  def error_text(msg), do: to_string(msg)

  def changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  def format_update_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> changeset_errors()
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{error_text(msgs)}" end)
  end

  def format_update_error(reason), do: to_string(reason)

  def import_notice(result) do
    skipped =
      if result.skipped > 0 do
        " Skipped #{result.skipped} already imported."
      else
        ""
      end

    errors =
      case result.errors do
        [] -> ""
        list -> " Errors: #{Enum.join(list, "; ")}."
      end

    "Imported #{result.imported} articles, processed #{result.processed}.#{skipped}#{errors}"
  end

  def publish_notice(result) do
    base = "Published #{result.published}. Failed #{result.failed}."

    message =
      case result[:errors] do
        [] -> base
        nil -> base
        issues -> base <> " " <> Enum.join(issues, " ")
      end

    kind =
      cond do
        result.failed > 0 -> :error
        is_list(result[:errors]) and result[:errors] != [] -> :warning
        true -> :info
      end

    {kind, message}
  end

  def reprocess_notice(result) do
    "Reprocessed #{result.processed}. Failed #{result.errors}."
  end

  def reprocessable?(%Post{} = post) do
    post.status in [Post.status_processed(), Post.status_pending_images()]
  end

  def publishable?(%Post{} = post), do: post.status == Post.status_processed()

  def join_tags(nil), do: ""
  def join_tags(list) when is_list(list), do: Enum.join(list, ", ")
  def join_tags(value), do: to_string(value)

  def source_path(%Source{id: id}, tab) when tab in ["feed", "compose", "articles", "publishing"] do
    "/sources/#{id}?tab=#{tab}"
  end

  def source_path(%Source{id: id}, _tab), do: "/sources/#{id}"

  def post_preview_href(source, post) do
    "/posts/#{post.id}?return_to=" <>
      URI.encode_www_form("/sources/#{source.id}?tab=articles")
  end

  def posts_path(opts) when is_list(opts) do
    query =
      opts
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
      |> URI.encode_query()

    case query do
      "" -> "/posts"
      encoded -> "/posts?" <> encoded
    end
  end

  def format_interval(ms) when is_integer(ms) do
    cond do
      rem(ms, 3_600_000) == 0 -> "#{div(ms, 3_600_000)}h"
      rem(ms, 60_000) == 0 -> "#{div(ms, 60_000)}m"
      rem(ms, 1000) == 0 -> "#{div(ms, 1000)}s"
      true -> "#{ms}ms"
    end
  end

  def format_interval(other), do: to_string(other || "-")

  def format_last_run(nil), do: "Never"
  def format_last_run(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  def format_last_run(other), do: to_string(other)

  def format_last_result(nil), do: "—"
  def format_last_result(%{error: reason}), do: "Error: #{reason}"
  def format_last_result(%{deleted: d, skipped: s}), do: "#{d} deleted, #{s} waiting"
  def format_last_result(%{imported: i, errors: e}), do: "#{i} imported, #{e} errors"
  def format_last_result(%{processed: p, errors: e}), do: "#{p} processed, #{e} errors"
  def format_last_result(%{published: p, errors: e}), do: "#{p} published, #{e} errors"
  def format_last_result(map) when is_map(map), do: inspect(map)

  def scheduler_status_class(status) do
    case status do
      :completed -> "badge-success"
      :running -> "badge-processing"
      :failed -> "badge-error"
      _ -> "badge-idle"
    end
  end
end
