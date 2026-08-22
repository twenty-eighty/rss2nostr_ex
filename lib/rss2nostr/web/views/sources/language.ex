defmodule Rss2Nostr.Web.Views.Sources.Language do
  @moduledoc false

  alias Rss2Nostr.Web.Views.Sources.Helpers

  def language_select(selected) do
    selected = selected || "de"

    options =
      language_choices()
      |> maybe_include_current_language(selected)
      |> Enum.map_join("", fn {code, label} ->
        sel = if code == selected, do: " selected", else: ""
        ~s(<option value="#{Helpers.escape_attr(code)}"#{sel}>#{Helpers.escape_html(label)}</option>)
      end)

    """
    <select id="language" name="language">
      #{options}
    </select>
    """
  end

  defp maybe_include_current_language(choices, selected) do
    if Enum.any?(choices, fn {code, _} -> code == selected end) do
      choices
    else
      [{selected, selected} | choices]
    end
  end

  defp language_choices do
    [
      {"ar", "Arabic (ar)"},
      {"bg", "Bulgarian (bg)"},
      {"zh", "Chinese (zh)"},
      {"hr", "Croatian (hr)"},
      {"cs", "Czech (cs)"},
      {"da", "Danish (da)"},
      {"nl", "Dutch (nl)"},
      {"en", "English (en)"},
      {"et", "Estonian (et)"},
      {"fi", "Finnish (fi)"},
      {"fr", "French (fr)"},
      {"de", "German (de)"},
      {"el", "Greek (el)"},
      {"he", "Hebrew (he)"},
      {"hi", "Hindi (hi)"},
      {"hu", "Hungarian (hu)"},
      {"id", "Indonesian (id)"},
      {"it", "Italian (it)"},
      {"ja", "Japanese (ja)"},
      {"ko", "Korean (ko)"},
      {"lv", "Latvian (lv)"},
      {"lt", "Lithuanian (lt)"},
      {"no", "Norwegian (no)"},
      {"fa", "Persian (fa)"},
      {"pl", "Polish (pl)"},
      {"pt", "Portuguese (pt)"},
      {"ro", "Romanian (ro)"},
      {"ru", "Russian (ru)"},
      {"sr", "Serbian (sr)"},
      {"sk", "Slovak (sk)"},
      {"sl", "Slovenian (sl)"},
      {"es", "Spanish (es)"},
      {"sv", "Swedish (sv)"},
      {"th", "Thai (th)"},
      {"tr", "Turkish (tr)"},
      {"uk", "Ukrainian (uk)"},
      {"vi", "Vietnamese (vi)"}
    ]
  end
end
