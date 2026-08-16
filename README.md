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
| `MCP_TOKEN` | Bearer token for the HTTP MCP endpoint at `/mcp` | For remote MCP clients |
| `SECRET_KEY_BASE` | Signs the admin session cookie. Generate with `openssl rand -base64 48` | Recommended |
| `NOSTR_NSEC` | Nostr private key (nsec or hex format) | For publishing |
| `NOSTR_RELAYS_DRAFT` | Comma-separated relays for NIP-37 drafts (Pareto client). Falls back to the test list if unset | No |
| `NOSTR_RELAYS_TEST` | Comma-separated relays for article sources that are not public | No |
| `NOSTR_RELAYS_PUBLIC` | Comma-separated relays for public article sources | No |
| `NOSTR_RELAYS` | Alias for `NOSTR_RELAYS_TEST` if that variable is unset | No |
| `NOSTR_RELAY_AUDIENCE` | Default audience when a source is missing: `test` or `public` | No |
| `NOSTR_UPLOAD_ENDPOINT` | Blossom server base URL (BUD-02 `PUT /upload`) | For image upload |
| `DATABASE_URL` | PostgreSQL connection URL | For production |

### Config File

Configure scheduler intervals in `config/config.exs` and the three relay lists under `:nostr`:

```elixir
config :rss2nostr, Rss2Nostr.Scheduler,
  intervals: %{
    import: :timer.minutes(15),
    process: :timer.minutes(5),
    export: :timer.minutes(10),
    cleanup: :timer.hours(24)
  }

config :rss2nostr, :nostr,
  relays: %{
    draft: ["wss://client.example"],
    test: ["wss://nos.lol", "wss://relay.damus.io"],
    public: ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.nostr.band"]
  }
```

Draft sources always publish to the **draft** list (or **test** if that list is empty). Article sources publish to the **test** list unless they are marked public (`source add --public`, or the checkbox in the web UI). `--relays` on export still overrides all lists.

## Usage

### CLI Commands

#### Source Management

```bash
# Add a new RSS/Atom source (publishes to test relays)
./rss2nostr source add --name "Bitcoin Magazine" --url "https://bitcoinmagazine.com/feed"

# Add a source that publishes to public relays
./rss2nostr source add --name "Bitcoin Magazine" --url "https://bitcoinmagazine.com/feed" --public

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

stdio (Cursor, Claude Desktop, and similar):

```bash
mix rss2nostr.mcp
# or, after `mix escript.build`:
./rss2nostr mcp
```

Copy `.cursor/mcp.json.example` to `.cursor/mcp.json` (that file is gitignored). Cursor can omit `cwd` when the project is already the workspace.

When the web server is running, the same tools are also at `http://localhost:4000/mcp`. Loopback clients need no token. Set `MCP_TOKEN` and send `Authorization: Bearer …` for anything else.

Tools cover sources (discover, add, update, import, delete), articles (list, process, publish), the scheduler, and status.

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
