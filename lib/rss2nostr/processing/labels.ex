defmodule Rss2Nostr.Processing.Labels do
  @moduledoc """
  Short phrases inserted during HTML-to-Markdown conversion
  (`Listen on SoundCloud`, `Watch on YouTube`, `Audio`, …),
  translated to the feed language.
  """

  @default "en"

  @aliases %{
    "nb" => "no",
    "nn" => "no",
    "iw" => "he",
    "jp" => "ja",
    "cz" => "cs",
    "ua" => "uk"
  }

  @listen_on %{
    "ar" => "استمع على %{platform}",
    "bg" => "Слушайте в %{platform}",
    "cs" => "Poslouchejte na %{platform}",
    "da" => "Lyt på %{platform}",
    "de" => "Auf %{platform} anhören",
    "el" => "Ακούστε στο %{platform}",
    "en" => "Listen on %{platform}",
    "es" => "Escuchar en %{platform}",
    "et" => "Kuula saidil %{platform}",
    "fa" => "گوش دادن در %{platform}",
    "fi" => "Kuuntele palvelussa %{platform}",
    "fr" => "Écouter sur %{platform}",
    "he" => "האזן ב-%{platform}",
    "hi" => "%{platform} पर सुनें",
    "hr" => "Slušaj na %{platform}",
    "hu" => "Hallgasd a(z) %{platform} oldalon",
    "id" => "Dengarkan di %{platform}",
    "it" => "Ascolta su %{platform}",
    "ja" => "%{platform}で聴く",
    "ko" => "%{platform}에서 듣기",
    "lt" => "Klausykite per %{platform}",
    "lv" => "Klausies vietnē %{platform}",
    "nl" => "Luister op %{platform}",
    "no" => "Lytt på %{platform}",
    "pl" => "Słuchaj na %{platform}",
    "pt" => "Ouvir no %{platform}",
    "ro" => "Ascultă pe %{platform}",
    "ru" => "Слушать на %{platform}",
    "sk" => "Počúvaj na %{platform}",
    "sl" => "Poslušaj na %{platform}",
    "sr" => "Слушај на %{platform}",
    "sv" => "Lyssna på %{platform}",
    "th" => "ฟังบน %{platform}",
    "tr" => "%{platform} üzerinde dinle",
    "uk" => "Слухати на %{platform}",
    "vi" => "Nghe trên %{platform}",
    "zh" => "在 %{platform} 收听"
  }

  @watch_on %{
    "ar" => "شاهد على %{platform}",
    "bg" => "Гледайте в %{platform}",
    "cs" => "Sledujte na %{platform}",
    "da" => "Se på %{platform}",
    "de" => "Auf %{platform} ansehen",
    "el" => "Δείτε στο %{platform}",
    "en" => "Watch on %{platform}",
    "es" => "Ver en %{platform}",
    "et" => "Vaata saidil %{platform}",
    "fa" => "تماشا در %{platform}",
    "fi" => "Katso palvelussa %{platform}",
    "fr" => "Regarder sur %{platform}",
    "he" => "צפה ב-%{platform}",
    "hi" => "%{platform} पर देखें",
    "hr" => "Gledaj na %{platform}",
    "hu" => "Nézd a(z) %{platform} oldalon",
    "id" => "Tonton di %{platform}",
    "it" => "Guarda su %{platform}",
    "ja" => "%{platform}で見る",
    "ko" => "%{platform}에서 보기",
    "lt" => "Žiūrėkite per %{platform}",
    "lv" => "Skaties vietnē %{platform}",
    "nl" => "Bekijk op %{platform}",
    "no" => "Se på %{platform}",
    "pl" => "Oglądaj na %{platform}",
    "pt" => "Assistir no %{platform}",
    "ro" => "Urmărește pe %{platform}",
    "ru" => "Смотреть на %{platform}",
    "sk" => "Sleduj na %{platform}",
    "sl" => "Glej na %{platform}",
    "sr" => "Гледај на %{platform}",
    "sv" => "Titta på %{platform}",
    "th" => "ดูบน %{platform}",
    "tr" => "%{platform} üzerinde izle",
    "uk" => "Дивитися на %{platform}",
    "vi" => "Xem trên %{platform}",
    "zh" => "在 %{platform} 观看"
  }

  @audio %{
    "ar" => "صوت",
    "el" => "Ήχος",
    "fa" => "صدا",
    "fi" => "Ääni",
    "fr" => "Audio",
    "he" => "אודיו",
    "hi" => "ऑडियो",
    "hu" => "Hang",
    "ja" => "音声",
    "ko" => "오디오",
    "pt" => "Áudio",
    "ru" => "Аудио",
    "th" => "เสียง",
    "tr" => "Ses",
    "uk" => "Аудіо",
    "vi" => "Âm thanh",
    "zh" => "音频"
  }

  @video %{
    "ar" => "فيديو",
    "el" => "Βίντεο",
    "es" => "Vídeo",
    "fa" => "ویدیو",
    "fr" => "Vidéo",
    "he" => "וידאו",
    "hi" => "वीडियो",
    "hu" => "Videó",
    "ja" => "動画",
    "ko" => "동영상",
    "pl" => "Wideo",
    "pt" => "Vídeo",
    "ru" => "Видео",
    "th" => "วิดีโอ",
    "uk" => "Відео",
    "zh" => "视频"
  }

  @type key :: :listen_on | :watch_on | :audio | :video

  @doc """
  Translated phrase for `key` in `language`. Unknown languages fall back
  to English. `:listen_on` and `:watch_on` take `platform: "SoundCloud"`.
  """
  @spec t(key(), String.t() | nil, keyword()) :: String.t()
  def t(key, language, binds \\ [])

  def t(:listen_on, language, binds), do: lookup(@listen_on, language, binds)
  def t(:watch_on, language, binds), do: lookup(@watch_on, language, binds)
  def t(:audio, language, _binds), do: lookup(@audio, language, [], "Audio")
  def t(:video, language, _binds), do: lookup(@video, language, [], "Video")

  @doc """
  ISO 639-1 code (`de-DE` → `de`). Unknown or blank becomes `"en"`.
  """
  @spec normalize(String.t() | nil) :: String.t()
  def normalize(nil), do: @default
  def normalize(""), do: @default

  def normalize(language) when is_binary(language) do
    primary =
      language
      |> String.trim()
      |> String.downcase()
      |> String.replace("_", "-")
      |> String.split("-", parts: 2)
      |> hd()

    Map.get(@aliases, primary, primary)
  end

  def normalize(_), do: @default

  @doc """
  True when `text` is a generated “Watch on YouTube” label in any
  supported language (so oEmbed can replace it with the video title).
  """
  @spec generic_watch_on_youtube?(String.t() | nil) :: boolean()
  def generic_watch_on_youtube?(text) when is_binary(text) do
    needle = squash(text)

    Enum.any?(Map.keys(@watch_on), fn lang ->
      squash(t(:watch_on, lang, platform: "YouTube")) == needle
    end)
  end

  def generic_watch_on_youtube?(_), do: false

  defp lookup(map, language, binds, fallback \\ nil) do
    lang = normalize(language)
    template = Map.get(map, lang) || fallback || Map.fetch!(map, @default)
    interpolate(template, binds)
  end

  defp interpolate(template, binds) do
    Enum.reduce(binds, template, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp squash(text) do
    text
    |> String.downcase()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
