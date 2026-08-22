defmodule Rss2Nostr.Processing.HtmlToMarkdown.EmbedUrls do
  @moduledoc false

  alias Rss2Nostr.Processing.Youtube

  @type video_key :: {String.t(), String.t()}

  @doc """
  Turns an embed iframe `src` into a watch-page URL when the host is known.
  YouTube is handled separately via `iframe_watch_url/1`.
  """
  @spec embed_watch_url(String.t() | nil) :: String.t() | nil
  def embed_watch_url(src) when is_binary(src) and src != "" do
    decoded = safe_decode_uri(src)
    uri = URI.parse(decoded)
    host = uri.host |> to_string() |> String.downcase()
    path = uri.path || ""

    cond do
      String.contains?(host, "odysee.com") ->
        odysee_watch_url(uri, path)

      String.contains?(host, "bitchute.com") ->
        bitchute_watch_url(uri, path)

      String.contains?(host, "rumble.com") ->
        rumble_watch_url(uri, path)

      String.contains?(host, "archive.org") ->
        archive_watch_url(uri, path)

      String.contains?(host, "rokfin.com") ->
        rokfin_watch_url(uri, path)

      true ->
        nil
    end
  rescue
    _ -> nil
  end

  def embed_watch_url(_), do: nil

  @doc """
  Watch-page URL for an iframe `src`, including YouTube.
  """
  @spec iframe_watch_url(String.t() | nil) :: String.t() | nil
  def iframe_watch_url(src) when is_binary(src) do
    cond do
      id = Youtube.video_id(src) -> "https://www.youtube.com/watch?v=#{id}"
      watch = embed_watch_url(src) -> watch
      true -> nil
    end
  end

  def iframe_watch_url(_), do: nil

  @doc """
  True when two URLs likely point at the same video (same host and
  video id / last path token).
  """
  @spec same_video?(String.t() | nil, String.t() | nil) :: boolean()
  def same_video?(a, b) when is_binary(a) and is_binary(b) do
    case {video_key(a), video_key(b)} do
      {{host, id}, {host, id}} when is_binary(id) and id != "" -> true
      _ -> false
    end
  end

  def same_video?(_, _), do: false

  @doc """
  Canonical Podbean episode URL from a player or page URL.
  """
  @spec podbean_episode_url(String.t()) :: String.t() | nil
  def podbean_episode_url(src) when is_binary(src) do
    decoded = unescape_attr(src)
    uri = URI.parse(decoded)
    query = uri.query || ""

    cond do
      id = podbean_player_id(query) ->
        "https://www.podbean.com/ep/pb-#{id}"

      id = podbean_path_id(uri.path) ->
        "https://www.podbean.com/ep/pb-#{id}"

      true ->
        nil
    end
  rescue
    _ -> nil
  end

  @spec platform_name(String.t()) :: String.t()
  def platform_name(url) do
    host = url |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()

    cond do
      String.contains?(host, "odysee.com") -> "Odysee"
      String.contains?(host, "bitchute.com") -> "Bitchute"
      String.contains?(host, "rumble.com") -> "Rumble"
      String.contains?(host, "archive.org") -> "Archive.org"
      String.contains?(host, "rokfin.com") -> "Rokfin"
      true -> "video"
    end
  rescue
    _ -> "video"
  end

  @spec video_key(String.t()) :: video_key() | nil
  defp video_key(url) do
    watch = iframe_watch_url(url) || url
    uri = URI.parse(watch)
    host = normalize_video_host(uri.host)
    id = video_id_token(uri, watch)

    if host != "" and is_binary(id) and id != "", do: {host, id}, else: nil
  rescue
    _ -> nil
  end

  defp video_id_token(uri, url) do
    case Youtube.video_id(url) do
      id when is_binary(id) -> String.downcase(id)
      _ -> last_significant_token(uri)
    end
  end

  defp last_significant_token(uri) do
    (uri.path || "")
    |> String.split("/", trim: true)
    |> Enum.reject(&(String.downcase(&1) in ~w($ embed video details watch post v)))
    |> List.last()
    |> case do
      nil ->
        nil

      seg ->
        seg
        |> URI.decode()
        |> String.trim_leading("@")
        |> String.split(":")
        |> hd()
        |> String.downcase()
    end
  rescue
    _ -> nil
  end

  defp normalize_video_host(host) do
    host
    |> to_string()
    |> String.downcase()
    |> String.replace_prefix("www.", "")
    |> String.replace_prefix("old.", "")
    |> String.replace_prefix("m.", "")
  end

  defp odysee_watch_url(uri, path) do
    rest =
      cond do
        String.starts_with?(path, "/$/embed/") -> String.replace_prefix(path, "/$/embed/", "")
        String.starts_with?(path, "/embed/") -> String.replace_prefix(path, "/embed/", "")
        true -> nil
      end

    cond do
      is_binary(rest) and rest != "" ->
        uri_watch(uri, "/" <> rest)

      path not in ["", "/"] ->
        uri_watch(uri, path)

      true ->
        nil
    end
  end

  defp bitchute_watch_url(uri, path) do
    case Regex.run(~r{/embed/([^/]+)/?}, path) do
      [_, id] -> uri_watch(uri, "/video/#{id}/")
      _ -> uri_watch(uri, path)
    end
  end

  defp rumble_watch_url(uri, path) do
    case Regex.run(~r{/embed/([^/]+)/?}, path) do
      [_, id] -> uri_watch(uri, "/embed/#{id}")
      _ -> uri_watch(uri, path)
    end
  end

  defp archive_watch_url(uri, path) do
    case Regex.run(~r{/embed/([^/]+)/?}, path) do
      [_, id] -> uri_watch(uri, "/details/#{id}")
      _ -> uri_watch(uri, path)
    end
  end

  defp rokfin_watch_url(uri, path) do
    case Regex.run(~r{/embed/(?:post/)?([^/]+)/?}, path) do
      [_, id] -> uri_watch(uri, "/post/#{id}")
      _ -> uri_watch(uri, path)
    end
  end

  defp uri_watch(uri, path) do
    URI.to_string(%{uri | path: path, query: nil, fragment: nil})
  end

  defp safe_decode_uri(url) do
    decoded = URI.decode(url)
    if decoded == url, do: url, else: safe_decode_uri(decoded)
  rescue
    _ -> url
  end

  defp podbean_player_id(query) do
    id =
      query
      |> URI.decode_query()
      |> Map.get("i")

    cond do
      is_binary(id) and id != "" -> String.replace_suffix(id, "-pb", "")
      true -> nil
    end
  end

  defp podbean_path_id(path) when is_binary(path) do
    case Regex.run(~r{(?:^|/)pb-([A-Za-z0-9]+-[A-Za-z0-9]+)(?:/|$)}, path) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp podbean_path_id(_), do: nil

  defp unescape_attr(value) when is_binary(value) do
    value
    |> String.replace("&amp;", "&")
    |> String.replace("&#038;", "&")
    |> String.replace("&#38;", "&")
  end
end
