defmodule Rss2Nostr.Nostr.Relays do
  @moduledoc """
  Configured Nostr relay lists.

  There are four lists:

  * `:draft` — relays used for NIP-37 draft wraps (Pareto client)
  * `:test` — fallback when the draft list is empty
  * `:public` — relays used for article and video sources
  * `:inbox` — extra relays always used when sending NIP-17 DMs

  Draft sources always use the draft list. If that list is empty, they
  fall back to the test list.

  Article and video sources use the public list. Setup vs automated only
  controls the scheduler, not which relays are used. An explicit `:relays`
  option is stripped of public relays only when the target is not public
  (unknown/unloaded sources).
  """

  alias Rss2Nostr.Nostr.Signer
  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Repo
  alias Rss2Nostr.Sources.Source

  @type audience :: :draft | :test | :public

  @doc """
  Relays used for NIP-37 draft wraps.
  """
  @spec draft() :: [String.t()]
  def draft, do: list(:draft)

  @doc """
  Relays used for testing unpublished or trial sources.
  """
  @spec test() :: [String.t()]
  def test, do: list(:test)

  @doc """
  Relays used for article and video sources.
  """
  @spec public() :: [String.t()]
  def public, do: list(:public)

  @doc """
  Extra relays always included when sending NIP-17 DMs.
  """
  @spec inbox() :: [String.t()]
  def inbox, do: list(:inbox)

  @doc """
  Relays for an audience (`:draft`, `:test`, or `:public`).

  `:draft` falls back to the test list when no draft relays are set.
  """
  @spec for(audience() | String.t() | atom() | nil) :: [String.t()]
  def for(:draft), do: draft_or_test()
  def for(:test), do: test()
  def for(:public), do: public()
  def for("draft"), do: draft_or_test()
  def for("test"), do: test()
  def for("public"), do: public()
  def for(_), do: test()

  @doc """
  Relays for a post: draft list when the source publishes drafts,
  otherwise the public list for articles and videos.

  Missing or unloaded sources use the test list so articles are not published
  widely by accident.
  """
  @spec for_post(Post.t() | map()) :: [String.t()]
  def for_post(post) do
    post
    |> target_for()
    |> __MODULE__.for()
  end

  @doc """
  Relays that may be used to publish a post or source.

  Draft sources always get the draft list (or test, if draft is empty).
  Those URLs are kept even when they also appear on the public list.
  Article and video sources use the public list. An explicit relay list
  cannot include public relays unless the source publishes articles or videos.
  """
  @spec publish_relays(Post.t() | Source.t() | map(), keyword()) :: [String.t()]
  def publish_relays(post_or_source, opts \\ []) do
    requested = Keyword.get(opts, :relays)
    forced = parse_audience(Keyword.get(opts, :audience))

    case requested do
      list when is_list(list) ->
        if restrict_public?(post_or_source), do: reject_public(list), else: list

      _ ->
        configured_publish_relays(post_or_source, forced)
    end
  end

  @doc """
  Which list a post or source publishes to (`:draft`, `:test`, or `:public`).
  """
  @spec target_for(Post.t() | Source.t() | map() | nil) :: audience()
  def target_for(post_or_source) do
    if draft?(post_or_source), do: :draft, else: audience_of(post_or_source)
  end

  @doc """
  Audience for a post (`:public` for article and video sources).

  Does not account for drafts; use `target_for/1` when choosing a relay list.
  """
  @spec audience_for_post(Post.t() | map()) :: :test | :public
  def audience_for_post(%{source: %Source{} = source}), do: audience_for_source(source)

  def audience_for_post(%{source: %Ecto.Association.NotLoaded{}} = post) do
    post
    |> Repo.preload(:source)
    |> audience_for_post()
  end

  def audience_for_post(_), do: :test

  @doc """
  Audience for a source. Article and video sources use `:public`.
  """
  @spec audience_for_source(Source.t() | map() | nil) :: :test | :public
  def audience_for_source(%Source{} = source) do
    if Signer.draft?(source), do: :test, else: :public
  end

  def audience_for_source(%{publish_as: value}) when value in ["article", "video"], do: :public
  def audience_for_source(%{default_post_kind: kind}) when kind in [30023, 34235], do: :public
  def audience_for_source(_), do: :test

  @doc """
  Default audience when none is specified (dev/test: `:test`, prod: `:public`).
  Override with `NOSTR_RELAY_AUDIENCE` or `:nostr` `:relay_audience`.
  """
  @spec default_audience() :: :test | :public
  def default_audience do
    case Application.get_env(:rss2nostr, :nostr, []) |> Access.get(:relay_audience) do
      :public -> :public
      "public" -> :public
      :test -> :test
      "test" -> :test
      _ -> :test
    end
  end

  @doc """
  True when the test, public, and draft lists are all empty.
  """
  @spec empty?() :: boolean()
  def empty?, do: test() == [] and public() == [] and draft() == []

  @doc """
  Configured lists.
  """
  @spec all() :: %{
          draft: [String.t()],
          test: [String.t()],
          public: [String.t()],
          inbox: [String.t()]
        }
  def all, do: configured_relays()

  @doc """
  Parses `"draft"` / `"test"` / `"public"` from CLI or form params.
  Returns `nil` if absent or invalid.
  """
  @spec parse_audience(term()) :: audience() | nil
  def parse_audience(nil), do: nil
  def parse_audience(:draft), do: :draft
  def parse_audience(:test), do: :test
  def parse_audience(:public), do: :public
  def parse_audience("draft"), do: :draft
  def parse_audience("test"), do: :test
  def parse_audience("public"), do: :public

  def parse_audience(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "draft" -> :draft
      "test" -> :test
      "public" -> :public
      _ -> nil
    end
  end

  def parse_audience(_), do: nil

  @doc """
  Splits a comma-separated relay string. Returns `nil` when the input is `nil`.
  """
  @spec parse_list(String.t() | [String.t()] | nil) :: [String.t()] | nil
  def parse_list(nil), do: nil

  def parse_list(list) when is_list(list) do
    list
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def parse_list(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec configured_publish_relays(Post.t() | Source.t() | map(), audience() | nil) :: [String.t()]
  defp configured_publish_relays(post_or_source, forced) do
    cond do
      draft?(post_or_source) ->
        draft_or_test()

      audience_of(post_or_source) == :test ->
        test()

      forced in [:test, :public] ->
        __MODULE__.for(forced)

      true ->
        __MODULE__.for(audience_of(post_or_source))
    end
  end

  @spec restrict_public?(Post.t() | Source.t() | map()) :: boolean()
  defp restrict_public?(post_or_source) do
    not draft?(post_or_source) and audience_of(post_or_source) == :test
  end

  @spec audience_of(Post.t() | Source.t() | map()) :: :test | :public
  defp audience_of(%Source{} = source), do: audience_for_source(source)
  defp audience_of(post), do: audience_for_post(post)

  @spec draft?(Post.t() | Source.t() | map()) :: boolean()
  defp draft?(%Source{} = source), do: Signer.draft?(source)

  defp draft?(%{source: %Source{} = source}), do: draft?(source)

  defp draft?(%{source: %Ecto.Association.NotLoaded{}} = post) do
    post
    |> Repo.preload(:source)
    |> draft?()
  end

  defp draft?(%{publish_as: value}) when value in ["draft", "draft_plain"], do: true
  defp draft?(_), do: false

  @spec draft_or_test() :: [String.t()]
  defp draft_or_test do
    case draft() do
      [] -> test()
      list -> list
    end
  end

  @spec reject_public([String.t()]) :: [String.t()]
  defp reject_public([]), do: []

  defp reject_public(list) do
    public_set = MapSet.new(public())
    filtered = Enum.reject(list, &MapSet.member?(public_set, &1))
    if filtered == [], do: test(), else: filtered
  end

  @spec list(audience()) :: [String.t()]
  defp list(audience) do
    configured_relays()
    |> Map.get(audience, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec configured_relays() :: %{draft: [String.t()], test: [String.t()], public: [String.t()], inbox: [String.t()]}
  defp configured_relays do
    case Application.get_env(:rss2nostr, :nostr, []) |> Access.get(:relays) do
      %{test: test, public: public} = map ->
        %{
          draft: wrap_list(Map.get(map, :draft, [])),
          test: wrap_list(test),
          public: wrap_list(public),
          inbox: wrap_list(Map.get(map, :inbox, []))
        }

      map when is_map(map) ->
        %{
          draft: wrap_list(Map.get(map, :draft, [])),
          test: wrap_list(Map.get(map, :test, [])),
          public: wrap_list(Map.get(map, :public, [])),
          inbox: wrap_list(Map.get(map, :inbox, []))
        }

      list when is_list(list) ->
        %{draft: [], test: wrap_list(list), public: [], inbox: []}

      _ ->
        %{draft: [], test: [], public: [], inbox: []}
    end
  end

  @spec wrap_list(term()) :: list()
  defp wrap_list(list) when is_list(list), do: list
  defp wrap_list(nil), do: []
  defp wrap_list(other), do: List.wrap(other)
end
