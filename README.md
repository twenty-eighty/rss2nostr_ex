# RSS2Nostr

Import RSS/Atom feeds and publish them as Nostr long-form content (NIP-23).

## Features

- **RSS/Atom Import**: Fetch articles from any RSS or Atom feed
- **HTML to Markdown**: Automatic conversion of HTML content to Markdown
- **NIP-23 Publishing**: Publish articles as Nostr long-form content (kind 30023)
- **Blossom Image Upload**: Upload images to Blossom (BUD-02) servers
- **NIP-46 Nostr Connect**: Remote signing support via bunker protocol
- **Scheduler**: Automatic import, processing, and publishing on schedule
- **Web Interface**: Admin dashboard for managing sources, posts, and scheduler
- **CLI**: Full command-line interface for all operations
- **MCP**: AI clients can manage sources, articles, and the scheduler

## Requirements

- Elixir 1.20+ (Erlang/OTP 27+)
- PostgreSQL
- Node.js 18+ (for Nostr signing)

For production deployment, use the included `Dockerfile` (see [Docker deployment](#docker-deployment)).

## Docker deployment

The app ships as an Elixir release in a multi-stage Docker image. Coolify (or any Docker host) can build from the repo `Dockerfile` and run the container with a linked PostgreSQL database.

### Coolify setup

1. Create a new application from this repository (build pack: **Dockerfile**).
2. Add a PostgreSQL database and set `DATABASE_URL` on the app (Coolify usually provides this when the DB is linked).
3. Set required environment variables (see below).
4. Expose port **4000** (or set `PORT` to match Coolify's assigned port).
5. Optional health check: `GET /health` (returns `200 ok`).

### Required environment variables (production)

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL URL (`ecto://USER:PASS@HOST/DATABASE`) |
| `SECRET_KEY_BASE` | Admin session signing key (`openssl rand -base64 48`) |
| `ADMIN_NOSTR_PUBKEYS` | Comma-separated npub/hex keys for admin login |
| `NOSTR_NSEC` | Nostr private key for publishing |

Also set `MCP_TOKEN` whenever `/mcp` is reachable through a reverse proxy or the public internet (do not rely on loopback auth). Set relay variables as needed (`NOSTR_RELAYS_PUBLIC`, etc.). Set `SCHEDULER_AUTO_START=true` if the import/process/export timers should run as soon as the container starts.

On startup the container runs database migrations automatically. Set `SKIP_MIGRATIONS=true` to disable that.

### Local Docker test

```bash
docker compose up --build
```

Then open http://localhost:4000 (after setting `ADMIN_NOSTR_PUBKEYS` and other env vars in `docker-compose.yml`).

## Installation

1. Clone the repository:
```bash
git clone https://github.com/razue/rss2nostr.git
cd rss2nostr
```

2. Copy `.env.example` to `.env` and edit credentials if needed:
```bash
cp .env.example .env
```

3. Start the dev server (installs deps, migrates the database, serves the UI):
```bash
./bin/dev
```

Or step through setup yourself:
```bash
mix deps.get
npm install
mix ecto.setup
mix rss2nostr.server
```

Build the CLI (optional):
```bash
mix escript.build
```

## Configuration

Copy `.env.example` to `.env`. Values are loaded at runtime (OS environment variables override the file). There is no need to edit `config/dev.exs` for local credentials.

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | Dev database credentials | No (defaults in `config/dev.exs`) |
| `POSTGRES_HOST` / `POSTGRES_PORT` / `POSTGRES_DB` | Dev database connection | No |
| `PORT` or `WEB_PORT` | Web server port (default 4000) | No |
| `ADMIN_NOSTR_PUBKEYS` | Comma-separated npub or hex keys allowed to log into the admin UI via [NIP-07](https://nips.nostr.com/7) | For the web UI |
| `MCP_TOKEN` | Bearer token for the HTTP MCP endpoint at `/mcp` | Required for remote / proxied MCP |
| `MCP_ALLOW_LOOPBACK` | Allow unauthenticated `/mcp` from loopback when token unset | Local dev only |
| `SECRET_KEY_BASE` | Signs the admin session cookie and encrypts source nsecs. Generate with `openssl rand -base64 48` | Recommended |
| `NOSTR_NSEC` | Nostr private key (nsec or hex format) | For publishing |
| `NOSTR_RELAYS_DRAFT` | Comma-separated relays for NIP-37 drafts (Pareto client). Falls back to the test list if unset | No |
| `NOSTR_RELAYS_TEST` | Comma-separated relays for article sources that are not public | No |
| `NOSTR_RELAYS_PUBLIC` | Comma-separated relays for public article sources; also the staging-DM fallback | No |
| `NOSTR_RELAYS_INBOX` | Extra relays always used when sending NIP-17 staging DMs (in addition to NIP-05 / public) | No |
| `NOSTR_RELAYS` | Alias for `NOSTR_RELAYS_TEST` if that variable is unset | No |
| `NOSTR_RELAY_AUDIENCE` | Default audience when a source is missing: `test` or `public` | No |
| `NOSTR_UPLOAD_ENDPOINT` | Blossom server base URL (BUD-02 `PUT /upload`) | For image upload |
| `SCHEDULER_AUTO_START` | `true`/`1`/`yes`/`on` starts import/process/export/cleanup timers with the server (default: off) | No |
| `DATABASE_URL` | PostgreSQL connection URL | For production |

### Config File

Configure scheduler intervals in `config/config.exs` and the relay lists under `:nostr`:

```elixir
config :rss2nostr, Rss2Nostr.Scheduler,
  intervals: %{
    import: :timer.minutes(15),
    process: :timer.minutes(5),
    export: :timer.minutes(10),
    cleanup: :timer.hours(1)
  }

config :rss2nostr, :nostr,
  relays: %{
    draft: ["wss://client.example"],
    test: ["wss://nos.lol", "wss://relay.damus.io"],
    public: ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.nostr.band"],
    inbox: []
  }
```

Draft sources always publish to the **draft** list (or **test** if that list is empty). Article and video sources always publish to the **public** list. `--relays` on export still overrides all lists. Staging DMs use the recipient’s NIP-05 relays (or **public** if none are advertised), plus **inbox**.

## Usage

### CLI Commands

#### Source Management

```bash
# Add a new RSS/Atom source (articles go to public relays)
./rss2nostr source add --name "Bitcoin Magazine" --url "https://bitcoinmagazine.com/feed"

# List all sources
./rss2nostr source list

# Enable/disable a source
./rss2nostr source enable 1
./rss2nostr source disable 1

# Delete a source
./rss2nostr source delete 1
```

#### Import & Processing

```bash
# Import articles from all active sources
./rss2nostr import

# Import from a specific source
./rss2nostr import --source 1

# Process imported articles (HTML to Markdown)
./rss2nostr process --limit 10
```

#### Publishing

```bash
# Export processed posts to Nostr
./rss2nostr export --nsec "nsec1..."

# Dry run (preview without publishing)
./rss2nostr export --dry-run

# Export with image upload
./rss2nostr export --upload-images

# Export to specific relays
./rss2nostr export --relays "wss://relay1.com,wss://relay2.com"

# Force the test or public list for every post in this run
./rss2nostr export --audience test
./rss2nostr export --audience public
```

#### Image Upload (Blossom)

```bash
# Upload a local image
./rss2nostr upload /path/to/image.jpg

# Upload from URL
./rss2nostr upload https://example.com/image.jpg

# List available Blossom servers
./rss2nostr servers
```

#### Scheduler

The HTTP server starts the scheduler process idle. Set `SCHEDULER_AUTO_START=true` to start the timers on boot, or use Start on `/scheduler`. The CLI command below always starts them.

```bash
# Start the scheduler daemon
./rss2nostr scheduler start

# Check scheduler status
./rss2nostr scheduler status

# Run a task manually
./rss2nostr scheduler run import
./rss2nostr scheduler run process
./rss2nostr scheduler run export
```

#### MCP (AI clients)

[MCP](https://modelcontextprotocol.io/) exposes the same operations as the admin UI and CLI so agents can discover feeds, tune composition, import articles, and run the scheduler.

**stdio** (Cursor, Claude Desktop, and similar):

```bash
mix rss2nostr.mcp
# or, after `mix escript.build`:
./rss2nostr mcp
```

Copy `.cursor/mcp.json.example` to `.cursor/mcp.json` (that file is gitignored). Cursor can omit `cwd` when the project is already the workspace.

**HTTP** (remote agents or when the web server is already running):

```
http://localhost:4000/mcp
```

Loopback clients need `MCP_ALLOW_LOOPBACK=true` **and** no `MCP_TOKEN` (local
dev only). Behind reverse proxies every client looks like `127.0.0.1`, so leave
loopback auth off and set `MCP_TOKEN`, then send `Authorization: Bearer <token>`.

Optional: `MCP_CORS_ORIGINS` (comma-separated) enables browser CORS for those
origins only. `MCP_ALLOWED_HOSTS` restricts the HTTP `Host` header.

##### Resources and prompts

| URI / name | Description |
|------------|-------------|
| `rss2nostr://status` | Source and post counts |
| `rss2nostr://sources` | All configured sources |
| `rss2nostr://settings` | Non-secret app settings |
| prompt `add_source` | Step-by-step feed discovery and source setup |
| prompt `triage_posts` | Review articles that need processing or publishing |

##### Tools

**Overview**

| Tool | Description |
|------|-------------|
| `get_status` | Dashboard-style counts and scheduler summary |
| `get_settings` | Relays, upload endpoint, scheduler intervals, and `compose` presets (body presets, languages, fetch/publish modes, default skip classes) |

**Sources**

| Tool | Description |
|------|-------------|
| `list_sources` | All sources |
| `get_source` | One source with flattened composition options |
| `discover_feeds` | Find RSS/Atom feeds on a site URL |
| `preview_feed` | Sample items from a feed URL without saving |
| `preview_compose` | Dry-run Markdown conversion and Nostr event shape for one item (works without a saved source) |
| `add_source` | Create a source (feed URL, language, `publish_as`, signing, composition, `start_guid`, staging hold, hashtags) |
| `update_source` | Change any of the above plus `active`, `public`, and `mode` (`setup` → `automated`) |
| `toggle_source` | Enable or disable imports |
| `duplicate_source` | Copy a source |
| `delete_source` | Delete a source and its articles |
| `import_source` | Fetch new items and process them |

`preview_compose` and `add_source` accept composition fields such as `fetch_source_from` (`content` or `fetch_from_url`), `body_selector`, `start_at`, `skip_classes`, `body_selector_auto`, `conversion_rules`, `fixed_hashtags`, `excluded_hashtags`, and `mirror_media` (for video). Draft modes need `pubkey`; article mode needs `signing_nsec` or `bunker_connection`.

**Articles**

| Tool | Description |
|------|-------------|
| `list_posts` | Filter by `status`, `source_id`, or search text |
| `get_post` | One article including Markdown |
| `process_post` | Convert HTML to Markdown and upload images |
| `upload_post_images` | Upload images for `pending_images` articles |
| `reprocess_post` | Reconvert one article from stored HTML |
| `reprocess_posts` | Reconvert multiple articles by id |
| `publish_post` | Publish one staging article (or republish) |
| `publish_source_posts` | Publish selected staging articles from a source |
| `update_post` | Edit title, summary, hashtags, language, or Markdown |
| `revise_post` | Reconvert a published article and move it back to staging |
| `delete_post` | Delete one article |

Post `status` values: `new`, `processing`, `staging`, `processed`, `pending_images`, `published`, `error`.

**Scheduler**

| Tool | Description |
|------|-------------|
| `scheduler_status` | Running state and last task runs |
| `start_scheduler` | Start import/process/export timers |
| `stop_scheduler` | Stop the scheduler |
| `run_scheduler_task` | Run `import`, `process`, `export`, or `cleanup` once |

The HTTP server starts the scheduler idle unless `SCHEDULER_AUTO_START=true` is set.

##### Typical agent workflow

1. `get_settings` — relays, Blossom endpoint, compose presets, languages.
2. `discover_feeds` on the site URL, then `preview_feed` on the best feed.
3. `preview_compose` on a sample item. Tune `fetch_source_from`, `body_selector`, `publish_as`, and `pubkey` until the Markdown and event look right.
4. `add_source` with the same fields plus `start_guid` from `preview_feed` if you want to limit the import window.
5. `update_source` with `mode: automated` once signing is configured.
6. `import_source`, then `list_posts`. Use `upload_post_images` or `reprocess_post` for failures; `publish_post` only when status is `processed` or staging rules allow it.

Use the built-in `add_source` prompt with a website URL for a shorter checklist an agent can follow.

#### NIP-46 Bunker (Remote Signing)

```bash
# Generate a bunker connection URL
./rss2nostr bunker generate

# Test a bunker connection
./rss2nostr bunker test --url "bunker://..."

# Export using bunker for signing
./rss2nostr export --bunker "bunker://..."
```

#### Web Interface

```bash
# One-command dev server (recommended)
./bin/dev

# Or via Mix, after deps and database are set up
mix rss2nostr.server
mix rss2nostr.server --port 8080

# CLI (after mix escript.build)
./rss2nostr web start
./rss2nostr web start --port 8080
./rss2nostr web status
```

Then open http://localhost:4000 in your browser (or the `PORT` from `.env`).

The admin UI requires a [NIP-07](https://nips.nostr.com/7) browser extension (Alby, nos2x, and similar). Only public keys listed in `ADMIN_NOSTR_PUBKEYS` can log in. The server never sees the private key: the extension signs a one-time challenge event.

```bash
# npub or 64-character hex, comma-separated for multiple admins
ADMIN_NOSTR_PUBKEYS=npub1...
SECRET_KEY_BASE=$(openssl rand -base64 48)
```

### Web Interface

The web interface provides:

- **Dashboard**: Overview of sources, posts, and system status
- **Sources**: Add, edit, enable/disable, and delete RSS/Atom sources
- **Posts**: View imported posts, filter by status, process and publish
- **Scheduler**: Start/stop scheduler, run tasks manually
- **Settings**: View configuration and Nostr key status
- **Login**: NIP-07 (`window.nostr`) only; allowlist from `ADMIN_NOSTR_PUBKEYS`

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/status` | GET | System status overview |
| `/api/sources` | GET | List all sources |
| `/api/posts` | GET | List posts (with filters) |

## Post Status Flow

```
new (0) → processing (1) → processed (2) → publishing (5) → published (6)
                ↓                                    ↓
            error (8)                           error (8)
```

## Nostr Event Format

Published articles use NIP-23 format (kind 30023):

```json
{
  "kind": 30023,
  "content": "# Article Title\n\nMarkdown content...",
  "tags": [
    ["d", "article-slug"],
    ["title", "Article Title"],
    ["summary", "Article summary..."],
    ["image", "https://nostr.build/..."],
    ["published_at", "1704067200"],
    ["t", "bitcoin"],
    ["t", "nostr"],
    ["L", "ISO-639-1"],
    ["l", "de", "ISO-639-1"],
    ["r", "https://example.com/article"]
  ]
}
```

## Development

### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/nostr/keys_test.exs

# Run with coverage
mix test --cover
```

### Test after refactoring

=== Full Pipeline Test with heise.de ===                                                                                      

1. Creating test source...                                                                                                    
✓ Source created: ID 1                                                                                                     

2. Importing articles (limit 3)...                                                                                            
✓ Imported: 3, Skipped: 0, Errors: 0                                                                                       

3. Processing new posts...                                                                                                    
✓ Processed: 3, Skipped: 0, Errors: 0                                                                                      

4. Processed posts:                                                                                                           
- Britische Marine testet autonomen Hubschrauber Proteus                                                                   
Status: processed                                                                                                        
- Neues XR-Headset Lynx-R2 setzt auf großes Sichtfeld...                                                                   
Status: processed                                                                                                        
- BOE: Produktionsprobleme bei iPhone-OLEDs...                                                                             
Status: processed                                                                                                        

5. Cleanup...                                                                                                                 
✓ Test data cleaned up                                                                                                     

=== All tests passed! ===                                                                                                     

Summary:                                                                                                                      
- 290 unit tests: All pass                                                                                                    
- heise.de integration test: Works correctly                                                                                  
- Feed fetch: 193KB Atom feed                                                                                               
- Parse: 152 items detected                                                                                                 
- Import: Articles saved to DB                                                                                              
- Process: HTML→Markdown conversion works                                                                                   
- Images: Extracted and stored                                                                                              

All refactoring changes are working correctly. 

### Code Structure

```
lib/
├── rss2nostr/
│   ├── application.ex      # Application supervisor
│   ├── repo.ex             # Ecto repository
│   ├── sources/            # Source context
│   ├── posts/              # Post context
│   ├── import/             # RSS/Atom import
│   ├── processing/         # HTML to Markdown
│   ├── nostr/              # Nostr protocol
│   │   ├── keys.ex         # Key management
│   │   ├── event.ex        # Event building
│   │   ├── relay.ex        # Relay communication
│   │   ├── nip19.ex        # Bech32 encoding
│   │   ├── nip46.ex        # Nostr Connect
│   │   ├── blossom.ex      # Blossom image upload
│   │   └── publisher.ex    # Event publishing
│   ├── scheduler/          # Task scheduler
│   └── web/                # Web interface
│       ├── router.ex       # Plug router
│       ├── server.ex       # Bandit server
│       ├── views/          # HTML views
│       └── api/            # JSON API handlers
└── rss2nostr_cli/
    ├── cli.ex              # CLI entry point
    └── commands/           # CLI commands
```

## Supported NIPs

- **NIP-01**: Basic protocol flow
- **NIP-04**: Encrypted Direct Messages (used for NIP-46)
- **NIP-07**: `window.nostr` browser extension login for the admin UI
- **NIP-19**: Bech32-encoded entities (npub, nsec, naddr, nevent, nprofile)
- **NIP-23**: Long-form Content
- **NIP-46**: Nostr Connect (Bunker)
- **Blossom** (BUD-02 / BUD-11): Blob storage (replaces NIP-96)
- **NIP-98**: HTTP Auth

## License

MIT License - see LICENSE file for details.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## Credits

Built with Elixir and the following libraries:
- [Ecto](https://hexdocs.pm/ecto/) - Database toolkit
- [Plug](https://hexdocs.pm/plug/) - Web server abstraction
- [Bandit](https://hexdocs.pm/bandit/) - HTTP server
- [K256](https://hexdocs.pm/k256/) - secp256k1 cryptography
- [nostr-tools](https://github.com/nbd-wtf/nostr-tools) - Nostr utilities (Node.js)
