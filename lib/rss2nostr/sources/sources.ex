defmodule Rss2Nostr.Sources do
  @moduledoc """
  Context for managing RSS/Atom feed sources.
  """

  import Ecto.Query
  alias Rss2Nostr.Repo
  alias Rss2Nostr.Sources.Source

  @doc """
  Returns all sources.
  """
  @spec list_sources() :: [Source.t()]
  def list_sources do
    Repo.all(Source)
  end

  @doc """
  Returns all active sources.
  """
  @spec list_active_sources() :: [Source.t()]
  def list_active_sources do
    Source
    |> where([s], s.active == true)
    |> Repo.all()
  end

  @doc """
  Gets a single source by ID.
  """
  @spec get_source(integer() | binary()) :: Source.t() | nil
  def get_source(id), do: Repo.get(Source, id)

  @doc """
  Gets a single source by ID, raises if not found.
  """
  @spec get_source!(integer() | binary()) :: Source.t()
  def get_source!(id), do: Repo.get!(Source, id)

  @doc """
  Gets a source by URL.
  """
  @spec get_source_by_url(String.t()) :: Source.t() | nil
  def get_source_by_url(url) do
    Repo.get_by(Source, url: url)
  end

  @doc """
  Creates a new source.
  """
  @spec create_source(map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def create_source(attrs \\ %{}) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a source.
  """
  @spec update_source(Source.t(), map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def update_source(%Source{} = source, attrs) do
    source
    |> Source.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a source.
  """
  @spec delete_source(Source.t()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def delete_source(%Source{} = source) do
    Repo.delete(source)
  end

  @doc """
  Enables a source (by struct or ID).
  """
  @spec enable_source(Source.t() | integer() | binary()) ::
          {:ok, Source.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def enable_source(%Source{} = source) do
    update_source(source, %{active: true})
  end

  def enable_source(id) when is_integer(id) or is_binary(id) do
    case get_source(id) do
      nil -> {:error, :not_found}
      source -> enable_source(source)
    end
  end

  @doc """
  Disables a source (by struct or ID).
  """
  @spec disable_source(Source.t() | integer() | binary()) ::
          {:ok, Source.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def disable_source(%Source{} = source) do
    update_source(source, %{active: false})
  end

  def disable_source(id) when is_integer(id) or is_binary(id) do
    case get_source(id) do
      nil -> {:error, :not_found}
      source -> disable_source(source)
    end
  end

  @doc """
  Returns a changeset for tracking source changes.
  """
  @spec change_source(Source.t(), map()) :: Ecto.Changeset.t()
  def change_source(%Source{} = source, attrs \\ %{}) do
    Source.changeset(source, attrs)
  end

  @doc """
  Returns the total count of sources.
  """
  @spec count_sources() :: non_neg_integer()
  def count_sources do
    Repo.aggregate(Source, :count, :id)
  end

  @doc """
  Returns the count of active sources.
  """
  @spec count_active_sources() :: non_neg_integer()
  def count_active_sources do
    Source
    |> where([s], s.active == true)
    |> Repo.aggregate(:count, :id)
  end
end
