defmodule Rss2Nostr.Processing.HtmlToMarkdown.Embeds do
  @moduledoc false

  @parent Rss2Nostr.Processing.HtmlToMarkdown

  alias Rss2Nostr.Processing.{Labels, Youtube}
  alias Rss2Nostr.Processing.HtmlToMarkdown.{Dom, EmbedUrls, SoundcloudPermalink, TrackingParams}

  @spec process_iframe(list()) :: String.t()
  def process_iframe(attrs) do
    src = iframe_src(attrs)

    cond do
      src == "" ->
        ""

      String.contains?(src, "youtube.com") || String.contains?(src, "youtu.be") ->
        youtube_markdown(src, Dom.get_attr(attrs, "title"))

      String.contains?(src, "podbean.com") ->
        process_podbean_iframe(src)

      String.contains?(src, "soundcloud.com") ->
        url =
          Process.get({@parent, :soundcloud_permalink}) ||
            SoundcloudPermalink.player_permalink(src) ||
            src

        soundcloud_listen_markdown(url)

      watch = EmbedUrls.embed_watch_url(src) ->
        "\n\n[#{watch_on(EmbedUrls.platform_name(watch))}](#{watch})\n\n"

      true ->
        ""
    end
  end

  @spec process_youtube_div(list(), list()) :: String.t()
  def process_youtube_div(attrs, _children) do
    data_attrs = Dom.get_attr(attrs, "data-attrs", "")

    if data_attrs != "" do
      case Jason.decode(data_attrs) do
        {:ok, %{"videoId" => video_id} = data} ->
          text =
            Youtube.meaningful_title(data["title"] || data["videoTitle"]) || watch_on("YouTube")

          "\n\n[#{text}](https://www.youtube.com/watch?v=#{video_id})\n\n"

        _ ->
          ""
      end
    else
      ""
    end
  end

  @spec process_powerpress_div(list()) :: String.t()
  def process_powerpress_div(children) do
    audio = Dom.find_element(children, "audio")

    src =
      case audio do
        {"audio", attrs, audio_children} ->
          Dom.get_attr(attrs, "src") || find_source_src(audio_children)

        _ ->
          nil
      end

    if src do
      clean_src = TrackingParams.remove(src)
      "\n\n[#{audio_label()}](#{clean_src})\n\n"
    else
      ""
    end
  end

  @spec process_audio(list(), list()) :: String.t()
  def process_audio(attrs, children) do
    src = Dom.get_attr(attrs, "src") || find_source_src(children)

    if src do
      clean_src = TrackingParams.remove(src)
      "\n\n[#{audio_label()}](#{clean_src})\n\n"
    else
      ""
    end
  end

  @spec process_video(list(), list()) :: String.t()
  def process_video(attrs, children) do
    src = Dom.get_attr(attrs, "src") || find_source_src(children)

    if src do
      clean_src = TrackingParams.remove(src)
      "\n\n[#{video_label()}](#{clean_src})\n\n"
    else
      ""
    end
  end

  @spec maybe_prepend_soundcloud(String.t(), String.t() | nil) :: String.t()
  def maybe_prepend_soundcloud(markdown, permalink) when is_binary(permalink) do
    href = with_soundcloud_params(permalink)

    if String.contains?(markdown, permalink) or String.contains?(markdown, href) do
      markdown
    else
      "[#{listen_on("SoundCloud")}](#{href})\n\n" <> markdown
    end
  end

  def maybe_prepend_soundcloud(markdown, _), do: markdown

  @spec soundcloud_widget_chrome?(String.t()) :: boolean()
  def soundcloud_widget_chrome?(href) do
    case Process.get({@parent, :soundcloud_permalink}) do
      permalink when is_binary(permalink) ->
        soundcloud_host?(href) and
          (same_soundcloud_url?(href, permalink) or soundcloud_profile_of?(href, permalink))

      _ ->
        false
    end
  end

  @spec soundcloud_widget_div?(list()) :: boolean()
  def soundcloud_widget_div?(children) do
    case Process.get({@parent, :soundcloud_permalink}) do
      permalink when is_binary(permalink) ->
        hrefs = collect_hrefs(children)

        hrefs != [] and
          Enum.all?(hrefs, &soundcloud_widget_chrome?/1) and
          not has_paragraph?(children) and
          chrome_only_text?(children)

      _ ->
        false
    end
  end

  @spec with_soundcloud_params(String.t()) :: String.t()
  def with_soundcloud_params(url) when is_binary(url) do
    case Process.get({@parent, :soundcloud_color}) do
      color when is_binary(color) -> put_soundcloud_query(url, "color", color)
      _ -> url
    end
  end

  @spec soundcloud_host?(String.t()) :: boolean()
  def soundcloud_host?(url), do: SoundcloudPermalink.host?(url)

  @spec summary_soundcloud_chrome?({String.t(), list(), list()}) :: boolean()
  def summary_soundcloud_chrome?({tag, attrs, children}) do
    style = attrs |> Dom.get_attr("style", "") |> String.downcase()
    hrefs = collect_hrefs(children)
    soundcloud_links? = hrefs != [] and Enum.all?(hrefs, &soundcloud_host?/1)

    cond do
      not soundcloud_links? ->
        false

      String.contains?(style, "font-size: 10px") or String.contains?(style, "font-size:10px") ->
        true

      tag in ["div", "span"] and not has_paragraph?(children) and chrome_only_text?(children) ->
        true

      true ->
        false
    end
  end

  defp youtube_markdown(url, title) do
    case Youtube.video_id(url) do
      nil ->
        ""

      video_id ->
        text = Youtube.meaningful_title(title) || watch_on("YouTube")
        "\n\n[#{text}](https://www.youtube.com/watch?v=#{video_id})\n\n"
    end
  end

  defp process_podbean_iframe(src) do
    case EmbedUrls.podbean_episode_url(src) do
      url when is_binary(url) ->
        "\n\n[#{listen_on("Podbean")}](#{url})\n\n"

      _ ->
        "\n\n[#{listen_on("Podbean")}](#{src})\n\n"
    end
  end

  defp iframe_src(attrs) do
    [Dom.get_attr(attrs, "src"), Dom.get_attr(attrs, "data-src")]
    |> Enum.find(&(is_binary(&1) and String.trim(&1) != ""))
    |> case do
      nil -> ""
      src -> unescape_attr(src)
    end
  end

  defp unescape_attr(value) when is_binary(value) do
    value
    |> String.replace("&amp;", "&")
    |> String.replace("&#038;", "&")
    |> String.replace("&#38;", "&")
  end

  defp unescape_attr(_), do: ""

  defp soundcloud_listen_markdown(url) when is_binary(url) and url != "" do
    "\n\n[#{listen_on("SoundCloud")}](#{with_soundcloud_params(url)})\n\n"
  end

  defp soundcloud_listen_markdown(_), do: ""

  defp same_soundcloud_url?(a, b) do
    normalize_soundcloud_url(a) == normalize_soundcloud_url(b)
  end

  defp soundcloud_profile_of?(href, permalink) do
    href_path =
      href |> URI.parse() |> Map.get(:path) |> to_string() |> String.split("/", trim: true)

    perm_path =
      permalink |> URI.parse() |> Map.get(:path) |> to_string() |> String.split("/", trim: true)

    case href_path do
      [user] -> match?([^user | _], perm_path)
      _ -> false
    end
  end

  defp normalize_soundcloud_url(url) do
    uri = URI.parse(url)
    host = uri.host |> to_string() |> String.downcase() |> String.replace_prefix("www.", "")
    path = uri.path |> to_string() |> String.trim_trailing("/")
    "https://#{host}#{path}"
  end

  defp put_soundcloud_query(url, key, value) do
    if soundcloud_host?(url) do
      uri = URI.parse(url)

      query =
        (uri.query || "")
        |> URI.decode_query()
        |> Map.put(key, value)

      URI.to_string(%{uri | query: URI.encode_query(query)})
    else
      url
    end
  end

  defp find_source_src(children) do
    source = Dom.find_element(children, "source")

    case source do
      {"source", attrs, _} -> Dom.get_attr(attrs, "src")
      _ -> nil
    end
  end

  defp chrome_only_text?(children) do
    text =
      children
      |> Floki.text()
      |> String.replace("·", " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    labels =
      children
      |> collect_anchor_nodes()
      |> Enum.map(&Floki.text/1)
      |> Enum.join(" ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    text == "" or text == labels
  end

  defp collect_hrefs(nodes) do
    nodes
    |> collect_anchor_nodes()
    |> Enum.map(fn {"a", attrs, _} -> Dom.get_attr(attrs, "href") end)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
  end

  defp collect_anchor_nodes(nodes) when is_list(nodes),
    do: Enum.flat_map(nodes, &collect_anchor_nodes/1)

  defp collect_anchor_nodes({"a", _, _} = node), do: [node]

  defp collect_anchor_nodes({_, _, children}) when is_list(children),
    do: collect_anchor_nodes(children)

  defp collect_anchor_nodes(_), do: []

  defp has_paragraph?(nodes) when is_list(nodes) do
    Enum.any?(nodes, fn
      {"p", _, children} -> String.trim(Floki.text(children)) != ""
      {_, _, children} -> has_paragraph?(children)
      _ -> false
    end)
  end

  defp has_paragraph?(_), do: false

  defp language do
    Process.get({@parent, :language}, "en")
  end

  defp listen_on(platform), do: Labels.t(:listen_on, language(), platform: platform)
  defp watch_on(platform), do: Labels.t(:watch_on, language(), platform: platform)
  defp audio_label, do: Labels.t(:audio, language())
  defp video_label, do: Labels.t(:video, language())
end
