defmodule Rss2Nostr.CLI do
  @moduledoc """
  Command Line Interface for RSS2Nostr.
  """

  alias Rss2Nostr.CLI.Commands

  @spec main([String.t()]) :: term()
  def main(args) do
    # Ensure the application is started
    Application.ensure_all_started(:rss2nostr)

    optimus =
      Optimus.new!(
        name: "rss2nostr",
        description: "Import RSS/Atom feeds and publish to Nostr",
        version: "0.1.0",
        author: "RSS2Nostr Team",
        about:
          "A tool to import RSS/Atom feeds and publish them as Nostr long-form content (NIP-23)",
        allow_unknown_args: false,
        subcommands: [
          source: [
            name: "source",
            about: "Manage RSS/Atom sources",
            subcommands: [
              add: [
                name: "add",
                about: "Add a new source",
                options: [
                  name: [
                    short: "-n",
                    long: "--name",
                    help: "Source name",
                    required: true
                  ],
                  url: [
                    short: "-u",
                    long: "--url",
                    help: "Feed URL",
                    required: true
                  ],
                  type: [
                    short: "-t",
                    long: "--type",
                    help: "Feed type (rss or atom)",
                    default: "rss"
                  ],
                  language: [
                    short: "-l",
                    long: "--language",
                    help: "Language code (ISO 639-1)",
                    default: "de"
                  ],
                  kind: [
                    short: "-k",
                    long: "--kind",
                    help: "Nostr event kind (30023 article or 30024 draft)",
                    default: "30023",
                    parser: :integer
                  ]
                ],
                flags: [
                  public: [
                    long: "--public",
                    help: "Deprecated: articles and videos always use public relays"
                  ]
                ]
              ],
              list: [
                name: "list",
                about: "List all sources"
              ],
              enable: [
                name: "enable",
                about: "Enable a source",
                args: [
                  id: [
                    help: "Source ID",
                    required: true,
                    parser: :integer
                  ]
                ]
              ],
              disable: [
                name: "disable",
                about: "Disable a source",
                args: [
                  id: [
                    help: "Source ID",
                    required: true,
                    parser: :integer
                  ]
                ]
              ],
              delete: [
                name: "delete",
                about: "Delete a source",
                args: [
                  id: [
                    help: "Source ID",
                    required: true,
                    parser: :integer
                  ]
                ]
              ],
              duplicate: [
                name: "duplicate",
                about: "Duplicate a source's settings into a new source",
                args: [
                  id: [
                    help: "Source ID",
                    required: true,
                    parser: :integer
                  ]
                ],
                options: [
                  name: [
                    short: "-n",
                    long: "--name",
                    help: "Name for the copy"
                  ],
                  url: [
                    short: "-u",
                    long: "--url",
                    help: "Feed URL for the copy"
                  ]
                ]
              ]
            ]
          ],
          import: [
            name: "import",
            about: "Import articles from sources",
            flags: [
              force: [
                short: "-f",
                long: "--force",
                help: "Force reimport of duplicates"
              ]
            ],
            options: [
              source: [
                short: "-s",
                long: "--source",
                help: "Import from specific source ID",
                parser: :integer
              ],
              limit: [
                short: "-l",
                long: "--limit",
                help: "Limit number of articles to import",
                parser: :integer
              ]
            ]
          ],
          process: [
            name: "process",
            about: "Process new posts (HTML to Markdown)",
            options: [
              limit: [
                short: "-l",
                long: "--limit",
                help: "Limit number of posts to process",
                default: "10",
                parser: :integer
              ]
            ]
          ],
          export: [
            name: "export",
            about: "Export processed posts to Nostr",
            flags: [
              dry_run: [
                short: "-d",
                long: "--dry-run",
                help: "Dry run - don't actually publish"
              ],
              upload_images: [
                short: "-u",
                long: "--upload-images",
                help: "Upload images to a Blossom server before publishing"
              ]
            ],
            options: [
              id: [
                long: "--id",
                help: "Export specific post by ID",
                parser: :integer
              ],
              limit: [
                short: "-l",
                long: "--limit",
                help: "Limit number of posts to export",
                default: "10",
                parser: :integer
              ],
              nsec: [
                long: "--nsec",
                help: "Nostr private key (nsec or hex format)"
              ],
              bunker: [
                short: "-b",
                long: "--bunker",
                help: "NIP-46 bunker URL for remote signing"
              ],
              relays: [
                short: "-r",
                long: "--relays",
                help: "Comma-separated list of relay URLs (overrides test/public lists)"
              ],
              audience: [
                long: "--audience",
                help: "Relay list to use for all posts: test or public (default: per source)"
              ]
            ]
          ],
          status: [
            name: "status",
            about: "Show status overview of all posts"
          ],
          mcp: [
            name: "mcp",
            about: "Run the MCP server on stdio for AI clients"
          ],
          upload: [
            name: "upload",
            about: "Upload an image to a Blossom server",
            args: [
              file: [
                help: "Local file path or URL to upload",
                required: true
              ]
            ],
            options: [
              nsec: [
                long: "--nsec",
                help: "Nostr private key (nsec or hex format)"
              ],
              server: [
                short: "-s",
                long: "--server",
                help: "Blossom server URL (uses NOSTR_UPLOAD_ENDPOINT if not specified)"
              ],
              alt: [
                short: "-a",
                long: "--alt",
                help: "Alt text for the image"
              ]
            ]
          ],
          servers: [
            name: "servers",
            about: "List available Blossom servers"
          ],
          bunker: [
            name: "bunker",
            about: "NIP-46 Nostr Connect (Bunker) operations",
            subcommands: [
              generate: [
                name: "generate",
                about: "Generate a bunker connection URL",
                options: [
                  relay: [
                    short: "-r",
                    long: "--relay",
                    help: "Relay URL for bunker communication",
                    default: "wss://relay.nsec.app"
                  ]
                ]
              ],
              test: [
                name: "test",
                about: "Test a bunker connection",
                options: [
                  url: [
                    short: "-u",
                    long: "--url",
                    help: "Bunker URL to test",
                    required: true
                  ]
                ]
              ],
              info: [
                name: "info",
                about: "Show information about bunker support"
              ]
            ]
          ],
          scheduler: [
            name: "scheduler",
            about: "Manage the automatic task scheduler",
            subcommands: [
              start: [
                name: "start",
                about: "Start the scheduler daemon",
                flags: [
                  upload_images: [
                    short: "-u",
                    long: "--upload-images",
                    help: "Upload images to a Blossom server"
                  ]
                ],
                options: [
                  nsec: [
                    long: "--nsec",
                    help: "Nostr private key for export"
                  ],
                  relays: [
                    short: "-r",
                    long: "--relays",
                    help: "Comma-separated relay URLs (overrides test/public lists)"
                  ],
                  audience: [
                    long: "--audience",
                    help: "Relay list to use for all posts: test or public (default: per source)"
                  ]
                ]
              ],
              status: [
                name: "status",
                about: "Show scheduler status"
              ],
              run: [
                name: "run",
                about: "Run a specific task manually",
                args: [
                  task: [
                    help: "Task to run (import, process, export, cleanup)",
                    required: true
                  ]
                ]
              ]
            ]
          ],
          web: [
            name: "web",
            about: "Manage the web admin interface",
            subcommands: [
              start: [
                name: "start",
                about: "Start the web server",
                options: [
                  port: [
                    short: "-p",
                    long: "--port",
                    help: "Port to listen on (default: PORT, WEB_PORT, or 4000)",
                    parser: :integer
                  ]
                ]
              ],
              stop: [
                name: "stop",
                about: "Stop the web server"
              ],
              status: [
                name: "status",
                about: "Show web server status"
              ]
            ]
          ]
        ]
      )

    case Optimus.parse!(optimus, args) do
      {[:source, :add], parsed} ->
        Commands.Source.add(Map.merge(parsed.options, parsed.flags))

      {[:source, :list], _parsed} ->
        Commands.Source.list()

      {[:source, :enable], parsed} ->
        Commands.Source.enable(parsed.args.id)

      {[:source, :disable], parsed} ->
        Commands.Source.disable(parsed.args.id)

      {[:source, :delete], parsed} ->
        Commands.Source.delete(parsed.args.id)

      {[:source, :duplicate], parsed} ->
        Commands.Source.duplicate(parsed.args.id, parsed.options)

      {[:import], parsed} ->
        Commands.Import.run(parsed.options, parsed.flags)

      {[:process], parsed} ->
        Commands.Process.run(parsed.options)

      {[:export], parsed} ->
        Commands.Export.run(Map.merge(parsed.options, parsed.flags))

      {[:status], _parsed} ->
        Commands.Status.run()

      {[:mcp], _parsed} ->
        Commands.MCP.run()

      {[:upload], parsed} ->
        options = Map.merge(parsed.options, %{file: parsed.args.file})
        Commands.Upload.run(options)

      {[:servers], _parsed} ->
        Commands.Upload.list_servers()

      {[:bunker, :generate], parsed} ->
        Commands.Bunker.generate(parsed.options)

      {[:bunker, :test], parsed} ->
        Commands.Bunker.test(parsed.options)

      {[:bunker, :info], _parsed} ->
        Commands.Bunker.info()

      {[:scheduler, :start], parsed} ->
        options = Map.merge(parsed.options, parsed.flags)
        Commands.Scheduler.start(options)

      {[:scheduler, :status], _parsed} ->
        Commands.Scheduler.status()

      {[:scheduler, :run], parsed} ->
        Commands.Scheduler.run_task(parsed.args.task)

      {[:web, :start], parsed} ->
        Commands.Web.start(parsed.options)

      {[:web, :stop], _parsed} ->
        Commands.Web.stop()

      {[:web, :status], _parsed} ->
        Commands.Web.status()

      _ ->
        Optimus.parse!(optimus, ["--help"])
    end
  end
end
