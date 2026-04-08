# swift-field-theory-cli

A pure Swift port of [fieldtheory-cli](https://github.com/afar1/fieldtheory-cli) — sync and store locally all of your X/Twitter bookmarks. Search, classify, and make them available to Claude Code, Codex, or any agent with shell access.

macOS only. One dependency ([swift-argument-parser](https://github.com/apple/swift-argument-parser)).

## Install

```bash
git clone https://github.com/juliensagot/swift-fieldtheory-cli
cd swift-fieldtheory-cli
swift build -c release
# Optionally copy to PATH:
cp .build/release/ft /usr/local/bin/ft
```

Requires Swift 6.1+ and macOS 15+.

## Quick start

```bash
# 1. Sync your bookmarks (needs Safari logged into X)
ft sync

# 2. Search them
ft search "distributed systems"

# 3. Download media
ft fetch-media

# 4. Explore
ft categories
ft stats
```

On first run, `ft sync` extracts your X session from Safari and downloads your bookmarks into `~/.ft-bookmarks/`. Terminal needs **Full Disk Access** (System Settings > Privacy & Security) to read Safari cookies.

## Commands

| Command | Description |
|---------|-------------|
| `ft sync` | Download and sync all bookmarks |
| `ft sync --rebuild` | Full re-sync (not incremental) |
| `ft sync --classify` | Sync then classify new bookmarks |
| `ft search <query>` | Full-text search with BM25 ranking |
| `ft list` | Filter by author, date, category, domain |
| `ft show <id>` | Show one bookmark in detail |
| `ft stats` | Top authors, languages, date range |
| `ft classify` | Classify by category using regex patterns |
| `ft categories` | Show category distribution |
| `ft domains` | Subject domain distribution |
| `ft fetch-media` | Download media (images, videos) to disk |
| `ft index` | Rebuild the FTS search index |
| `ft status` | Show sync status and data location |
| `ft path` | Print data directory path |

## Notable differences from the Node.js version

| | Node.js | Swift |
|---|---------|-------|
| **Runtime** | Node.js 20+ | Native binary (Swift 6.1, macOS 15+) |
| **Browser** | Chrome (encrypted cookies via Keychain) | Safari (binary cookies, unencrypted) |
| **SQLite** | WASM (`sql.js-fts5`) | System `libsqlite3` with FTS5 |
| **Source of truth** | JSONL cache → SQLite as derived index | SQLite directly |
| **Media storage** | Files on disk + JSON manifest | Files on disk + `media_files` table in SQLite |
| **Media download** | Sequential | Concurrent (6 parallel downloads) |
| **Classification** | Regex + optional LLM (`claude -p` / `codex exec`) | Regex only (no LLM dependency) |
| **Dependencies** | `commander`, `sql.js`, `sql.js-fts5`, `zod`, `dotenv` | `swift-argument-parser` only |
| **OAuth API sync** | Supported (`ft auth` + `ft sync --api`) | Not yet implemented |
| **Viz dashboard** | ANSI terminal dashboard (`ft viz`) | Not yet implemented |
| **Platform** | macOS, Linux, Windows (via OAuth) | macOS only |

## Data

All data is stored locally at `~/.ft-bookmarks/`:

```
~/.ft-bookmarks/
  bookmarks.db            # SQLite FTS5 database (source of truth)
  media/                  # Downloaded images and videos
    {tweetId}-{hash}.jpg
    {tweetId}-{hash}.mp4
```

Override the location with `FT_DATA_DIR`:

```bash
export FT_DATA_DIR=/path/to/custom/dir
```

## Security

**Your data stays local.** No telemetry, no analytics. The CLI only makes network requests to X's API during sync and media download.

**Safari session sync** reads cookies from Safari's local cookie store, uses them for the sync request, and discards them. Cookies are never stored separately.

## License

MIT
