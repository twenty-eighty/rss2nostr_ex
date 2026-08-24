defmodule Rss2Nostr.Processing.Conversion do
  @moduledoc """
  Visual HTML-to-Markdown conversion rules.

  A rule is an XPath match plus an action. Stored rules such as
  `//p[contains(., 'WATCH ON:')]` still apply `links_as_paragraphs`
  to matching elements. Corbett “WATCH ON:” rows are rewritten in
  `Rss2Nostr.Processing.Sites.Corbett` instead of a compose-page toggle.
  """

  @type rule :: %{
          required(:action) => String.t(),
          required(:xpath) => String.t(),
          optional(:label) => String.t()
        }

  @type xpath_spec :: %{
          tag: String.t(),
          contains_text: String.t() | nil,
          contains_class: String.t() | nil,
          class: String.t() | nil
        }

  @type link_group :: %{
          xpath: String.t(),
          description: String.t(),
          snippet: String.t(),
          links: [%{text: String.t(), href: String.t()}],
          enabled: boolean()
        }

  @generic_classes ~w(p div span strong em b i text content node wp-block-image)

  @spec parse_rules(term()) :: [rule()]
  def parse_rules(nil), do: []
  def parse_rules(""), do: []

  def parse_rules(list) when is_list(list) do
    Enum.flat_map(list, &normalize_rule/1)
  end

  def parse_rules(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, list} -> parse_rules(list)
      _ -> []
    end
  end

  def parse_rules(_), do: []

  @spec candidates(String.t() | nil, [rule()]) :: [link_group()]
  def candidates(html, rules \\ [])
  def candidates(html, _rules) when html in [nil, ""], do: []

  def candidates(html, rules) when is_binary(html) do
    enabled = MapSet.new(Enum.map(rules, & &1.xpath))

    case Floki.parse_document(html) do
      {:ok, doc} ->
        doc
        |> collect_elements()
        |> Enum.filter(&link_row?/1)
        |> Enum.map(&group_from_node/1)
        |> Enum.uniq_by(& &1.xpath)
        |> Enum.map(fn group ->
          Map.put(group, :enabled, MapSet.member?(enabled, group.xpath))
        end)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  @spec matches?(Floki.html_node(), rule() | map()) :: boolean()
  def matches?({tag, attrs, children}, rule) when is_map(rule) do
    xpath = rule[:xpath] || rule["xpath"]

    case parse_xpath(xpath) do
      {:ok, spec} ->
        (spec.tag == "*" or spec.tag == tag) and predicates_match?({tag, attrs, children}, spec)

      :error ->
        false
    end
  end

  def matches?(_, _), do: false

  @spec links(Floki.html_tree() | Floki.html_node()) :: [{String.t(), String.t()}]
  def links(nodes), do: extract_links(nodes)

  @spec links_as_paragraphs(Floki.html_tree() | [Floki.html_node()], keyword()) :: String.t()
  def links_as_paragraphs(children, opts \\ []) do
    links = extract_links(children)

    if links == [] do
      ""
    else
      heading = Keyword.get(opts, :heading) || row_heading(Floki.text(children))
      blocks = Enum.map(links, fn {text, href} -> "[#{text}](#{href})" end)
      body = Enum.join(blocks, "\n\n")

      if heading do
        "\n\n**#{heading}**\n\n#{body}\n\n"
      else
        "\n\n#{body}\n\n"
      end
    end
  end

  @spec suggest_xpath({String.t(), [{String.t(), String.t()}], [Floki.html_node()]}) ::
          String.t()
  def suggest_xpath({tag, attrs, children}) do
    text = children |> Floki.text() |> normalize_space()
    class = distinctive_class(attrs)
    prefix = distinctive_prefix(text)

    cond do
      prefix != nil ->
        "//#{tag}[contains(., '#{xpath_escape(prefix)}')]"

      class != nil ->
        "//#{tag}[contains(@class, '#{xpath_escape(class)}')]"

      text != "" ->
        snippet = text |> String.slice(0, 32) |> String.trim()
        "//#{tag}[contains(., '#{xpath_escape(snippet)}')]"

      true ->
        "//#{tag}"
    end
  end

  @spec describe_xpath(String.t()) :: String.t()
  def describe_xpath(xpath) when is_binary(xpath) do
    case parse_xpath(xpath) do
      {:ok, spec} ->
        tag = human_tag(spec.tag)

        cond do
          spec.contains_text ->
            "#{tag} containing “#{spec.contains_text}”"

          spec.contains_class ->
            "#{tag} with class #{spec.contains_class}"

          spec.class ->
            "#{tag} with class #{spec.class}"

          true ->
            "All #{tag}"
        end

      :error ->
        xpath
    end
  end

  def describe_xpath(_), do: ""

  @spec normalize_rule(map()) :: [rule()]
  defp normalize_rule(rule) when is_map(rule) do
    xpath = blank_to_nil(rule["xpath"] || rule[:xpath])
    action = rule["action"] || rule[:action] || "links_as_paragraphs"

    if xpath && action == "links_as_paragraphs" do
      [
        %{
          action: "links_as_paragraphs",
          xpath: xpath,
          label: rule["label"] || rule[:label] || "alt"
        }
      ]
    else
      []
    end
  end

  defp normalize_rule(_), do: []

  @spec collect_elements(Floki.html_tree() | [Floki.html_node()]) :: [Floki.html_node()]
  defp collect_elements(nodes) do
    Floki.find(nodes, "p, div, li, section")
  end

  @spec link_row?(Floki.html_node()) :: boolean()
  defp link_row?({_tag, _attrs, children} = node) do
    links = extract_links(children)

    length(links) >= 2 and
      (watch_like?(node) or icon_row?(children) or separator_row?(node) or
         link_text_dominates?(node, links))
  end

  defp link_row?(_), do: false

  @spec watch_like?(Floki.html_node()) :: boolean()
  defp watch_like?({_tag, _attrs, children}) do
    text = children |> Floki.text() |> String.downcase()

    String.contains?(text, "watch on") or
      String.contains?(text, "listen on") or
      String.contains?(text, "play on") or
      String.match?(text, ~r/\bdownload\b/)
  end

  @spec icon_row?([Floki.html_node()]) :: boolean()
  defp icon_row?(children) do
    anchors = find_tags(children, "a")

    anchors != [] and
      Enum.all?(anchors, fn
        {"a", _, a_children} ->
          text = a_children |> Floki.text() |> String.trim()
          has_img? = find_tags(a_children, "img") != []
          has_img? and text == ""

        _ ->
          false
      end)
  end

  @spec separator_row?(Floki.html_node()) :: boolean()
  defp separator_row?({_tag, _attrs, children}) do
    text = children |> Floki.text() |> normalize_space()
    String.contains?(text, " / ") or String.contains?(text, " | ")
  end

  @spec link_text_dominates?(Floki.html_node(), [{String.t(), String.t()}]) :: boolean()
  defp link_text_dominates?({_tag, _attrs, children}, links) do
    full = children |> Floki.text() |> normalize_space()
    labels = links |> Enum.map_join("", &elem(&1, 0)) |> normalize_space()

    full != "" and String.length(labels) / max(String.length(full), 1) >= 0.55
  end

  @spec group_from_node(Floki.html_node()) :: link_group()
  defp group_from_node({_tag, _attrs, children} = node) do
    xpath = suggest_xpath(node)
    links = extract_links(children)

    %{
      xpath: xpath,
      description: describe_xpath(xpath),
      snippet: children |> Floki.text() |> normalize_space() |> String.slice(0, 160),
      links:
        Enum.map(links, fn {text, href} ->
          %{text: text, href: href}
        end),
      enabled: false
    }
  end

  @spec extract_links(Floki.html_tree() | Floki.html_node()) :: [{String.t(), String.t()}]
  defp extract_links(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &extract_links/1)
  end

  defp extract_links({"a", attrs, children}) do
    href = attr(attrs, "href")

    if valid_href?(href) do
      clean = Rss2Nostr.Processing.HtmlToMarkdown.remove_tracking_params(href)
      [{link_label(children, clean), clean}]
    else
      []
    end
  end

  defp extract_links({_tag, _attrs, children}), do: extract_links(children)
  defp extract_links(_), do: []

  @spec link_label([Floki.html_node()], String.t()) :: String.t()
  defp link_label(children, href) do
    alt =
      children
      |> find_tags("img")
      |> Enum.find_value(fn
        {"img", attrs, _} -> blank_to_nil(attr(attrs, "alt"))
        _ -> nil
      end)

    text = children |> Floki.text() |> String.trim() |> blank_to_nil()

    cond do
      alt && String.downcase(alt) not in ["unknown", "link", "click here"] -> alt
      text && String.downcase(text) not in ["unknown", "link", "click here"] -> text
      true -> platform_name(href)
    end
  end

  @spec platform_name(String.t()) :: String.t()
  defp platform_name(url) do
    host = url |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()

    cond do
      String.contains?(host, "archive.org") -> "Archive.org"
      String.contains?(host, "bitchute.com") -> "Bitchute"
      String.contains?(host, "odysee.com") -> "Odysee"
      String.contains?(host, "rumble.com") -> "Rumble"
      String.contains?(host, "substack.com") -> "Substack"
      String.contains?(host, "youtube.com") or String.contains?(host, "youtu.be") -> "YouTube"
      String.contains?(host, "rokfin.com") -> "Rokfin"
      String.ends_with?(url, ".mp4") -> "MP4"
      String.ends_with?(url, ".mp3") -> "Audio"
      true -> "Link"
    end
  rescue
    _ -> "Link"
  end

  @spec valid_href?(term()) :: boolean()
  defp valid_href?(href) do
    is_binary(href) and href != "" and
      not String.starts_with?(href, "/") and
      not String.contains?(String.downcase(href), "not yet available") and
      (String.starts_with?(href, "http://") or String.starts_with?(href, "https://"))
  end

  @spec row_heading(String.t()) :: String.t() | nil
  defp row_heading(text) do
    cond do
      String.match?(text, ~r/watch\s+on\s*:/i) -> "WATCH ON:"
      String.match?(text, ~r/listen\s+on\s*:/i) -> "LISTEN ON:"
      String.match?(text, ~r/play\s+on\s*:/i) -> "PLAY ON:"
      String.match?(text, ~r/download\s*:/i) -> "DOWNLOAD:"
      true -> nil
    end
  end

  @spec distinctive_class([{String.t(), String.t()}]) :: String.t() | nil
  defp distinctive_class(attrs) do
    attrs
    |> attr("class", "")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(String.downcase(&1) in @generic_classes))
    |> List.first()
  end

  @spec distinctive_prefix(String.t()) :: String.t() | nil
  defp distinctive_prefix(text) do
    cond do
      match = Regex.run(~r/(WATCH\s+ON\s*:)/i, text) -> hd(match)
      match = Regex.run(~r/(LISTEN\s+ON\s*:)/i, text) -> hd(match)
      match = Regex.run(~r/(PLAY\s+ON\s*:)/i, text) -> hd(match)
      match = Regex.run(~r/(DOWNLOAD\s*:)/i, text) -> hd(match)
      true -> nil
    end
  end

  @spec parse_xpath(term()) :: {:ok, xpath_spec()} | :error
  defp parse_xpath(xpath) when is_binary(xpath) do
    xpath = String.trim(xpath)

    case Regex.run(~r{^//(\*|[A-Za-z][\w-]*)(?:\[(.*)\])?$}, xpath) do
      [_, tag] ->
        {:ok, %{tag: String.downcase(tag), contains_text: nil, contains_class: nil, class: nil}}

      [_, tag, preds] ->
        {:ok,
         %{
           tag: String.downcase(tag),
           contains_text: xpath_pred(preds, ~r/contains\(\s*\.\s*,\s*'([^']*)'\s*\)/),
           contains_class: xpath_pred(preds, ~r/contains\(\s*@class\s*,\s*'([^']*)'\s*\)/),
           class: xpath_pred(preds, ~r/@class\s*=\s*'([^']*)'/)
         }}

      _ ->
        :error
    end
  end

  defp parse_xpath(_), do: :error

  @spec xpath_pred(String.t(), Regex.t()) :: String.t() | nil
  defp xpath_pred(preds, regex) do
    case Regex.run(regex, preds) do
      [_, value] -> value
      _ -> nil
    end
  end

  @spec predicates_match?(Floki.html_node(), xpath_spec()) :: boolean()
  defp predicates_match?(node, spec) do
    text = node |> elem(2) |> Floki.text()
    class = attr(elem(node, 1), "class", "")

    (is_nil(spec.contains_text) or String.contains?(text, spec.contains_text)) and
      (is_nil(spec.contains_class) or String.contains?(class, spec.contains_class)) and
      (is_nil(spec.class) or class == spec.class)
  end

  @spec find_tags(Floki.html_tree() | Floki.html_node(), String.t()) :: [Floki.html_node()]
  defp find_tags(nodes, tag) when is_list(nodes) do
    Enum.flat_map(nodes, &find_tags(&1, tag))
  end

  defp find_tags({name, _, _} = node, tag) when name == tag, do: [node]

  defp find_tags({_, _, children}, tag), do: find_tags(children, tag)
  defp find_tags(_, _), do: []

  @spec attr([{String.t(), String.t()}], String.t(), term()) :: term()
  defp attr(attrs, name, default \\ nil) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> default
    end
  end

  @spec human_tag(String.t()) :: String.t()
  defp human_tag("*"), do: "Elements"
  defp human_tag("p"), do: "Paragraphs"
  defp human_tag("div"), do: "Divs"
  defp human_tag("li"), do: "List items"
  defp human_tag(tag), do: String.capitalize(tag) <> "s"

  @spec normalize_space(String.t()) :: String.t()
  defp normalize_space(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @spec xpath_escape(String.t()) :: String.t()
  defp xpath_escape(text) do
    String.replace(text, "'", " ")
  end

  @spec blank_to_nil(term()) :: term()
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
