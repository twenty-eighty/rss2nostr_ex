defmodule Rss2NostrWeb.LiveHelpers do
  @moduledoc false

  alias Phoenix.LiveView
  alias Rss2Nostr.Nostr.{Relays, Signer}
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Processing.{BodySchema, Composer}
  alias Rss2Nostr.Sources.Source
  alias Rss2NostrWeb.Language

  alias Rss2Nostr.Sources.Source

  @future_only_guid "__future_only__"

  @type source_option :: String.t() | [String.t()] | boolean() | integer() | nil

  @type import_notice_result :: %{
          imported: non_neg_integer(),
          processed: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: [String.t()]
        }

  @type publish_notice_result :: %{
          published: non_neg_integer(),
          failed: non_neg_integer(),
          errors: [String.t()]
        }

  @type reprocess_notice_result :: %{
          processed: non_neg_integer(),
          errors: non_neg_integer()
        }

  @avatar_placeholder "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='32' height='32'%3E%3Crect fill='%23e5e7eb' width='32' height='32' rx='16'/%3E%3C/svg%3E"

  @spec truncate(String.t() | nil, integer()) :: String.t()
  def truncate(str, max) when is_binary(str) do
    if String.length(str) > max, do: String.slice(str, 0, max) <> "...", else: str
  end

  def truncate(nil, _max), do: ""

  @spec format_datetime(DateTime.t() | nil) :: String.t()
  def format_datetime(nil), do: "-"
  def format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  @spec status_class(integer()) :: String.t()
  def status_class(status) do
    case status do
      0 -> "badge-new"
      1 -> "badge-processing"
      2 -> "badge-processed"
      6 -> "badge-published"
      9 -> "badge-pending-images"
      _ -> "badge-error"
    end
  end

  @spec status_label(integer()) :: String.t()
  def status_label(status), do: Post.status_label(status)

  @spec option(Source.t() | map() | nil, atom() | String.t()) :: source_option()
  def option(nil, _key), do: nil

  def option(source, key) do
    (source.options || %{})[key]
  end

  @spec skip_classes_text(Source.t() | map() | nil) :: String.t()
  def skip_classes_text(nil), do: Composer.default_skip_classes_text()

  def skip_classes_text(source) do
    case option(source, "skip_classes") do
      nil -> Composer.default_skip_classes_text()
      list when is_list(list) -> Enum.join(list, ", ")
      text when is_binary(text) -> text
      _ -> Composer.default_skip_classes_text()
    end
  end

  @spec known_body_schema?(String.t() | nil, Source.t() | map() | nil) :: boolean()
  def known_body_schema?(selector, source) do
    sel = selector |> to_string() |> String.trim()
    url = source && Map.get(source, :url)

    BodySchema.known_selector?(sel) or
      (sel == "" and is_binary(BodySchema.selector_for_url(url)))
  end

  @doc """
  Sentinel `start_guid` value meaning: skip everything currently in the feed
  and only import articles published after `start_published_at` / now.
  """
  @spec future_only_guid() :: String.t()
  def future_only_guid, do: @future_only_guid

  @spec future_only_guid?(term()) :: boolean()
  def future_only_guid?(value), do: value == @future_only_guid

  @spec start_label(Source.t() | map(), String.t() | nil, String.t() | nil) :: String.t()
  def start_label(source, start_guid, start_at) do
    options = Map.get(source, :options) || %{}
    stored_guid = options["start_guid"]

    cond do
      future_only_guid?(start_guid) ->
        case start_at not in [nil, ""] && start_at do
          stamp when is_binary(stamp) -> "only future articles (after #{stamp})"
          _ -> "only future articles"
        end

      start_guid not in [nil, ""] ->
        start_guid

      start_at not in [nil, ""] ->
        "only future articles (after #{start_at})"

      match?(%DateTime{}, Map.get(source, :publish_after_date)) and stored_guid in [nil, ""] ->
        "only future articles (after #{datetime_value(source.publish_after_date)})"

      source.publish_after_date ->
        datetime_value(source.publish_after_date)

      true ->
        "beginning of the feed"
    end
  end

  @spec datetime_value(DateTime.t() | String.t() | nil) :: String.t()
  def datetime_value(nil), do: ""
  def datetime_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def datetime_value(value) when is_binary(value), do: value

  @spec relay_target_label(atom()) :: String.t()
  def relay_target_label(:draft), do: "Draft relays"
  def relay_target_label(:public), do: "Public relays"
  def relay_target_label(_), do: "Test relays"

  @spec relay_badge_class(atom()) :: String.t()
  def relay_badge_class(:public), do: "badge-public"
  def relay_badge_class(_), do: "badge-test"

  @spec relay_target_name(atom()) :: String.t()
  def relay_target_name(:draft), do: "draft relays"
  def relay_target_name(:public), do: "public relays"
  def relay_target_name(_), do: "test relays"

  @spec avatar_relays() :: String.t()
  def avatar_relays do
    (Relays.draft() ++ Relays.test() ++ Relays.public())
    |> Enum.uniq()
    |> Enum.take(4)
    |> Enum.join(",")
  end

  @spec avatar_placeholder() :: String.t()
  def avatar_placeholder, do: @avatar_placeholder
  @spec author_pubkey(map()) :: String.t() | nil
  def author_pubkey(source), do: Signer.author_pubkey(source)
  @spec target_for(map()) :: atom()
  def target_for(source), do: Relays.target_for(source)

  @spec language_options(String.t() | nil) :: [{String.t(), String.t()}]
  def language_options(selected) do
    selected = selected || "de"
    choices = Language.choices()

    if Enum.any?(choices, fn {code, _} -> code == selected end) do
      choices
    else
      [{selected, selected} | choices]
    end
  end

  @spec shorten_npub(String.t() | nil) :: String.t() | nil
  def shorten_npub(nil), do: nil

  def shorten_npub(npub) when is_binary(npub) and byte_size(npub) > 16 do
    String.slice(npub, 0, 8) <> "…" <> String.slice(npub, -8, 8)
  end

  def shorten_npub(npub), do: npub

  @spec error_text(nil | [String.t()] | String.t()) :: String.t() | nil
  def error_text(nil), do: nil
  def error_text(msgs) when is_list(msgs), do: Enum.join(msgs, ", ")
  def error_text(msg), do: to_string(msg)

  @spec changeset_errors(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  @spec format_update_error(Ecto.Changeset.t() | String.t() | atom()) :: String.t()
  def format_update_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> changeset_errors()
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{error_text(msgs)}" end)
  end

  def format_update_error(reason), do: to_string(reason)

  @spec apply_query_flash(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def apply_query_flash(socket, params) do
    notice = params["notice"]

    cond do
      notice in [nil, ""] and params["saved"] == "1" ->
        LiveView.put_flash(socket, :info, "Settings saved.")

      notice in [nil, ""] ->
        socket

      params["notice_kind"] == "error" ->
        LiveView.put_flash(socket, :error, notice)

      params["notice_kind"] == "warning" ->
        LiveView.put_flash(socket, :warning, notice)

      true ->
        LiveView.put_flash(socket, :info, notice)
    end
  end

  @spec import_notice(import_notice_result()) :: String.t()
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

  @spec publish_notice(publish_notice_result()) :: {:info | :warning | :error, String.t()}
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

  @spec reprocess_notice(reprocess_notice_result()) :: String.t()
  def reprocess_notice(result) do
    "Reprocessed #{result.processed}. Failed #{result.errors}."
  end

  @spec reprocessable?(Rss2Nostr.Posts.Post.t()) :: boolean()
  def reprocessable?(%Post{} = post) do
    post.status in [Post.status_processed(), Post.status_pending_images(), Post.status_error()]
  end

  @spec publishable?(Rss2Nostr.Posts.Post.t()) :: boolean()
  def publishable?(%Post{} = post), do: post.status == Post.status_processed()

  @spec join_tags(nil | [String.t()] | String.t()) :: String.t()
  def join_tags(nil), do: ""
  def join_tags(list) when is_list(list), do: Enum.join(list, ", ")
  def join_tags(value), do: to_string(value)

  @spec source_path(Rss2Nostr.Sources.Source.t(), String.t()) :: String.t()
  def source_path(%Source{id: id}, tab)
      when tab in ["feed", "compose", "articles", "publishing"] do
    "/sources/#{id}?tab=#{tab}"
  end

  def source_path(%Source{id: id}, _tab), do: "/sources/#{id}"

  @spec post_preview_href(Source.t() | map(), Rss2Nostr.Posts.Post.t()) :: String.t()
  def post_preview_href(source, post) do
    "/posts/#{post.id}?return_to=" <>
      URI.encode_www_form("/sources/#{source.id}?tab=articles")
  end

  @spec posts_path(keyword()) :: String.t()
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

  @spec format_interval(integer() | nil) :: String.t()
  def format_interval(ms) when is_integer(ms) do
    cond do
      rem(ms, 3_600_000) == 0 -> "#{div(ms, 3_600_000)}h"
      rem(ms, 60_000) == 0 -> "#{div(ms, 60_000)}m"
      rem(ms, 1000) == 0 -> "#{div(ms, 1000)}s"
      true -> "#{ms}ms"
    end
  end

  def format_interval(other), do: to_string(other || "-")

  @spec format_last_run(DateTime.t() | nil | String.t()) :: String.t()
  def format_last_run(nil), do: "Never"
  def format_last_run(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  def format_last_run(other), do: to_string(other)

  @spec format_last_result(nil | map()) :: String.t()
  def format_last_result(nil), do: "—"
  def format_last_result(%{error: reason}), do: "Error: #{reason}"
  def format_last_result(%{deleted: d, skipped: s}), do: "#{d} deleted, #{s} waiting"
  def format_last_result(%{imported: i, errors: e}), do: "#{i} imported, #{e} errors"
  def format_last_result(%{processed: p, errors: e}), do: "#{p} processed, #{e} errors"
  def format_last_result(%{published: p, errors: e}), do: "#{p} published, #{e} errors"
  def format_last_result(map) when is_map(map), do: inspect(map)

  @spec scheduler_status_class(atom()) :: String.t()
  def scheduler_status_class(status) do
    case status do
      :completed -> "badge-success"
      :running -> "badge-processing"
      :failed -> "badge-error"
      _ -> "badge-idle"
    end
  end
end
