defmodule Rss2Nostr.Web.Views.Sources.Helpers do
  @moduledoc false

  alias Rss2Nostr.Nostr.{Relays, Signer}
  alias Rss2Nostr.Processing.{BodySchema, Composer}
  alias Rss2Nostr.Sources.Source

  @avatar_placeholder "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='32' height='32'%3E%3Crect fill='%23e5e7eb' width='32' height='32' rx='16'/%3E%3C/svg%3E"

  @spec escape_html(String.t() | nil) :: String.t()
  def escape_html(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  def escape_html(nil), do: ""

  @spec escape_attr(term()) :: String.t()
  def escape_attr(nil), do: ""

  def escape_attr(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
  end

  def escape_attr(_), do: ""

  @spec error_message(map(), atom()) :: String.t()
  def error_message(errors, field) do
    case errors[field] do
      nil -> ""
      msgs when is_list(msgs) -> "<span class=\"error\">#{Enum.join(msgs, ", ")}</span>"
      msg -> "<span class=\"error\">#{msg}</span>"
    end
  end

  @spec flash_notice(term(), term()) :: String.t()
  def flash_notice(nil, _), do: ""
  def flash_notice("", _), do: ""

  def flash_notice(notice, kind) do
    class =
      case kind do
        "error" -> "error"
        "warning" -> "warning"
        _ -> "success"
      end

    ~s(<p class="#{class}">#{escape_html(notice)}</p>)
  end

  @spec truncate(String.t() | nil, integer()) :: String.t()
  def truncate(str, max) when is_binary(str) do
    if String.length(str) > max do
      String.slice(str, 0, max) <> "..."
    else
      str
    end
  end

  def truncate(nil, _max), do: ""

  @spec datetime_value(term()) :: String.t()
  def datetime_value(nil), do: ""
  def datetime_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def datetime_value(value) when is_binary(value), do: value

  @spec format_datetime(nil | DateTime.t()) :: String.t()
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

  @spec option(Source.t() | nil, String.t()) :: term()
  def option(nil, _key), do: nil

  def option(source, key) do
    options = source.options || %{}
    options[key]
  end

  @spec skip_classes_text(Source.t() | nil) :: String.t()
  def skip_classes_text(nil), do: Composer.default_skip_classes_text()

  def skip_classes_text(source) do
    case option(source, "skip_classes") do
      nil -> Composer.default_skip_classes_text()
      list when is_list(list) -> Enum.join(list, ", ")
      text when is_binary(text) -> text
      _ -> Composer.default_skip_classes_text()
    end
  end

  @spec known_body_schema?(String.t(), Source.t() | nil) :: boolean()
  def known_body_schema?(selector, source) do
    sel = selector |> to_string() |> String.trim()
    url = source && Map.get(source, :url)

    BodySchema.known_selector?(sel) or
      (sel == "" and is_binary(BodySchema.selector_for_url(url)))
  end

  @spec start_label(Source.t(), term(), term()) :: String.t()
  def start_label(source, start_guid, start_at) do
    cond do
      start_guid not in [nil, ""] -> start_guid
      start_at not in [nil, ""] -> start_at
      source.publish_after_date -> datetime_value(source.publish_after_date)
      true -> "beginning of the feed"
    end
  end

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

  @spec source_name_cell(Source.t()) :: String.t()
  def source_name_cell(source) do
    pubkey = Signer.author_pubkey(source)
    attrs = if pubkey, do: ~s( data-pubkey="#{escape_attr(pubkey)}"), else: ""

    """
    <div class="source-author">
      <img class="source-avatar" src="#{@avatar_placeholder}" alt="" width="32" height="32"#{attrs}
           onerror="this.onerror=null;this.src='#{@avatar_placeholder}'">
      <span>#{escape_html(source.name)}</span>
    </div>
    """
  end
end
