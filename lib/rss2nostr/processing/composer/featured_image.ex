defmodule Rss2Nostr.Processing.Composer.FeaturedImage do
  @moduledoc false

  alias Rss2Nostr.Processing.ImageExtractor

  @linked_image ~r/\[!\[[^\]]*\]\(([^"\)]+)(?:\s+"[^"]*")?\s*\)\]\([^\)]+\)/
  @bare_image ~r/!\[[^\]]*\]\(\s*([^"\)]+)(?:\s+"[^"]*")?\s*\)/

  @spec promote_leading_image(String.t() | nil, String.t() | nil) ::
          {String.t() | nil, String.t() | nil}
  def promote_leading_image(markdown, image) when is_binary(image) and image != "" do
    case extract_opening_image(markdown) do
      {leading, rest} when is_binary(leading) ->
        if same_image?(leading, image), do: {image, rest}, else: {image, markdown}

      _ ->
        {image, markdown}
    end
  end

  def promote_leading_image(markdown, _image) when is_binary(markdown) do
    extract_opening_image(markdown)
  end

  def promote_leading_image(markdown, _image), do: {nil, markdown}

  @spec drop_opening_featured_html(String.t(), String.t() | nil) :: String.t()
  def drop_opening_featured_html(html, image)
      when is_binary(html) and is_binary(image) and image != "" do
    case Floki.parse_fragment(html) do
      {:ok, nodes} -> nodes |> drop_opening_featured_nodes(image) |> Floki.raw_html()
      _ -> html
    end
  rescue
    _ -> html
  end

  def drop_opening_featured_html(html, _), do: html

  @spec same_image?(String.t(), String.t()) :: boolean()
  def same_image?(left, right) do
    keys_left = image_keys(left)
    keys_right = image_keys(right)

    keys_left != MapSet.new() and not MapSet.disjoint?(keys_left, keys_right)
  end

  @spec img_attr_urls(list()) :: [String.t()]
  def img_attr_urls(attrs) do
    [
      html_attr_value(attrs, "src"),
      html_attr_value(attrs, "data-src"),
      srcset_head(html_attr_value(attrs, "srcset") || html_attr_value(attrs, "data-srcset")),
      data_attrs_src(html_attr_value(attrs, "data-attrs"))
    ]
    |> List.flatten()
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
  end

  @spec image_keys(String.t()) :: MapSet.t(String.t())
  defp image_keys(url) do
    origin = ImageExtractor.normalize_url(url)

    [
      origin,
      image_basename(origin),
      image_basename(url),
      substack_media_id(origin),
      substack_media_id(url)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> MapSet.new()
  end

  @spec substack_media_id(String.t()) :: String.t() | nil
  defp substack_media_id(url) when is_binary(url) do
    decoded =
      url
      |> ImageExtractor.normalize_url()
      |> URI.decode()

    case Regex.run(~r/([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})/i, decoded) do
      [_, id] -> String.downcase(id)
      _ -> nil
    end
  end

  @spec drop_opening_featured_nodes([Floki.html_node()], String.t()) :: [Floki.html_node()]
  defp drop_opening_featured_nodes([node], featured) do
    case node do
      {tag, attrs, children} ->
        [{tag, attrs, drop_opening_children(children, featured)}]

      _ ->
        [node]
    end
  end

  defp drop_opening_featured_nodes(nodes, featured) when is_list(nodes) do
    drop_opening_children(nodes, featured)
  end

  @spec drop_opening_children([Floki.html_tree() | Floki.html_node()], String.t()) :: [Floki.html_tree() | Floki.html_node()]
  defp drop_opening_children(nodes, featured) do
    {kept, _} =
      Enum.reduce(nodes, {[], :opening}, fn
        node, {acc, :done} ->
          {acc ++ [node], :done}

        node, {acc, :opening} ->
          cond do
            blank_html_node?(node) ->
              {acc, :opening}

            short_credit_html?(node) ->
              {acc ++ [node], :opening}

            featured_image_block?(node, featured) ->
              {acc, :done}

            true ->
              {acc ++ [node], :done}
          end
      end)

    kept
  end

  @spec blank_html_node?(term()) :: boolean()
  defp blank_html_node?(text) when is_binary(text), do: String.trim(text) == ""
  defp blank_html_node?(_), do: false

  @spec short_credit_html?(Floki.html_node()) :: boolean()
  defp short_credit_html?({"p", _, _} = node) do
    text = node |> Floki.text() |> String.trim()

    image_urls_in(node) == [] and text != "" and
      length(String.split(text, ~r/\s+/, trim: true)) <= 10
  end

  defp short_credit_html?(_), do: false

  @spec featured_image_block?(Floki.html_node(), String.t()) :: boolean()
  defp featured_image_block?(node, featured) do
    urls = image_urls_in(node)

    urls != [] and image_only_block?(node) and
      Enum.any?(urls, &same_image?(&1, featured))
  end

  @spec image_only_block?(Floki.html_node()) :: boolean()
  defp image_only_block?({"img", _, _}), do: true
  defp image_only_block?({"figure", _, _}), do: true
  defp image_only_block?({"picture", _, _}), do: true
  defp image_only_block?({"a", _, children}), do: image_only_block_children?(children)

  defp image_only_block?({"p", _, children}) do
    image_only_block_children?(children) and
      String.trim(Floki.text({"p", [], children})) == ""
  end

  defp image_only_block?({"div", _, children}), do: image_only_block_children?(children)
  defp image_only_block?(_), do: false

  @spec image_only_block_children?([Floki.html_node()]) :: boolean()
  defp image_only_block_children?(children) do
    children
    |> Enum.reject(&blank_html_node?/1)
    |> Enum.all?(fn
      {"img", _, _} ->
        true

      {"figure", _, _} ->
        true

      {"picture", _, _} ->
        true

      {"a", _, inner} ->
        image_only_block_children?(inner)

      {"div", _, inner} ->
        image_only_block_children?(inner)

      {"p", _, inner} ->
        image_only_block_children?(inner) and String.trim(Floki.text({"p", [], inner})) == ""

      _ ->
        false
    end)
  end

  @spec image_urls_in(Floki.html_tree() | Floki.html_node()) :: [String.t()]
  defp image_urls_in(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &image_urls_in/1)

  defp image_urls_in({"img", attrs, children}) do
    img_attr_urls(attrs) ++ image_urls_in(children)
  end

  defp image_urls_in({"source", attrs, children}) do
    img_attr_urls(attrs) ++ image_urls_in(children)
  end

  defp image_urls_in({_, _, children}), do: image_urls_in(children)
  defp image_urls_in(_), do: []

  @spec srcset_head(String.t() | nil) :: [String.t()]
  defp srcset_head(srcset) when is_binary(srcset) and srcset != "" do
    case Regex.run(~r/(\S+)\s+\d+w/i, srcset) do
      [_, url] -> [url]
      _ -> []
    end
  end

  defp srcset_head(_), do: []

  @spec data_attrs_src(String.t() | nil) :: [String.t()]
  defp data_attrs_src(json) when is_binary(json) and json != "" do
    case Jason.decode(json) do
      {:ok, %{"src" => src}} when is_binary(src) and src != "" -> [src]
      _ -> []
    end
  end

  defp data_attrs_src(_), do: []

  @spec html_attr_value([{String.t(), String.t()}], String.t()) :: String.t() | nil
  defp html_attr_value(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  @spec image_basename(String.t()) :: String.t()
  defp image_basename(url) do
    name =
      url
      |> URI.parse()
      |> Map.get(:path, "")
      |> Path.basename()
      |> String.downcase()
      |> String.replace(~r/-\d+x\d+(?=\.[a-z0-9]+$)/, "")
      |> String.replace(~r/-scaled(?=\.[a-z0-9]+$)/, "")

    if String.contains?(name, "."), do: name, else: ""
  end

  @spec extract_opening_image(String.t() | nil) :: {String.t() | nil, String.t() | nil}
  defp extract_opening_image(markdown) when not is_binary(markdown), do: {nil, markdown}

  defp extract_opening_image(markdown) do
    case first_image_match(markdown) do
      {url, start, len} ->
        prefix = binary_part(markdown, 0, start)

        if opening_prefix?(prefix) do
          {url, remove_image_at(markdown, start, len)}
        else
          {nil, markdown}
        end

      nil ->
        {nil, markdown}
    end
  end

  @spec first_image_match(String.t()) :: {String.t(), non_neg_integer(), non_neg_integer()} | nil
  defp first_image_match(markdown) do
    linked = image_match(markdown, @linked_image)
    bare = image_match(markdown, @bare_image)

    cond do
      linked && bare && elem(linked, 1) <= elem(bare, 1) -> linked
      linked -> linked
      bare -> bare
      true -> nil
    end
  end

  @spec image_match(String.t(), Regex.t()) :: {String.t(), non_neg_integer(), non_neg_integer()} | nil
  defp image_match(markdown, regex) do
    case Regex.run(regex, markdown, return: :index) do
      [{start, len} | captures] ->
        url =
          captures
          |> Enum.find_value(fn
            {pos, n} when n > 0 -> binary_part(markdown, pos, n)
            _ -> nil
          end)

        if is_binary(url), do: {url, start, len}

      _ ->
        nil
    end
  end

  @spec opening_prefix?(String.t()) :: boolean()
  defp opening_prefix?(prefix) do
    prefix
    |> String.split(~r/\n{2,}/)
    |> Enum.all?(&thin_opening_block?/1)
  end

  @spec thin_opening_block?(String.t()) :: boolean()
  defp thin_opening_block?(block) do
    trimmed = String.trim(block)

    trimmed == "" or String.match?(trimmed, ~r/\A---+\z/) or lone_markdown_link?(trimmed) or
      short_credit?(trimmed)
  end

  @spec short_credit?(String.t()) :: boolean()
  defp short_credit?(text) do
    not String.contains?(text, "![") and
      not String.contains?(text, "\n") and
      length(String.split(text, ~r/\s+/, trim: true)) <= 10
  end

  @spec lone_markdown_link?(String.t()) :: boolean()
  defp lone_markdown_link?(text) do
    String.match?(text, ~r/\A\[[^\]]+\]\([^)]+\)\s*\z/)
  end

  @spec remove_image_at(String.t(), non_neg_integer(), non_neg_integer()) :: String.t()
  defp remove_image_at(markdown, start, len) do
    {pre, rest} = String.split_at(markdown, start)
    {_gone, post} = String.split_at(rest, len)

    (pre <> post)
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> then(fn joined ->
      if String.trim(pre) == "", do: String.trim_leading(joined), else: joined
    end)
  end
end
