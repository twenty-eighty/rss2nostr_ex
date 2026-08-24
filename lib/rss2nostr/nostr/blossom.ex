defmodule Rss2Nostr.Nostr.Blossom do
  @moduledoc """
  Blossom blob storage (BUD-01 / BUD-02 / BUD-04 / BUD-11).

  Uploads images and audio with `PUT /upload` and a kind 24242 authorization event.
  Blobs larger than 5MB that still have a public HTTPS origin are sent with
  BUD-04 `PUT /mirror` so the server fetches the file itself. That avoids
  inbound PUTs dying at a 60s proxy body timeout (HTTP 499 / EOF).
  This replaces NIP-96.
  """

  alias Rss2Nostr.HTTP
  alias Rss2Nostr.Nostr.Blossom.{Client, PostImages}
  alias Rss2Nostr.Nostr.Signer

  @type upload_result :: %{
          url: String.t(),
          sha256: String.t() | nil,
          size: integer() | nil,
          type: String.t() | nil,
          nip94: list(),
          dimensions: {integer(), integer()} | nil
        }

  @doc """
  Configured Blossom server from `NOSTR_UPLOAD_ENDPOINT`, or `nil`.
  """
  @spec configured_server() :: String.t() | nil
  def configured_server do
    case Application.get_env(:rss2nostr, :nostr, []) |> Access.get(:upload_endpoint) do
      nil ->
        nil

      "" ->
        nil

      url when is_binary(url) ->
        case String.trim(url) do
          "" -> nil
          trimmed -> String.trim_trailing(trimmed, "/")
        end

      _ ->
        nil
    end
  end

  @doc """
  The configured upload server, or an empty list if none is set.
  There are no fallback servers.
  """
  @spec servers() :: [String.t()]
  def servers do
    case configured_server() do
      nil -> []
      endpoint -> [endpoint]
    end
  end

  @doc """
  True when `url` is already hosted on the given Blossom server
  (defaults to `NOSTR_UPLOAD_ENDPOINT`).
  """
  @spec already_hosted?(String.t(), String.t() | nil) :: boolean()
  def already_hosted?(url, server \\ nil)

  def already_hosted?(url, server) when is_binary(url) do
    image_host = server_host(url)
    blossom_host = server_host(server || configured_server())

    is_binary(image_host) and is_binary(blossom_host) and image_host == blossom_host
  end

  def already_hosted?(_, _), do: false

  @doc """
  BUD-02 upload URL for a server base (`https://host` → `https://host/upload`).
  """
  @spec upload_url(String.t()) :: String.t()
  def upload_url(server_url) do
    base = server_url |> String.trim() |> String.trim_trailing("/")

    if String.ends_with?(base, "/upload") do
      base
    else
      base <> "/upload"
    end
  end

  @doc """
  BUD-04 mirror URL for a server base.
  """
  @spec mirror_url(String.t()) :: String.t()
  def mirror_url(server_url) do
    base = server_url |> String.trim() |> String.trim_trailing("/")

    cond do
      String.ends_with?(base, "/mirror") -> base
      String.ends_with?(base, "/upload") -> String.replace_suffix(base, "/upload", "/mirror")
      true -> base <> "/mirror"
    end
  end

  @doc """
  BUD-11 `Authorization` header for a signed kind 24242 event.
  """
  @spec authorization_header(map()) :: String.t()
  def authorization_header(signed_event), do: Client.authorization_header(signed_event)

  @doc """
  HEAD `/upload` to see if a Blossom server is reachable.
  """
  @spec probe_server(String.t()) :: {:ok, integer()} | {:error, term()}
  def probe_server(server_url) do
    case HTTP.head(upload_url(server_url), receive_timeout: 10_000, retry: false) do
      {:ok, %{status: status}} when status in [200, 201, 400, 401, 403, 411, 413, 415] ->
        {:ok, status}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  Uploads a local file.

  Options:
  - `:private_key` (required)
  - `:server` — Blossom base URL (default: `NOSTR_UPLOAD_ENDPOINT` only)
  - `:content_type`
  """
  @spec upload_file(String.t(), keyword()) :: {:ok, upload_result()} | {:error, term()}
  def upload_file(file_path, opts \\ []) do
    case File.read(file_path) do
      {:ok, data} ->
        opts = Keyword.put_new(opts, :content_type, Client.guess_content_type(file_path))
        Client.upload_data(data, Path.basename(file_path), opts)

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  @doc """
  Uploads binary data. Filename is unused by Blossom (hash-addressed) but kept
  for call-site compatibility.
  """
  @spec upload_data(binary(), String.t(), keyword()) :: {:ok, upload_result()} | {:error, term()}
  def upload_data(data, filename, opts \\ []), do: Client.upload_data(data, filename, opts)

  @doc """
  Uploads a post's featured image to the configured Blossom server if needed.
  """
  @spec ensure_post_image(Rss2Nostr.Posts.Post.t(), Signer.signer() | binary()) ::
          {:ok, Rss2Nostr.Posts.Post.t()} | {:error, term()}
  def ensure_post_image(post, signer), do: PostImages.ensure_post_images(post, signer)

  @doc """
  Uploads the featured image and every referenced article image, then
  rewrites Markdown URLs to the Blossom copies.

  `signer` is `{:private_key, key}`, `{:bunker, url}`, or a raw key binary.
  Does not change post status. Returns `{:error, reason}` when any image
  is still missing so the caller can leave the post pending.
  """
  @spec ensure_post_images(Rss2Nostr.Posts.Post.t(), Signer.signer() | binary()) ::
          {:ok, Rss2Nostr.Posts.Post.t()} | {:error, term()}
  def ensure_post_images(post, signer), do: PostImages.ensure_post_images(post, signer)

  @doc """
  Marks already-hosted image records as uploaded without contacting Blossom.
  """
  @spec stamp_hosted_images(Rss2Nostr.Posts.Post.t()) ::
          {Rss2Nostr.Posts.Post.t(), %{String.t() => String.t()}}
  def stamp_hosted_images(post), do: PostImages.stamp_hosted_images(post)

  @doc """
  True when the featured image or any article image still needs a Blossom URL.
  """
  @spec pending_images?(Rss2Nostr.Posts.Post.t()) :: boolean()
  def pending_images?(post), do: PostImages.pending_images?(post)

  @doc """
  Downloads an image from a URL and uploads it to Blossom.
  """
  @spec upload_from_url(String.t(), keyword()) :: {:ok, upload_result()} | {:error, term()}
  def upload_from_url(image_url, opts \\ []), do: Client.upload_from_url(image_url, opts)

  @doc """
  Parses a BUD-02 blob descriptor JSON object or encoded string.
  """
  @spec parse_descriptor(map() | String.t()) :: {:ok, upload_result()} | {:error, atom()}
  def parse_descriptor(body), do: Client.parse_descriptor(body)

  @spec server_host(String.t() | nil) :: String.t() | nil
  defp server_host(nil), do: nil

  defp server_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> String.downcase(host)
      _ -> nil
    end
  end
end
