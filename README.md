# RSS2Nostr

Import RSS/Atom feeds and publish them as Nostr long-form content (NIP-23).

## Features

- **RSS/Atom Import**: Fetch articles from any RSS or Atom feed
- **HTML to Markdown**: Automatic conversion of HTML content to Markdown
- **NIP-23 Publishing**: Publish articles as Nostr long-form content (kind 30023)
- **NIP-96 Image Upload**: Upload images to NIP-96 compatible servers (nostr.build, nostrcheck.me)
- **NIP-46 Nostr Connect**: Remote signing support via bunker protocol
- **Scheduler**: Automatic import, processing, and publishing on schedule
- **Web Interface**: Admin dashboard for managing sources, posts, and scheduler
- **CLI**: Full command-line interface for all operations

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

2. Install dependencies:
```bash
mix deps.get
npm install --prefix priv
```

3. Configure the database in `config/dev.exs`:
```elixir
config :rss2nostr, Rss2Nostr.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "rss2nostr_dev"
```

4. Create and migrate the database:
```bash
mix ecto.setup
```

5. Build the CLI (optional):
```bash
mix escript.build
```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `NOSTR_NSEC` | Nostr private key (nsec or hex format) | For publishing |
| `DATABASE_URL` | PostgreSQL connection URL | For production |

### Config File

Configure default relays and scheduler intervals in `config/config.exs`:

```elixir
config :rss2nostr, Rss2Nostr.Scheduler,
  intervals: %{
    import: :timer.minutes(15),
    process: :timer.minutes(5),
    export: :timer.minutes(10)
  },
  default_relays: [
    "wss://relay.damus.io",
    "wss://nos.lol",
    "wss://relay.nostr.band"
  ]
```

## Usage

### CLI Commands

#### Source Management

```bash
# Add a new RSS/Atom source
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
```

#### Image Upload (NIP-96)

```bash
# Upload a local image
./rss2nostr upload /path/to/image.jpg

# Upload from URL
./rss2nostr upload https://example.com/image.jpg

# List available NIP-96 servers
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
# Start the web server
./rss2nostr web start

# Start on a custom port
./rss2nostr web start --port 8080

# Check web server status
./rss2nostr web status
```

Then open http://localhost:4000 in your browser.

### Web Interface

The web interface provides:

- **Dashboard**: Overview of sources, posts, and system status
- **Sources**: Add, edit, enable/disable, and delete RSS/Atom sources
- **Posts**: View imported posts, filter by status, process and publish
- **Scheduler**: Start/stop scheduler, run tasks manually
- **Settings**: View configuration and Nostr key status

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
    ["t", "nostr"]
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
│   │   ├── nip96.ex        # Image upload
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
- **NIP-19**: Bech32-encoded entities (npub, nsec, naddr, nevent, nprofile)
- **NIP-23**: Long-form Content
- **NIP-46**: Nostr Connect (Bunker)
- **NIP-96**: HTTP File Storage Integration
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
