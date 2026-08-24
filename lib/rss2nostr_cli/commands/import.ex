defmodule Rss2Nostr.CLI.Commands.Import do
  @moduledoc """
  CLI command for importing from RSS/Atom sources.
  """

  alias Rss2Nostr.CLI.Output
  alias Rss2Nostr.Import.Importer
  alias Rss2Nostr.Sources

  @spec run(map(), map()) :: :ok
  def run(options, flags) do
    force = Map.get(flags, :force, false)
    source_id = Map.get(options, :source)

    Output.info("Starting import...")

    if force do
      Output.info("  Force mode: enabled (will reimport duplicates)")
    end

    results =
      if source_id do
        Output.info("  Importing from source ID: #{source_id}")

        case Importer.import_from_source_id(source_id, force: force) do
          {:ok, result} ->
            [result]

          {:error, :source_not_found} ->
            Output.error("Source with ID #{source_id} not found.")
            []
        end
      else
        active_count = length(Sources.list_active_sources())
        Output.info("  Importing from #{active_count} active source(s)")
        Importer.import_all(force: force)
      end

    # Print summary
    Output.info("")
    Output.info("=== Import Summary ===")

    total_imported = Enum.reduce(results, 0, &(&1.imported + &2))
    total_skipped = Enum.reduce(results, 0, &(&1.skipped + &2))
    total_errors = Enum.reduce(results, 0, &(length(&1.errors) + &2))

    Enum.each(results, fn result ->
      status = if Enum.empty?(result.errors), do: "OK", else: "ERRORS"

      Output.info(
        "  #{result.source.name}: #{result.imported} imported, #{result.skipped} skipped [#{status}]"
      )

      Enum.each(result.errors, fn error ->
        Output.error("    - #{error}")
      end)
    end)

    Output.info("")

    Output.info(
      "Total: #{total_imported} imported, #{total_skipped} skipped, #{total_errors} errors"
    )

    if total_imported > 0 do
      Output.success("Import completed successfully!")
    else
      if total_errors > 0 do
        Output.warning("Import completed with errors.")
      else
        Output.info("No new articles to import.")
      end
    end
  end
end
