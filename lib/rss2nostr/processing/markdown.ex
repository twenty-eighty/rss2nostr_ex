defmodule Rss2Nostr.Processing.Markdown do
  @moduledoc """
  Renders a conservative HTML preview of article Markdown.

  Text and attribute values are escaped. Only http(s) links and images
  are emitted, so the compose preview can use the HTML safely.
  """

  @spec to_html(String.t() | nil) :: String.t()
  def to_html(nil), do: ""
  def to_html(""), do: ""

  def to_html(markdown) when is_binary(markdown) do
    markdown
    |> String.replace("\r\n", "\n")
    |> String.trim()
    |> split_blocks()
    |> Enum.map_join("\n", &block_to_html/1)
  end

  defp split_blocks(markdown) do
    markdown
    |> extract_segments()
    |> Enum.flat_map(fn
      {:fence, text} -> [String.split(text, "\n")]
      {:text, text} -> split_text_blocks(text)
    end)
    |> Enum.reject(&empty_block?/1)
  end

  defp extract_segments(markdown) do
    pattern = ~r/^```[^\n]*\n[\s\S]*?^```[ \t]*$/m

    Regex.split(pattern, markdown, include_captures: true, trim: true)
    |> Enum.map(fn chunk ->
      if String.starts_with?(String.trim_leading(chunk), "```") do
        {:fence, String.trim(chunk)}
      else
        {:text, chunk}
      end
    end)
  end

  defp split_text_blocks(text) do
    text
    |> String.split(~r/\n{2,}/)
    |> Enum.map(&String.split(&1, "\n"))
  end

  defp empty_block?(lines) do
    Enum.all?(lines, &(String.trim(&1) == ""))
  end

  defp block_to_html(lines) do
    first = List.first(lines) |> to_string() |> String.trim_leading()

    cond do
      String.starts_with?(first, "```") ->
        code_block_html(lines)

      heading?(first) ->
        heading_html(first)

      hr?(first) ->
        "<hr>"

      String.starts_with?(first, ">") ->
        quote_html(lines)

      list_item?(first) ->
        list_html(lines)

      String.starts_with?(first, "|") ->
        table_html(lines)

      footnote_def?(first) ->
        footnote_def_html(lines)

      true ->
        text = lines |> Enum.join("\n") |> String.trim()
        html = inline(text)

        cond do
          html == "" -> ""
          figure_only?(html) -> html
          true -> "<p>#{html}</p>"
        end
    end
  end

  defp figure_only?(html) do
    String.starts_with?(html, "<figure") and String.ends_with?(html, "</figure>")
  end

  defp footnote_def?(line), do: String.match?(String.trim_leading(line), ~r/^\[\^\d+\]:/)

  defp footnote_def_html(lines) do
    text = lines |> Enum.join("\n") |> String.trim()

    case Regex.run(~r/^\[\^(\d+)\]:\s*(.*)/s, text) do
      [_, n, body] ->
        inner = if body == "", do: "", else: " #{inline(body)}"
        ~s(<p class="footnote" id="fn-#{n}"><a href="#fnref-#{n}">#{n}</a>.#{inner}</p>)

      _ ->
        "<p>#{inline(text)}</p>"
    end
  end

  defp heading?(line), do: String.match?(line, ~r/^\#{1,6}\s+\S/)
  defp hr?(line), do: String.match?(String.trim(line), ~r/^(-{3,}|\*{3,}|_{3,})$/)
  defp list_item?(line), do: String.match?(line, ~r/^(?:[-*+]|\d+\.)\s+/)

  defp heading_html(line) do
    case Regex.run(~r/^(\#{1,6})\s+(.*)$/, line) do
      [_, hashes, text] ->
        level = String.length(hashes)
        "<h#{level}>#{inline(String.trim(text))}</h#{level}>"

      _ ->
        "<p>#{inline(line)}</p>"
    end
  end

  defp quote_html(lines) do
    text =
      lines
      |> Enum.map(&String.replace(&1, ~r/^\s*>\s?/, ""))
      |> Enum.join("\n")
      |> String.trim()

    "<blockquote><p>#{inline(text)}</p></blockquote>"
  end

  defp list_html(lines) do
    ordered? = String.match?(hd(lines) |> String.trim_leading(), ~r/^\d+\.\s+/)
    tag = if ordered?, do: "ol", else: "ul"

    items =
      Enum.map_join(lines, "", fn line ->
        text = String.replace(String.trim_leading(line), ~r/^(?:[-*+]|\d+\.)\s+/, "")
        "<li>#{inline(text)}</li>"
      end)

    "<#{tag}>#{items}</#{tag}>"
  end

  defp table_html(lines) do
    rows =
      lines
      |> Enum.reject(&table_separator?/1)
      |> Enum.map_join("", fn line ->
        cells =
          line
          |> String.trim()
          |> String.trim("|")
          |> String.split("|")
          |> Enum.map_join("", fn cell -> "<td>#{inline(String.trim(cell))}</td>" end)

        "<tr>#{cells}</tr>"
      end)

    "<table>#{rows}</table>"
  end

  defp table_separator?(line) do
    String.match?(String.trim(line), ~r/^\|?[\s:|-]+\|[\s:|-]+\|?$/)
  end

  defp code_block_html(lines) do
    body =
      lines
      |> Enum.drop(1)
      |> Enum.drop(-1)
      |> Enum.join("\n")

    "<pre><code>#{escape(body)}</code></pre>"
  end

  defp inline(text) do
    text
    |> escape()
    |> replace_hard_breaks()
    |> replace_images()
    |> replace_links()
    |> replace_footnotes()
    |> replace_code()
    |> replace_emphasis()
  end

  defp replace_hard_breaks(text) do
    text
    |> String.replace("\\\n", "<br>\n")
    |> String.replace(~r/ {2,}\n/, "<br>\n")
  end

  defp replace_footnotes(text) do
    Regex.replace(~r/\[\^(\d+)\](?!:)/, text, fn _, n ->
      ~s(<sup class="footnote-ref" id="fnref-#{n}"><a href="#fn-#{n}">#{n}</a></sup>)
    end)
  end

  defp replace_images(text) do
    Regex.replace(~r/!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;([^&]*)&quot;)?\)/, text, fn
      _, alt, url, title ->
        case safe_url(unescape(url)) do
          nil ->
            alt

          safe ->
            img = ~s(<img src="#{escape_attr(safe)}" alt="#{alt}">)

            if title != "" do
              ~s(<figure>#{img}<figcaption>#{title}</figcaption></figure>)
            else
              img
            end
        end
    end)
  end

  defp replace_links(text) do
    Regex.replace(~r/\[([^\]]+)\]\(([^)\s]+)\)/, text, fn _, label, url ->
      case safe_url(unescape(url)) do
        nil -> label
        safe -> ~s(<a href="#{escape_attr(safe)}">#{label}</a>)
      end
    end)
  end

  defp replace_code(text) do
    Regex.replace(~r/`([^`]+)`/, text, fn _, code -> "<code>#{code}</code>" end)
  end

  # CommonMark flanking: a `*`/`_` run cannot open if followed by whitespace,
  # and cannot close if preceded by whitespace. Longer runs first so
  # `***bold italic***` does not leave a stray marker.
  defp replace_emphasis(text) do
    text
    |> replace_delimited(~r/\*\*\*(?!\s)(.+?)(?<!\s)\*\*\*/, fn inner ->
      "<strong><em>#{inner}</em></strong>"
    end)
    |> replace_delimited(~r/\*\*(?!\s)(.+?)(?<!\s)\*\*/, fn inner ->
      "<strong>#{inner}</strong>"
    end)
    |> replace_delimited(~r/__(?!\s)(.+?)(?<!\s)__/, fn inner ->
      "<strong>#{inner}</strong>"
    end)
    |> replace_delimited(~r/(?<!\*)\*(?!\s)(.+?)(?<!\s)\*(?!\*)/, fn inner ->
      "<em>#{inner}</em>"
    end)
    |> replace_delimited(~r/(?<![A-Za-z0-9_])_(?!\s)(.+?)(?<!\s)_(?![A-Za-z0-9_])/, fn inner ->
      "<em>#{inner}</em>"
    end)
  end

  defp replace_delimited(text, regex, fun) do
    Regex.replace(regex, text, fn _, inner -> fun.(inner) end)
  end

  defp safe_url(url) do
    uri = URI.parse(String.trim(url))

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      url
    end
  rescue
    _ -> nil
  end

  defp unescape(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end

  defp escape(text) when is_binary(text), do: Plug.HTML.html_escape(text)
  defp escape(_), do: ""

  defp escape_attr(text) do
    text
    |> escape()
    |> String.replace("\"", "&quot;")
  end
end
