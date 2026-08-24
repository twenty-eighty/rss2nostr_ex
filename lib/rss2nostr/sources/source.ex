defmodule Rss2Nostr.Sources.Source do
  @moduledoc """
  Schema for RSS/Atom feed sources.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Rss2Nostr.Nostr.{Event, Keys, Secret, Signer}

  @type_values ~w(rss atom)
  @mode_values ~w(setup automated)
  @publish_as_values ~w(draft draft_plain article video)

  @type t :: %__MODULE__{}

  schema "sources" do
    field(:name, :string)
    field(:url, :string)
    field(:type, :string, default: "rss")
    field(:active, :boolean, default: true)
    field(:language, :string, default: "de")
    field(:public, :boolean, default: false)
    field(:mode, :string, default: "setup")
    field(:publish_as, :string, default: "draft")

    # Nostr-specific
    field(:default_post_kind, :integer, default: 30024)
    field(:pubkey, :string)
    field(:bunker_connection, :string)
    field(:signing_nsec_ciphertext, :string)
    field(:signing_nsec, :string, virtual: true)

    # Filters
    field(:publish_after_date, :utc_datetime)
    field(:fetch_source_from, :string, default: "fetch_from_url")
    field(:staging_hold_minutes, :integer, default: 0)
    field(:notify_pubkey, :string)
    field(:fixed_hashtags, {:array, :string}, default: [])
    field(:excluded_hashtags, {:array, :string}, default: [])

    # Additional options
    field(:options, :map, default: %{})

    has_many(:posts, Rss2Nostr.Posts.Post)

    timestamps()
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(source, attrs) do
    source
    |> cast(normalize_hashtag_attrs(attrs), [
      :name,
      :url,
      :type,
      :active,
      :language,
      :public,
      :mode,
      :publish_as,
      :default_post_kind,
      :pubkey,
      :bunker_connection,
      :signing_nsec_ciphertext,
      :signing_nsec,
      :publish_after_date,
      :fetch_source_from,
      :staging_hold_minutes,
      :notify_pubkey,
      :fixed_hashtags,
      :excluded_hashtags,
      :options
    ])
    |> validate_required([:name, :url])
    |> validate_inclusion(:type, @type_values)
    |> validate_inclusion(:mode, @mode_values)
    |> validate_inclusion(:publish_as, @publish_as_values)
    |> validate_inclusion(:default_post_kind, [30023, 30024, 34235])
    |> validate_inclusion(:fetch_source_from, ~w(content fetch_from_url))
    |> normalize_pubkey()
    |> normalize_notify_pubkey()
    |> validate_number(:staging_hold_minutes, greater_than_or_equal_to: 0)
    |> encrypt_signing_nsec()
    |> sync_post_kind()
    |> validate_publish_identity()
    |> validate_automated_signer()
    |> unique_constraint(:url)
  end

  @spec setup?(t() | map() | nil) :: boolean()
  def setup?(%{mode: "automated"}), do: false
  def setup?(_), do: true

  @spec automated?(t() | map() | nil) :: boolean()
  def automated?(%{mode: "automated"}), do: true
  def automated?(_), do: false

  @spec video?(t() | map() | nil) :: boolean()
  def video?(%{publish_as: "video"}), do: true
  def video?(%{default_post_kind: 34235}), do: true
  def video?(_), do: false

  @doc """
  True when video files should be uploaded to Blossom.

  `options["mirror_media"]` of `"original"` (or false) keeps the feed URL
  in the Nostr event instead.
  """
  @spec mirror_media?(t() | map() | nil) :: boolean()
  def mirror_media?(source) when is_map(source) do
    case option(source, "mirror_media") do
      value when value in [false, "false", "original", "0"] -> false
      _ -> true
    end
  end

  def mirror_media?(_), do: true

  @spec option(t() | map(), String.t()) :: term()
  defp option(%{options: options}, key) when is_map(options) do
    Map.get(options, key) || Map.get(options, String.to_atom(key))
  end

  defp option(_, _), do: nil

  @spec normalize_hashtag_attrs(map()) :: map()
  defp normalize_hashtag_attrs(attrs) when is_map(attrs) do
    attrs
    |> normalize_hashtag_field(:fixed_hashtags)
    |> normalize_hashtag_field(:excluded_hashtags)
  end

  defp normalize_hashtag_attrs(attrs), do: attrs

  @spec normalize_hashtag_field(map(), atom()) :: map()
  defp normalize_hashtag_field(attrs, field) do
    string = Atom.to_string(field)

    cond do
      Map.has_key?(attrs, field) ->
        Map.put(attrs, field, Event.normalize_hashtags(attrs[field]))

      Map.has_key?(attrs, string) ->
        Map.put(attrs, string, Event.normalize_hashtags(attrs[string]))

      true ->
        attrs
    end
  end

  @spec normalize_pubkey(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp normalize_pubkey(changeset) do
    normalize_hex_pubkey(changeset, :pubkey)
  end

  @spec normalize_notify_pubkey(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp normalize_notify_pubkey(changeset) do
    normalize_hex_pubkey(changeset, :notify_pubkey)
  end

  @spec normalize_hex_pubkey(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  defp normalize_hex_pubkey(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      "" ->
        put_change(changeset, field, nil)

      value when is_binary(value) ->
        case Keys.parse_public_key(value) do
          {:ok, hex} -> put_change(changeset, field, hex)
          {:error, _} -> add_error(changeset, field, "must be an npub or hex public key")
        end

      _ ->
        add_error(changeset, field, "must be an npub or hex public key")
    end
  end

  @spec encrypt_signing_nsec(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp encrypt_signing_nsec(changeset) do
    case get_change(changeset, :signing_nsec) do
      value when is_binary(value) and value != "" ->
        case Keys.parse_private_key(value) do
          {:ok, _} ->
            put_change(changeset, :signing_nsec_ciphertext, Secret.encrypt(value))

          {:error, _} ->
            add_error(changeset, :signing_nsec, "must be an nsec or hex private key")
        end

      _ ->
        changeset
    end
  end

  @spec sync_post_kind(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp sync_post_kind(changeset) do
    case get_field(changeset, :publish_as) do
      "article" ->
        put_change(changeset, :default_post_kind, 30023)

      "video" ->
        put_change(changeset, :default_post_kind, 34235)

      value when value in ["draft", "draft_plain"] ->
        put_change(changeset, :default_post_kind, 30024)

      _ ->
        changeset
    end
  end

  @spec validate_publish_identity(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_publish_identity(changeset) do
    if publish_as_submitted?(changeset) do
      case get_field(changeset, :publish_as) do
        value when value in ["draft", "draft_plain"] ->
          changeset
          |> validate_required([:pubkey], message: "is required for drafts")

        value when value in ["article", "video"] ->
          validate_article_signer(changeset)

        _ ->
          changeset
      end
    else
      changeset
    end
  end

  @spec publish_as_submitted?(Ecto.Changeset.t()) :: boolean()
  defp publish_as_submitted?(changeset) do
    params = changeset.params || %{}
    Map.has_key?(params, "publish_as") or Map.has_key?(params, :publish_as)
  end

  @spec validate_article_signer(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_article_signer(changeset) do
    nsec = get_field(changeset, :signing_nsec)
    cipher = get_field(changeset, :signing_nsec_ciphertext)
    bunker = get_field(changeset, :bunker_connection)

    if present?(nsec) or present?(cipher) or present?(bunker) do
      changeset
    else
      add_error(changeset, :signing_nsec, "or a bunker URL is required for articles and videos")
    end
  end

  @spec present?(term()) :: boolean()
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  @spec validate_automated_signer(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_automated_signer(changeset) do
    mode = get_field(changeset, :mode)

    if mode == "automated" and changing_to_automated?(changeset) do
      source = apply_changes(changeset)

      if Signer.configured?(source) do
        changeset
      else
        add_error(
          changeset,
          :mode,
          "needs a signing key before automation (app nsec for drafts, or a source nsec/bunker for articles)"
        )
      end
    else
      changeset
    end
  end

  @spec changing_to_automated?(Ecto.Changeset.t()) :: boolean()
  defp changing_to_automated?(changeset) do
    changed?(changeset, :mode) or changed?(changeset, :publish_as) or
      changed?(changeset, :signing_nsec) or changed?(changeset, :bunker_connection)
  end
end
