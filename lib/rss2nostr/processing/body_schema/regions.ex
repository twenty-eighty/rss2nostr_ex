defmodule Rss2Nostr.Processing.BodySchema.Regions do
  @moduledoc false

  alias Rss2Nostr.Processing.BodySchema.{Extract, Presets}

  @skip_classes MapSet.new(~w(
    row col column columns container grid flex
    inner outer wrap wrapper
    clearfix hidden visible active open
  ))

  @skip_discover_class ~r/(^|[-_])(tab|tabs|sidebar|related|comment|comments|comm|widget|menu|nav|footer|header|share|social|popular|breadcrumb|pagination)s?([-_]|$)/i

  @discover_class ~r/content|article|entry|post|body|markup|wpb_|elementor|et_pb|fl-|wp-block/i

  @type region :: %{
          selector: String.t(),
          label: String.t(),
          first_line: String.t(),
          word_count: non_neg_integer(),
          recommended: boolean(),
          selected: boolean()
        }

  @spec candidates(String.t() | nil, keyword()) :: [region()]
  def candidates(html, opts \\ [])
  def candidates(html, _opts) when html in [nil, ""], do: []

  def candidates(html, opts) do
    url = Keyword.get(opts, :url)
    selected = Keyword.get(opts, :selected)
    schema = Presets.schema_for_url(url)
    page = region(html, "", "Whole page", schema)

    preset_regions =
      Presets.preset_labels()
      |> Enum.filter(fn {selector, _} -> Extract.matches?(html, selector) end)
      |> Enum.map(fn {selector, label} ->
        region(html, selector, label, schema)
      end)

    discovered_regions =
      html
      |> discovered_selectors()
      |> Enum.map(fn selector -> region(html, selector, Presets.label_for(selector), schema) end)
      |> Enum.filter(&(&1.word_count > 0 and &1.word_count < page.word_count))

    regions =
      ([page | preset_regions] ++ discovered_regions)
      |> Enum.reject(&(&1.selector != "" and &1.word_count == 0))
      |> prefer_distinct_regions()
      |> mark_recommended(schema)

    chosen = selected || recommended_selector(regions) || ""

    regions
    |> keep_visible(chosen)
    |> Enum.sort_by(&{!&1.recommended, -&1.word_count})
    |> mark_selected(chosen)
  end

  @spec preferred_selector(String.t() | nil, String.t() | nil) :: String.t() | nil
  def preferred_selector(html, url) do
    case candidates(html, url: url) do
      [] -> nil
      regions -> recommended_selector(regions)
    end
  end

  defp discovered_selectors(html) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        doc
        |> Floki.find("article, main, section, div")
        |> Enum.flat_map(&node_selectors/1)
        |> Enum.uniq()
        |> Enum.reject(&Map.has_key?(Presets.preset_labels(), &1))

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp node_selectors({tag, attrs, _}) when is_binary(tag) do
    classes =
      attrs
      |> attr("class")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.filter(&usable_class?/1)
      |> Enum.map(&"#{tag}.#{&1}")

    itemprop =
      case attr(attrs, "itemprop") do
        "articleBody" -> ["[itemprop='articleBody']"]
        _ -> []
      end

    id =
      case attr(attrs, "id") do
        id when id in ["content", "main", "main-content", "article", "post", "primary"] ->
          ["##{id}"]

        _ ->
          []
      end

    itemprop ++ id ++ classes
  end

  defp node_selectors(_), do: []

  defp usable_class?(class) do
    String.match?(class, ~r/^[A-Za-z][A-Za-z0-9_-]{3,}$/) and
      not MapSet.member?(@skip_classes, String.downcase(class)) and
      not String.match?(class, ~r/^(col|span)[-_]/i) and
      not String.match?(class, @skip_discover_class) and
      String.match?(class, @discover_class)
  end

  defp attr(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {_, value} when is_binary(value) -> value
      _ -> ""
    end
  end

  defp prefer_distinct_regions(regions) do
    preset_keys = MapSet.new(["" | Map.keys(Presets.preset_labels())])

    {presets, discovered} =
      Enum.split_with(regions, &MapSet.member?(preset_keys, &1.selector))

    discovered =
      discovered
      |> Enum.sort_by(&semantic_rank/1)
      |> Enum.reject(fn region ->
        Enum.any?(presets, &same_region?(&1, region))
      end)
      |> Enum.uniq_by(&{&1.word_count, &1.first_line})

    Enum.uniq_by(presets, & &1.selector) ++ discovered
  end

  defp same_region?(a, b), do: a.word_count == b.word_count and a.first_line == b.first_line

  defp semantic_rank(%{selector: selector}) do
    page_builder_selectors = Presets.page_builder_selectors()

    cond do
      selector == "" ->
        {0, 0, selector}

      selector in page_builder_selectors ->
        {1, Enum.find_index(page_builder_selectors, &(&1 == selector)) || 99, selector}

      selector == "[itemprop='articleBody']" ->
        {2, 0, selector}

      selector in ["article", "main"] ->
        {3, 0, selector}

      String.match?(selector, ~r/content|article|entry|post|body|markup/i) ->
        {4, String.length(selector), selector}

      true ->
        {5, String.length(selector), selector}
    end
  end

  defp keep_visible(regions, selected) do
    preset_keys = MapSet.new(Map.keys(Presets.preset_labels()))

    {pinned, rest} =
      Enum.split_with(regions, fn region ->
        region.selector == "" or region.recommended or region.selector == selected or
          MapSet.member?(preset_keys, region.selector)
      end)

    extras =
      rest
      |> Enum.filter(&(&1.word_count >= 80))
      |> Enum.sort_by(& &1.word_count, :desc)
      |> Enum.take(4)

    pinned ++ extras
  end

  defp region(html, selector, label, schema) do
    excerpt = excerpt(html, selector)
    recommended? = schema != nil and schema.selector == selector

    %{
      selector: selector,
      label: if(recommended?, do: schema.label, else: label),
      first_line: excerpt.first_line,
      word_count: excerpt.word_count,
      recommended: recommended?,
      selected: false
    }
  end

  defp excerpt(html, ""), do: excerpt_from_html(html)

  defp excerpt(html, selector) do
    case Extract.extract(html, selector) do
      nil -> %{first_line: "", word_count: 0}
      selected -> excerpt_from_html(selected)
    end
  end

  defp excerpt_from_html(html) do
    {:ok, doc} = Floki.parse_document(html)

    text =
      doc
      |> Extract.strip_non_content()
      |> Floki.text()
      |> Extract.normalize_space()

    words = String.split(text, ~r/\s+/, trim: true)

    %{
      first_line: text |> String.slice(0, 140) |> String.trim(),
      word_count: length(words)
    }
  rescue
    _ -> %{first_line: "", word_count: 0}
  end

  defp mark_selected(regions, selected) do
    selected = selected || ""

    Enum.map(regions, fn region ->
      %{region | selected: region.selector == selected}
    end)
  end

  defp mark_recommended(regions, schema) do
    chosen =
      cond do
        is_map(schema) and
            Enum.any?(regions, &(&1.selector == schema.selector and &1.word_count > 0)) ->
          schema.selector

        plugin = page_builder_selector(regions) ->
          plugin

        article = article_selector(regions) ->
          article

        true ->
          tightest_content_selector(regions)
      end

    Enum.map(regions, fn region ->
      %{region | recommended: chosen != "" and region.selector == chosen}
    end)
  end

  defp recommended_selector(regions) do
    case Enum.find(regions, & &1.recommended) do
      %{selector: selector} when selector != "" -> selector
      _ -> nil
    end
  end

  defp article_selector(regions) do
    Enum.find_value(Presets.article_selectors(), fn selector ->
      case Enum.find(regions, &(&1.selector == selector and &1.word_count >= 80)) do
        %{selector: match} -> match
        _ -> nil
      end
    end)
  end

  defp page_builder_selector(regions) do
    page_builder_selectors = Presets.page_builder_selectors()

    matching =
      Enum.filter(regions, fn region ->
        region.selector in page_builder_selectors and region.word_count >= 80
      end)

    case matching do
      [] ->
        nil

      list ->
        max_words = Enum.max_by(list, & &1.word_count).word_count
        threshold = div(max_words * 85, 100)

        list
        |> Enum.filter(&(&1.word_count >= threshold))
        |> Enum.min_by(& &1.word_count)
        |> Map.get(:selector)
    end
  end

  defp tightest_content_selector(regions) do
    content = Enum.filter(regions, &(&1.selector != "" and &1.word_count > 0))

    case content do
      [] ->
        ""

      list ->
        max_words = Enum.max_by(list, & &1.word_count).word_count
        threshold = max(80, div(max_words * 2, 5))

        case Enum.filter(list, &(&1.word_count >= threshold)) do
          [] ->
            ""

          kept ->
            kept |> Enum.min_by(& &1.word_count) |> Map.get(:selector)
        end
    end
  end
end
