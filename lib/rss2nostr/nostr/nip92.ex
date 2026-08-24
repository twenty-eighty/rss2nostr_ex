defmodule Rss2Nostr.Nostr.NIP92 do
  @moduledoc """
  NIP-92 `imeta` tags for media URLs in long-form events.

  Pairs are `"key value"` strings. A tag is `["imeta" | pairs]` and must
  include `url` plus at least one other field.
  """

  @zero_noise ~w(duration bitrate)

  @type pair :: String.t()
  @type tag :: [String.t()]

  @doc """
  Attributes to persist on an article image after a Blossom upload.
  """
  @spec stored_attrs(map(), keyword()) :: map()
  def stored_attrs(result, opts \\ []) when is_map(result) do
    pairs = pairs_from_descriptor(result, opts)

    %{
      sha256: result[:sha256] || result["sha256"],
      mime_type: result[:type] || result["type"],
      file_size: result[:size] || result["size"],
      dim: pair_value(pairs, "dim"),
      thumb: pair_value(pairs, "thumb"),
      imeta: pairs
    }
  end

  @doc """
  `imeta` pairs from a BUD-02 descriptor, including optional BUD-08 `nip94`.
  """
  @spec pairs_from_descriptor(map(), keyword()) :: [pair()]
  def pairs_from_descriptor(result, opts \\ []) when is_map(result) do
    nip94 = normalize_nip94(result[:nip94] || result["nip94"])

    pairs =
      if nip94 != [] do
        Enum.flat_map(nip94, &tag_to_pair/1)
      else
        [
          pair("url", result[:url] || result["url"]),
          pair("x", result[:sha256] || result["sha256"]),
          pair("m", result[:type] || result["type"]),
          pair("size", result[:size] || result["size"])
        ]
      end

    pairs
    |> maybe_put_pair("alt", Keyword.get(opts, :alt))
    |> maybe_put_pair("duration", Keyword.get(opts, :duration) || result[:duration])
    |> maybe_put_pair("dim", Keyword.get(opts, :dim) || result[:dim])
    |> maybe_put_pair("bitrate", Keyword.get(opts, :bitrate) || result[:bitrate])
    |> sanitize_pairs()
  end

  @doc """
  Minimal pairs when a blob is already on the Blossom host.
  """
  @spec pairs_from_url(String.t(), keyword()) :: [pair()]
  def pairs_from_url(url, opts \\ []) when is_binary(url) do
    [
      pair("url", url),
      pair("m", Keyword.get(opts, :mime) || guess_mime(url)),
      pair("x", Keyword.get(opts, :sha256)),
      pair("size", Keyword.get(opts, :size)),
      pair("dim", Keyword.get(opts, :dim)),
      pair("thumb", Keyword.get(opts, :thumb)),
      pair("alt", Keyword.get(opts, :alt)),
      pair("duration", Keyword.get(opts, :duration)),
      pair("bitrate", Keyword.get(opts, :bitrate))
    ]
    |> sanitize_pairs()
  end

  @doc """
  Stored pairs for an article image, synthesizing them when needed.
  """
  @spec pairs_from_image(map()) :: [pair()]
  def pairs_from_image(image) when is_map(image) do
    stored = List.wrap(Map.get(image, :imeta) || Map.get(image, "imeta"))
    url = Map.get(image, :uploaded_url) || Map.get(image, :original_url)

    cond do
      valid_pairs?(stored) ->
        stored
        |> maybe_put_pair("alt", image_alt(image))
        |> sanitize_pairs()

      present?(url) ->
        pairs_from_url(url,
          mime: Map.get(image, :mime_type),
          sha256: Map.get(image, :sha256),
          size: Map.get(image, :file_size),
          dim: Map.get(image, :dim),
          thumb: Map.get(image, :thumb),
          alt: image_alt(image)
        )

      true ->
        []
    end
  end

  @doc """
  NIP-92 tags for media whose URL appears in `content` or as the featured image.
  """
  @spec tags_for_event([map()], String.t() | nil, keyword()) :: [tag()]
  def tags_for_event(images, content, opts \\ []) when is_list(images) do
    featured = Keyword.get(opts, :featured)
    haystack = [content, featured] |> Enum.filter(&is_binary/1) |> Enum.join("\n")

    images
    |> Enum.map(&pairs_from_image/1)
    |> Enum.filter(&valid_pairs?/1)
    |> Enum.uniq_by(&url_from_pairs/1)
    |> Enum.filter(fn pairs ->
      case url_from_pairs(pairs) do
        url when is_binary(url) -> String.contains?(haystack, url)
        _ -> false
      end
    end)
    |> Enum.flat_map(fn pairs ->
      case tag(pairs) do
        nil -> []
        imeta -> [imeta]
      end
    end)
  end

  @doc """
  `["imeta", "url …", …]` or nil when the pairs are not enough.
  """
  @spec tag([pair()]) :: tag() | nil
  def tag(pairs) when is_list(pairs) do
    pairs = sanitize_pairs(pairs)

    if valid_pairs?(pairs) do
      ["imeta" | pairs]
    end
  end

  def tag(_), do: nil

  @spec url_from_pairs([pair()]) :: String.t() | nil
  def url_from_pairs(pairs) when is_list(pairs), do: pair_value(pairs, "url")
  def url_from_pairs(_), do: nil

  defp normalize_nip94(tags) when is_list(tags), do: tags
  defp normalize_nip94(%{"tags" => tags}) when is_list(tags), do: tags
  defp normalize_nip94(_), do: []

  defp tag_to_pair([key, value | _]) when is_binary(key) and not is_nil(value) do
    List.wrap(pair(key, value))
  end

  defp tag_to_pair(_), do: []

  defp pair(_key, value) when value in [nil, ""], do: nil
  defp pair(key, value) when is_integer(value), do: "#{key} #{value}"
  defp pair(key, value) when is_binary(value), do: "#{key} #{String.trim(value)}"
  defp pair(_, _), do: nil

  defp maybe_put_pair(pairs, _key, value) when value in [nil, ""], do: pairs

  defp maybe_put_pair(pairs, key, value) do
    if pair_value(pairs, key) do
      pairs
    else
      pairs ++ List.wrap(pair(key, value))
    end
  end

  defp sanitize_pairs(pairs) do
    pairs
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reject(&noise_pair?/1)
    |> Enum.uniq_by(&pair_key/1)
    |> put_url_first()
  end

  defp noise_pair?(pair) do
    case String.split(pair, " ", parts: 2) do
      ["dim", dim] -> zero_dim?(dim)
      [key, value] -> key in @zero_noise and value in ["0", "0.0"]
      _ -> true
    end
  end

  defp zero_dim?(value) do
    String.match?(value, ~r/\A0+x0+\z/i)
  end

  defp pair_key(pair) do
    pair |> String.split(" ", parts: 2) |> hd()
  end

  defp pair_value(pairs, key) do
    prefix = key <> " "

    Enum.find_value(pairs, fn
      <<^prefix::binary, value::binary>> -> value
      _ -> nil
    end)
  end

  defp put_url_first(pairs) do
    {urls, rest} = Enum.split_with(pairs, &String.starts_with?(&1, "url "))
    urls ++ rest
  end

  defp valid_pairs?(pairs) when is_list(pairs) do
    match?("url " <> _, List.first(pairs)) and length(pairs) >= 2
  end

  defp valid_pairs?(_), do: false

  defp image_alt(image) do
    alt = Map.get(image, :alt_text) || Map.get(image, :caption)
    if present?(alt), do: alt
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp guess_mime(url) do
    case url
         |> URI.parse()
         |> Map.get(:path, "")
         |> to_string()
         |> Path.extname()
         |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".mp4" -> "video/mp4"
      ".m4v" -> "video/mp4"
      ".webm" -> "video/webm"
      ".mov" -> "video/quicktime"
      ".mp3" -> "audio/mpeg"
      ".m4a" -> "audio/mp4"
      ".aac" -> "audio/aac"
      ".ogg" -> "audio/ogg"
      ".opus" -> "audio/opus"
      ".wav" -> "audio/wav"
      _ -> nil
    end
  end
end
