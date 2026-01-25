defmodule Rss2Nostr.Web.API.Sources do
  @moduledoc """
  API handlers for source operations.
  """

  alias Rss2Nostr.Sources
  alias Rss2Nostr.Sources.Source

  @spec list() :: [map()]
  def list do
    Sources.list_sources()
    |> Enum.map(&source_to_map/1)
  end

  @spec create(map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    attrs = %{
      name: params["name"],
      url: params["url"],
      type: params["type"] || "atom",
      language: params["language"] || "de",
      active: true
    }

    Sources.create_source(attrs)
  end

  @spec toggle(String.t()) :: {:ok, Source.t()} | {:error, atom() | Ecto.Changeset.t()}
  def toggle(id) do
    with {:ok, source_id} <- parse_id(id),
         %Source{} = source <- Sources.get_source(source_id) do
      if source.active do
        Sources.disable_source(source)
      else
        Sources.enable_source(source)
      end
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  @spec delete(String.t()) :: {:ok, Source.t()} | {:error, atom()}
  def delete(id) do
    with {:ok, source_id} <- parse_id(id),
         %Source{} = source <- Sources.get_source(source_id) do
      Sources.delete_source(source)
    else
      nil -> {:error, :not_found}
      {:error, :invalid_id} -> {:error, :invalid_id}
    end
  end

  defp source_to_map(source) do
    %{
      id: source.id,
      name: source.name,
      url: source.url,
      type: source.type,
      active: source.active,
      language: source.language
    }
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} when int_id > 0 -> {:ok, int_id}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_), do: {:error, :invalid_id}
end
