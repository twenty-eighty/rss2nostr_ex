defmodule Rss2Nostr.Processing.HtmlToMarkdown.Links do
  @moduledoc false

  @fa_brand_cdn "https://cdn.jsdelivr.net/npm/@fortawesome/fontawesome-free@6.7.2/svgs/brands"

  @fa_networks [
    {"telegram", "Telegram"},
    {"twitter", "Twitter"},
    {"x-twitter", "X"},
    {"facebook", "Facebook"},
    {"instagram", "Instagram"},
    {"youtube", "YouTube"},
    {"mastodon", "Mastodon"},
    {"whatsapp", "WhatsApp"},
    {"signal", "Signal"}
  ]

  @platform_hosts [
    {"facebook.com", "Facebook", "facebook"},
    {"fb.com", "Facebook", "facebook"},
    {"instagram.com", "Instagram", "instagram"},
    {"twitter.com", "Twitter", "x-twitter"},
    {"x.com", "X", "x-twitter"},
    {"t.me", "Telegram", "telegram"},
    {"telegram.me", "Telegram", "telegram"},
    {"telegram.org", "Telegram", "telegram"}
  ]

  @platform_url_re ~r{(?:https?://)?(?:www\.)?(?:facebook\.com|fb\.com|instagram\.com|twitter\.com|x\.com|t\.me|telegram\.me)/[^\s<>\]\)]+}i
  @tweet_status_url_re ~r{\Ahttps?://(?:www\.|mobile\.)?(?:x\.com|twitter\.com)/[^/\s]+/status/\d+\z}i

  @type icon_order :: :icon_first | :label_first

  @spec social_bar_class?(String.t()) :: boolean()
  def social_bar_class?(class) when is_binary(class) do
    class
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.any?(fn token ->
      token in ~w(social-bar social-icons social-links social-media) or
        String.starts_with?(token, "social-")
    end)
  end

  def social_bar_class?(_), do: false

  @spec icon_class?(String.t()) :: boolean()
  def icon_class?(class) do
    Enum.any?(class_tokens(class), fn token ->
      token in ~w(fa fab fas far fal fad icon dashicons material-icons) or
        String.starts_with?(token, "fa-") or
        String.starts_with?(token, "icon-")
    end)
  end

  @spec normalize_href(String.t() | nil) :: String.t() | nil
  def normalize_href(href) when is_binary(href) do
    case String.replace(href, ~r/\s+/, "") do
      "" -> nil
      "mailto:" <> rest -> "mailto:" <> normalize_mailto_target(rest)
      url -> url
    end
  end

  def normalize_href(_), do: nil

  @spec ensure_absolute_url(String.t()) :: String.t()
  def ensure_absolute_url(url) when is_binary(url) do
    cond do
      String.match?(url, ~r/\A[a-z][a-z0-9+.-]*:/i) -> url
      String.starts_with?(url, "/") -> url
      String.contains?(url, ".") -> "https://" <> url
      true -> url
    end
  end

  def ensure_absolute_url(url), do: url

  @spec platform_for_href(String.t()) :: {String.t(), String.t()} | nil
  def platform_for_href(href) when is_binary(href) do
    host =
      href
      |> ensure_absolute_url()
      |> URI.parse()
      |> Map.get(:host)
      |> to_string()
      |> String.downcase()
      |> String.replace_prefix("www.", "")

    Enum.find_value(@platform_hosts, fn {name, label, slug} ->
      if host == name or String.ends_with?(host, "." <> name) do
        {label, slug}
      end
    end)
  rescue
    _ -> nil
  end

  def platform_for_href(_), do: nil

  @spec tweet_status_link?(String.t()) :: boolean()
  def tweet_status_link?(href) when is_binary(href) do
    Regex.match?(@tweet_status_url_re, String.trim(href))
  end

  def tweet_status_link?(_), do: false

  @spec strip_url_noise(String.t()) :: String.t()
  def strip_url_noise(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace_prefix("https://", "")
    |> String.replace_prefix("http://", "")
    |> String.replace_prefix("www.", "")
    |> String.trim_trailing("/")
  end

  @spec autolink_platform_urls(String.t()) :: String.t()
  def autolink_platform_urls(text) do
    trimmed = String.trim(text)

    if Regex.match?(@tweet_status_url_re, trimmed) do
      trimmed
    else
      Regex.replace(@platform_url_re, text, fn url ->
        {bare, trail} = split_url_trail(url)
        href = ensure_absolute_url(bare)

        case platform_for_href(href) do
          {label, slug} -> markdown_icon_link(href, label, fa_brand_url(slug)) <> trail
          _ -> url
        end
      end)
    end
  end

  @spec markdown_icon_link(String.t(), String.t(), String.t() | nil, icon_order()) :: String.t()
  def markdown_icon_link(href, label, icon_url, order \\ :icon_first)

  def markdown_icon_link(href, label, icon_url, order) do
    cond do
      not present_title?(icon_url) ->
        "[#{label}](#{href})"

      present_title?(label) and label != href ->
        case order do
          :label_first -> "[#{label} ![](#{icon_url})](#{href})"
          _ -> "[![](#{icon_url}) #{label}](#{href})"
        end

      true ->
        "[![#{label}](#{icon_url})](#{href})"
    end
  end

  @spec link_icon_order(list(), String.t()) :: icon_order()
  def link_icon_order(_nodes, ""), do: :icon_first

  def link_icon_order(nodes, _text) do
    case first_link_signal(nodes) do
      :text -> :label_first
      _ -> :icon_first
    end
  end

  @spec network_icon_url(list(), String.t(), String.t()) :: String.t() | nil
  def network_icon_url(nodes, _label, href) do
    case fa_brand_slug(nodes) do
      slug when is_binary(slug) and slug != "" ->
        fa_brand_url(slug)

      _ ->
        case platform_for_href(href) do
          {_label, slug} -> fa_brand_url(slug)
          _ -> nil
        end
    end
  end

  @spec icon_network_label(list()) :: String.t() | nil
  def icon_network_label(nodes) do
    classes = element_classes(nodes)

    Enum.find_value(@fa_networks, fn {name, label} ->
      if Enum.any?(classes, &(String.starts_with?(&1, "fa") and String.contains?(&1, name))) do
        label
      end
    end)
  end

  @spec fa_brand_url(String.t()) :: String.t()
  def fa_brand_url(slug), do: "#{@fa_brand_cdn}/#{slug}.svg"

  @spec fa_brand_slug(list()) :: String.t() | nil
  defp fa_brand_slug(nodes) do
    skip = MapSet.new(~w(lg sm xs 2x 3x 4x 5x fw spin pulse border))

    nodes
    |> element_classes()
    |> Enum.find_value(fn
      "fa-" <> rest when rest != "" ->
        cond do
          rest in skip -> nil
          String.contains?(rest, "telegram") -> "telegram"
          rest in ~w(twitter x-twitter) -> "x-twitter"
          true -> rest
        end

      _ ->
        nil
    end)
  end

  @spec first_link_signal(list()) :: :icon | :text | nil
  defp first_link_signal(nodes) do
    Enum.find_value(List.wrap(nodes), fn
      {tag, attrs, inner} when tag in ~w(i em span) ->
        cond do
          icon_class?(attr(attrs, "class", "")) ->
            :icon

          String.trim(Floki.text(inner)) != "" ->
            :text

          true ->
            first_link_signal(inner)
        end

      {_, _, inner} ->
        first_link_signal(inner)

      text when is_binary(text) ->
        if String.trim(text) == "", do: nil, else: :text

      _ ->
        nil
    end)
  end

  @spec element_classes(list()) :: [String.t()]
  defp element_classes(nodes) do
    Enum.flat_map(List.wrap(nodes), fn
      {_, attrs, inner} ->
        class_tokens(attr(attrs, "class", "")) ++ element_classes(inner)

      _ ->
        []
    end)
  end

  @spec class_tokens(term()) :: [String.t()]
  defp class_tokens(class) when is_binary(class) do
    class |> String.downcase() |> String.split(~r/\s+/, trim: true)
  end

  defp class_tokens(_), do: []

  @spec split_url_trail(String.t()) :: {String.t(), String.t()}
  defp split_url_trail(url) do
    case Regex.run(~r/\A(.*?)([.,;:!?]+)\z/, url) do
      [_, bare, trail] -> {bare, trail}
      _ -> {url, ""}
    end
  end

  @spec normalize_mailto_target(String.t()) :: String.t()
  defp normalize_mailto_target(rest) do
    {address, suffix} =
      case String.split(rest, "?", parts: 2) do
        [address, query] -> {address, "?" <> query}
        [address] -> {address, ""}
      end

    (address |> URI.decode() |> String.trim()) <> suffix
  end

  @spec present_title?(term()) :: boolean()
  defp present_title?(title) when is_binary(title), do: String.trim(title) != ""
  defp present_title?(_), do: false

  @spec attr(list(), String.t(), term()) :: term()
  defp attr(attrs, name, default) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> default
    end
  end
end
