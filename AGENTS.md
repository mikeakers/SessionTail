# AGENTS.md — SessionTail

## Project Overview

SessionTail is a Swift 6.2 CLI tool that tails OpenClaw session JSONL logs with
formatted, color-coded terminal output. It reads structured events (messages,
tool calls, thinking blocks, model changes) and renders them as a readable
conversation transcript. Built with Swift Package Manager and Swift Argument Parser.

---

## Build / Run / Test Commands

| Action                     | Command                                                              |
| -------------------------- | -------------------------------------------------------------------- |
| Build (debug)              | `swift build`                                                        |
| Build (release)            | `swift build -c release`                                             |
| Run (auto-discover)        | `swift run SessionTail`                                              |
| Run (specific file)        | `swift run SessionTail path/to/session.jsonl`                        |
| Run (follow mode)          | `swift run SessionTail -f`                                           |
| Clean                      | `swift package clean`                                                |
| Resolve dependencies       | `swift package resolve`                                              |
| Run all tests              | `swift test`                                                         |
| Run a single test suite    | `swift test --filter "SessionTailTests.SessionEventDecodingTests"`   |
| Run a single test          | `swift test --filter "SessionTailTests.EventRendererTests/rendersUserMessage"` |
| Run tests matching a regex | `swift test --filter /ToolResult/`                                   |

When adding a dependency, add it to `Package.swift` then run `swift package resolve`.

---

## Project Layout

```
Package.swift                          # SPM manifest (swift-tools-version: 6.2)
Sources/
  SessionTail/
    SessionTail.swift                  # @main entry point (AsyncParsableCommand)
    SessionReader.swift                # Async JSONL line reader with follow/tail support
    SessionDiscovery.swift             # Discovers current session from sessions.json
    Models/
      SessionEvent.swift               # JSONL event types and decoder
      SessionIndex.swift               # sessions.json parser
    Rendering/
      ANSIColors.swift                 # ANSI escape code helpers
      EventRenderer.swift              # Formats events as colored terminal output
Tests/
  SessionTailTests/
    SessionTailTests.swift             # 24 tests across 3 suites
```

- One primary type per file. Name the file after the type it contains.
- Group related files into subdirectories (`Models/`, `Rendering/`).
- Never put source files directly in `Sources/` — they must be inside a target directory.

---

## Dependencies

| Package | Version | Used For |
|---|---|---|
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.5.0+ | CLI argument/flag parsing |

Keep dependencies minimal. Evaluate whether Foundation covers the need before adding packages.

---

## Naming Conventions

| Element                   | Convention       | Example from codebase          |
| ------------------------- | ---------------- | ------------------------------ |
| Types (struct/class/enum) | PascalCase       | `SessionReader`, `ContentBlock`|
| Protocols                 | PascalCase       | `Sendable`                     |
| Functions / methods       | lowerCamelCase   | `resolveCurrentSession()`      |
| Variables / properties    | lowerCamelCase   | `showThinking`, `filePath`     |
| Enum cases                | lowerCamelCase   | `.toolResult`, `.modelChange`  |
| File names                | PascalCase.swift | `EventRenderer.swift`          |
| Directories               | PascalCase       | `Models/`, `Rendering/`        |

- Use descriptive names. Avoid abbreviations except widely-known ones (`URL`, `ID`).
- Boolean properties should read as assertions: `showThinking`, `isError`, `follow`.

---

## Imports

- Prefer selective imports when only a few symbols are needed:
  `import struct Foundation.URL` over `import Foundation`.
- Use full `import Foundation` when many symbols are needed (e.g., `SessionEvent.swift`).
- Files that only use types from the same module need no imports (e.g., `EventRenderer.swift`).
- Group imports: Apple frameworks first, then third-party (`ArgumentParser`).

---

## Error Handling

- Custom error enums conforming to `Error` and `CustomStringConvertible`.
- Use Swift 6.2 typed throws (`throws(SomeError)`) where the error set is closed:
  ```swift
  func resolveCurrentSession() throws(SessionDiscoveryError) -> ResolvedSession
  ```
- Never use `try!` or force-unwrap in production paths.
- Prefer `guard let` for early exits. Propagate errors to callers.
- Malformed JSONL lines are skipped with `try?` — never crash on bad input.

---

## Concurrency

- Swift 6.2 strict concurrency is enabled. All types must be data-race safe.
- All model types are structs (automatically `Sendable`).
- `@unchecked Sendable` requires a comment explaining why (see `AnyCodable`).
- Use `AsyncStream` for streaming data (see `SessionReader.lines(follow:)`).
- The entry point is `AsyncParsableCommand` — `run()` is `async throws`.

---

## Formatting

- **Indentation:** 4 spaces (no tabs).
- **Line length:** aim for 120 characters max.
- **Braces:** opening brace on the same line.
- **Trailing commas:** include in multi-line collections and parameter lists.
- **Access control:** default to `internal` or `private`. No `public` except protocol conformances.
- Use `// MARK: -` to organize sections within a file.

---

## Testing

- **Framework:** Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`).
- **Location:** `Tests/SessionTailTests/`
- **Current suites:** `SessionEvent Decoding` (12 tests), `EventRenderer` (10 tests), `SessionIndex` (2 tests)
- Name test functions descriptively: `@Test func decodesAssistantMessageWithToolCall()`.
- Test one behavior per test function.

```swift
import Foundation
import Testing
@testable import SessionTail

@Suite("SessionEvent Decoding")
struct SessionEventDecodingTests {
    @Test func decodesSessionHeader() throws {
        let line = #"{"type":"session","version":3,"id":"abc","timestamp":"2026-01-01T00:00:00Z"}"#
        let event = try SessionEventDecoder.decode(line: line)
        guard case .session(let header) = event else {
            Issue.record("Expected .session"); return
        }
        #expect(header.id == "abc")
    }
}
```

---

## JSONL Event Types

The session files contain one JSON object per line. Each has a `type` field:

| Type                     | Description                          | Key fields                                |
| ------------------------ | ------------------------------------ | ----------------------------------------- |
| `session`                | Session header (first line)          | `id`, `version`, `timestamp`, `cwd`       |
| `model_change`           | Model switch                         | `provider`, `modelId`                     |
| `thinking_level_change`  | Thinking level change                | `thinkingLevel`                           |
| `custom`                 | Internal events (cache-ttl, etc.)    | `customType`                              |
| `message`                | User, assistant, or tool messages    | `message.role`, `message.content[]`       |

Message content blocks have sub-types: `text`, `thinking`, `toolCall`.
Tool results arrive as messages with `role: "toolResult"`.
