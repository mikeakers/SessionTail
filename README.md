# SessionTail

A CLI tool that tails [OpenClaw](https://openclaw.ai) session logs with
formatted, color-coded terminal output. Think `tail -f`, but for AI
conversations.

SessionTail reads the JSONL session log files that OpenClaw produces and renders
them as a readable conversation transcript — with color-coded roles, tool
call/result summaries, thinking blocks, token usage, and more.

## Installation

Requires Swift 6.2+ and macOS 13+.

```bash
git clone https://github.com/your-user/sessiontail.git
cd sessiontail
swift build -c release
# Binary is at .build/release/SessionTail
```

To install to your PATH:

```bash
cp .build/release/SessionTail /usr/local/bin/sessiontail
```

## Usage

```
USAGE: sessiontail [<session-file>] [--path <path>] [--follow] [--no-thinking] [--full] [--last <n>]
                   [--id <id>] [--list] [--all]
```

### Auto-discover the current session

```bash
sessiontail
```

Reads `~/.openclaw/agents/main/sessions/sessions.json`, finds the most recently
active session, and renders it.

### List all sessions

```bash
sessiontail --list
sessiontail --list --all    # include deleted/missing sessions
```

Prints a table of all known sessions, sorted by most recently updated. Each row
shows the session key, model (provider/model), relative age, and a short UUID.
The currently active session is highlighted with a `*` marker in green. Deleted
sessions appear dimmed.

### Tail a specific session by key or UUID

```bash
sessiontail --id agent:main:main
sessiontail --id 72e7beae-1234-5678-9abc-def012345678
sessiontail --id agent:main:main -f    # follow mode
```

Looks up a session by its key (e.g. `agent:main:main`) or full UUID. Key matches
take priority over UUID matches. Use `--list` to see available keys. Deleted
sessions (`.jsonl.deleted.*` files) can also be tailed this way.

### Tail a specific session file

```bash
sessiontail ~/.openclaw/agents/main/sessions/72e7beae-....jsonl
```

### Follow mode (live tail)

```bash
sessiontail -f
sessiontail -f --no-thinking
```

Watches for new lines appended to the session file, like `tail -f`.

### Show only recent events

```bash
sessiontail --last 20
sessiontail --last 10 -f    # show last 10, then follow
```

### Options

| Flag | Short | Description |
|---|---|---|
| `--follow` | `-f` | Watch for new lines (live tail) |
| `--no-thinking` | | Hide model thinking blocks |
| `--full` | | Don't truncate long tool outputs (default: 500 chars) |
| `--last <n>` | `-l` | Show only the last N events |
| `--path <dir>` | | Override the sessions directory |
| `--id <id>` | | Tail a session by key or UUID (see `--list` for keys) |
| `--list` | | List all sessions and exit |
| `--all` | | Include deleted/missing sessions in `--list` output |

## Output Format

SessionTail renders each JSONL event type with distinct formatting:

- **User messages** — green role label, with metadata wrappers stripped
- **Assistant messages** — blue role label, model name, token usage
- **Thinking blocks** — gray text with 💭 prefix (toggle with `--no-thinking`)
- **Tool calls** — yellow, showing tool name and arguments
- **Tool results** — cyan, showing output, exit codes, and duration
- **API errors** — compact red one-liner for empty error responses
- **System messages** — magenta role label with dimmed content
- **Session headers** — magenta banner with session ID, timestamp, working directory
- **Model changes** — subtle gray info line
- **Thinking level changes** — gray info line showing the new thinking level

## How It Works

OpenClaw writes session logs as JSONL files (one JSON object per line) in
`~/.openclaw/agents/main/sessions/`. Each line has a `type` field — `session`,
`model_change`, `thinking_level_change`, `custom`, or `message`.

SessionTail:

1. Parses `sessions.json` to find the active session (or accepts a direct file path, or looks up by `--id`)
2. Reads the JSONL file line-by-line using async streaming
3. Decodes each line into a typed `SessionEvent` discriminated union
4. Renders events through `EventRenderer` with ANSI color codes
5. In follow mode, polls for new lines at 250ms intervals

Session resolution (`--id`) tries an exact key match first, then falls back to
UUID matching. Deleted sessions are discovered via `.jsonl.deleted.<timestamp>`
files on disk, so you can tail sessions that have been removed from the active
index.

## Development

```bash
swift build          # build
swift test           # run all 45 tests
swift run SessionTail --help
```

The project uses the [Swift Testing](https://developer.apple.com/documentation/testing)
framework with 6 test suites covering JSONL decoding, terminal rendering, session
listing, session resolution, relative time formatting, and session index parsing.

## Project Structure

```
Sources/SessionTail/
  SessionTail.swift          # CLI entry point (ArgumentParser)
  SessionReader.swift        # Async JSONL reader with follow support
  SessionDiscovery.swift     # Session auto-discovery from sessions.json
  Models/
    SessionEvent.swift       # Event types and JSONL decoder
    SessionIndex.swift       # sessions.json parser
  Rendering/
    ANSIColors.swift         # ANSI terminal color helpers
    EventRenderer.swift      # Event-to-text rendering
Tests/SessionTailTests/
  SessionTailTests.swift     # Unit tests
```

## License

MIT
