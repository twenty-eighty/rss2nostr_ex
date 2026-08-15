defmodule Rss2Nostr.Nostr.Relays do
  @moduledoc """
  Configured Nostr relay lists.

  There are two audiences:

  * `:test` — relays used while a source is being tried out
  * `:public` — relays used for sources that should be published openly

  Each source has a `public` flag that selects the list once it is
  `automated`. Sources in `setup` always use the test list. An explicit
  `:relays` option is stripped of public relays while the source is in setup.
  """

  alias Rss2Nostr.Posts.Post
  alias Rss2Nostr.Repo
  alias Rss2Nostr.Sources.Source

  @type audience :: :test | :public

  @doc """
  Relays used for testing unpublished or trial sources.
  """
  @spec test() :: [String.t()]
  def test, do: list(:test)

  @doc """
  Relays used for sources marked public.
  """
  @spec public() :: [String.t()]
  def public, do: list(:public)

  @doc """
  Relays for an audience (`:test` or `:public`).
  """
  @spec for(audience() | String.t() | atom() | nil) :: [String.t()]
  def for(:test), do: test()
  def for(:public), do: public()
  def for("test"), do: test()
  def for("public"), do: public()
  def for(_), do: test()

  @doc """
  Relays for a post, based on its source's mode and `public` flag.

  Missing or unloaded sources use the test list so articles are not published
  widely by accident.
  """
  @spec for_post(Post.t() | map()) :: [String.t()]
  def for_post(post) do
    post
    |> audience_for_post()
    |> __MODULE__.for()
  end

  @doc """
  Relays that may be used to publish a post.

  Setup sources always get the test list. An explicit relay list cannot
  include public relays unless the source is automated.
  """
  @spec publish_relays(Post.t() | Source.t() | map(), keyword()) :: [String.t()]
  def publish_relays(post_or_source, opts \\ []) do
    audience = audience_of(post_or_source)
    requested = Keyword.get(opts, :relays)
    forced = parse_audience(Keyword.get(opts, :audience))

    effective =
      cond do
        audience == :test -> :test
        forced in [:test, :public] -> forced
        true -> audience
      end

    case requested do
      list when is_list(list) ->
        if effective == :test, do: reject_public(list), else: list

      _ ->
        __MODULE__.for(effective)
    end
  end

  @doc """
  Audience for a post (`:public` only when the source is automated and public).
  """
  @spec audience_for_post(Post.t() | map()) :: audience()
  def audience_for_post(%{source: %Source{} = source}), do: audience_for_source(source)

  def audience_for_post(%{source: %Ecto.Association.NotLoaded{}} = post) do
    post
    |> Repo.preload(:source)
    |> audience_for_post()
  end

  def audience_for_post(_), do: :test

  @doc """
  Audience for a source. Setup always uses `:test`.
  """
  @spec audience_for_source(Source.t() | map() | nil) :: audience()
  def audience_for_source(%{mode: "automated", public: true}), do: :public
  def audience_for_source(_), do: :test

  defp audience_of(%Source{} = source), do: audience_for_source(source)
  defp audience_of(post), do: audience_for_post(post)

  defp reject_public([]), do: []

  defp reject_public(list) do
    public_set = MapSet.new(public())
    filtered = Enum.reject(list, &MapSet.member?(public_set, &1))
    if filtered == [], do: test(), else: filtered
  end

  @doc """
  Default audience when none is specified (dev/test: `:test`, prod: `:public`).
  Override with `NOSTR_RELAY_AUDIENCE` or `:nostr` `:relay_audience`.
  """
  @spec default_audience() :: audience()
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
  True when both relay lists are empty.
  """
  @spec empty?() :: boolean()
  def empty?, do: test() == [] and public() == []

  @doc """
  Both configured lists.
  """
  @spec all() :: %{test: [String.t()], public: [String.t()]}
  def all, do: configured_relays()

  @doc """
  Parses `"test"` / `"public"` from CLI or form params. Returns `nil` if absent or invalid.
  """
  @spec parse_audience(term()) :: audience() | nil
  def parse_audience(nil), do: nil
  def parse_audience(:test), do: :test
  def parse_audience(:public), do: :public
  def parse_audience("test"), do: :test
  def parse_audience("public"), do: :public

  def parse_audience(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
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

  defp list(audience) do
    configured_relays()
    |> Map.get(audience, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp configured_relays do
    case Application.get_env(:rss2nostr, :nostr, []) |> Access.get(:relays) do
      %{test: test, public: public} ->
        %{test: wrap_list(test), public: wrap_list(public)}

      map when is_map(map) ->
        %{test: wrap_list(Map.get(map, :test, [])), public: wrap_list(Map.get(map, :public, []))}

      list when is_list(list) ->
        %{test: wrap_list(list), public: []}

      _ ->
        %{test: [], public: []}
    end
  end

  defp wrap_list(list) when is_list(list), do: list
  defp wrap_list(nil), do: []
  defp wrap_list(other), do: List.wrap(other)
end
