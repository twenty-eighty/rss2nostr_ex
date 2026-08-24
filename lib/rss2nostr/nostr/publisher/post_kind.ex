defmodule Rss2Nostr.Nostr.Publisher.PostKind do
  @moduledoc false

  alias Rss2Nostr.Nostr.{Event, Relays, Signer}
  alias Rss2Nostr.Nostr.Publisher.PostContext, as: Ctx
  alias Rss2Nostr.Sources.Source

  @spec encrypted_draft?(map()) :: boolean()
  def encrypted_draft?(post) do
    case Ctx.source_of(post) do
      %Source{} = source ->
        Signer.encrypted_draft?(source)

      _ ->
        case Ctx.field(post, :publish_as) do
          "draft_plain" ->
            false

          value when value in ["article", "video"] ->
            false

          "draft" ->
            true

          _ ->
            case Ctx.field(post, :type) do
              30023 -> false
              34235 -> false
              30024 -> true
              31234 -> true
              _ -> true
            end
        end
    end
  end

  @spec plain_draft?(map()) :: boolean()
  def plain_draft?(post) do
    case Ctx.source_of(post) do
      %Source{} = source -> Signer.plain_draft?(source)
      _ -> Ctx.field(post, :publish_as) == "draft_plain"
    end
  end

  @spec draft_kind?(map()) :: boolean()
  def draft_kind?(post), do: encrypted_draft?(post) or plain_draft?(post)

  @spec video?(map()) :: boolean()
  def video?(post) do
    Ctx.field(post, :type) == Event.kind_video() or
      case Ctx.source_of(post) do
        %Source{} = source -> Source.video?(source)
        _ -> Ctx.field(post, :publish_as) == "video"
      end
  end

  @spec long_form_kind(map()) :: integer()
  def long_form_kind(post) do
    cond do
      video?(post) -> Event.kind_video()
      draft_kind?(post) -> Event.kind_long_form_draft()
      true -> Event.kind_long_form()
    end
  end

  @spec published_kind(map()) :: integer()
  def published_kind(post) do
    cond do
      encrypted_draft?(post) -> Event.kind_draft_wrap()
      plain_draft?(post) -> Event.kind_long_form_draft()
      video?(post) -> Event.kind_video()
      true -> Event.kind_long_form()
    end
  end

  @spec public_article?(map()) :: boolean()
  def public_article?(post) do
    not draft_kind?(post) and Relays.target_for(post) == :public
  end

  @spec draft_author(map(), map() | Source.t() | nil) :: String.t() | nil
  def draft_author(post, source \\ nil) do
    source = source || Ctx.source_of(post)

    if draft_kind?(post) do
      Ctx.field(source, :pubkey)
    end
  end
end
