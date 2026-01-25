defmodule Rss2Nostr.CLI.Commands.Source do
  @moduledoc """
  CLI commands for managing sources.
  """

  alias Rss2Nostr.Sources
  alias Rss2Nostr.CLI.Output

  def add(options) do
    attrs = %{
      name: options.name,
      url: options.url,
      type: options.type,
      language: options.language,
      default_post_kind: options.kind
    }

    case Sources.create_source(attrs) do
      {:ok, source} ->
        Output.success("Source created successfully!")
        Output.info("  ID: #{source.id}")
        Output.info("  Name: #{source.name}")
        Output.info("  URL: #{source.url}")

      {:error, changeset} ->
        Output.error("Failed to create source:")

        Enum.each(changeset.errors, fn {field, {msg, _}} ->
          Output.error("  #{field}: #{msg}")
        end)
    end
  end

  def list do
    sources = Sources.list_sources()

    if Enum.empty?(sources) do
      Output.info("No sources configured yet.")

      Output.info(
        "Add one with: rss2nostr source add --name \"My Feed\" --url \"https://example.com/feed.xml\""
      )
    else
      Output.info("Configured sources:\n")

      Output.info(
        String.pad_trailing("ID", 5) <>
          String.pad_trailing("Active", 8) <>
          String.pad_trailing("Type", 6) <>
          String.pad_trailing("Lang", 6) <>
          String.pad_trailing("Kind", 7) <>
          "Name / URL"
      )

      Output.info(String.duplicate("-", 80))

      Enum.each(sources, &print_source/1)
    end
  end

  def enable(id) do
    case Sources.enable_source(id) do
      {:ok, source} ->
        Output.success("Source '#{source.name}' enabled.")

      {:error, :not_found} ->
        Output.error("Source with ID #{id} not found.")

      {:error, changeset} ->
        Output.error("Failed to enable source: #{inspect(changeset.errors)}")
    end
  end

  def disable(id) do
    case Sources.disable_source(id) do
      {:ok, source} ->
        Output.success("Source '#{source.name}' disabled.")

      {:error, :not_found} ->
        Output.error("Source with ID #{id} not found.")

      {:error, changeset} ->
        Output.error("Failed to disable source: #{inspect(changeset.errors)}")
    end
  end

  def delete(id) do
    case Sources.get_source(id) do
      nil ->
        Output.error("Source with ID #{id} not found.")

      source ->
        case Sources.delete_source(source) do
          {:ok, _} ->
            Output.success("Source '#{source.name}' deleted.")

          {:error, _} ->
            Output.error("Failed to delete source.")
        end
    end
  end

  defp print_source(source) do
    active = if source.active, do: "yes", else: "no"

    line =
      String.pad_trailing(to_string(source.id), 5) <>
        String.pad_trailing(active, 8) <>
        String.pad_trailing(source.type, 6) <>
        String.pad_trailing(source.language, 6) <>
        String.pad_trailing(to_string(source.default_post_kind), 7) <>
        source.name

    Output.info(line)
    Output.info("     #{source.url}")
  end
end
