import ArgumentParser
import Foundation
import struct Foundation.Date

@main
struct SessionTail: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "sessiontail",
        abstract: "Tail an OpenClaw session JSONL log with formatted, color-coded output.",
        discussion: """
            By default, discovers the most recently active session from \
            ~/.openclaw/agents/main/sessions/sessions.json and renders it \
            as a formatted conversation. Pass a file path to tail a specific session.
            """
    )

    // MARK: - Arguments

    @Argument(help: "Path to a specific .jsonl session file.")
    var sessionFile: String?

    @Option(name: .long, help: "Base sessions directory (default: ~/.openclaw/agents/main/sessions).")
    var path: String?

    @Flag(name: .shortAndLong, help: "Follow mode — watch for new lines (like tail -f).")
    var follow: Bool = false

    @Flag(name: .long, help: "Hide thinking blocks.")
    var noThinking: Bool = false

    @Flag(name: .long, help: "Don't truncate long tool outputs.")
    var full: Bool = false

    @Option(name: .shortAndLong, help: "Show only the last N events (0 = show all).")
    var last: Int = 0

    @Option(name: .long, help: "Session key or UUID to tail (see --list for keys).")
    var id: String?

    @Flag(name: .long, help: "List all sessions and exit.")
    var list: Bool = false

    @Flag(name: .long, help: "Include deleted/missing sessions in --list output.")
    var all: Bool = false

    // MARK: - Run

    func run() async throws {
        // Mutual exclusion: positional path and --id both identify a session
        if sessionFile != nil && id != nil {
            throw SessionTailError.conflictingOptions(
                "Cannot specify both a session file path and --id — use one or the other."
            )
        }

        // --list: print all sessions and exit
        if list {
            let discovery = SessionDiscovery(path: path)
            let listings: [SessionListing]
            do {
                listings = try discovery.allSessions(includeDeleted: all)
            } catch {
                throw SessionTailError.discoveryFailed(String(describing: error))
            }
            printSessionList(listings)
            return
        }

        let filePath: URL

        if let sessionFile {
            // User gave us an explicit file path
            let expanded = (sessionFile as NSString).expandingTildeInPath
            filePath = URL(fileURLWithPath: expanded)
            guard FileManager.default.fileExists(atPath: filePath.path) else {
                throw SessionTailError.fileNotFound(filePath.path)
            }
        } else if let id {
            // --id: look up session by key or UUID
            let discovery = SessionDiscovery(path: path)
            let resolved: ResolvedSession
            do {
                resolved = try discovery.resolveSession(byId: id)
            } catch {
                throw SessionTailError.discoveryFailed(String(describing: error))
            }

            filePath = resolved.filePath
            printToStderr(styled("  Tailing session: \(resolved.sessionId)", .dim))
            if let model = resolved.model, let provider = resolved.provider {
                printToStderr(styled("  Model: \(provider)/\(model)", .dim))
            }
            printToStderr(styled("  File: \(resolved.filePath.path)", .dim))
            printToStderr("")
        } else {
            // Discover the current session
            let discovery = SessionDiscovery(path: path)
            let resolved: ResolvedSession
            do {
                resolved = try discovery.resolveCurrentSession()
            } catch {
                throw SessionTailError.discoveryFailed(String(describing: error))
            }

            filePath = resolved.filePath
            printToStderr(styled(
                "  Tailing session: \(resolved.sessionId)",
                .dim
            ))
            if let model = resolved.model, let provider = resolved.provider {
                printToStderr(styled("  Model: \(provider)/\(model)", .dim))
            }
            printToStderr(styled("  File: \(resolved.filePath.path)", .dim))
            printToStderr("")
        }

        let renderer = EventRenderer(
            showThinking: !noThinking,
            fullOutput: full
        )
        let reader = SessionReader(filePath: filePath)

        if last > 0 {
            // Collect all events, then render only the tail
            var events: [SessionEvent] = []
            for await line in reader.lines(follow: false) {
                if let event = try? SessionEventDecoder.decode(line: line) {
                    events.append(event)
                }
            }

            let startIndex = max(0, events.count - last)
            for event in events[startIndex...] {
                if let output = renderer.render(event) {
                    print(output)
                }
            }

            // If follow mode, continue tailing after showing the tail
            if follow {
                let followReader = SessionReader(filePath: filePath)
                var skipCount = events.count
                for await line in followReader.lines(follow: true) {
                    if skipCount > 0 {
                        skipCount -= 1
                        continue
                    }
                    if let event = try? SessionEventDecoder.decode(line: line) {
                        if let output = renderer.render(event) {
                            print(output)
                        }
                    }
                }
            }
        } else {
            // Stream all events
            for await line in reader.lines(follow: follow) {
                if let event = try? SessionEventDecoder.decode(line: line) {
                    if let output = renderer.render(event) {
                        print(output)
                    }
                }
            }
        }
    }
}


// MARK: - Errors

enum SessionTailError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case discoveryFailed(String)
    case conflictingOptions(String)

    var description: String {
        switch self {
        case .fileNotFound(let path):
            "Session file not found: \(path)"
        case .discoveryFailed(let reason):
            "Failed to discover session: \(reason)"
        case .conflictingOptions(let message):
            message
        }
    }
}


// MARK: - Session List Formatting

private func printSessionList(_ listings: [SessionListing]) {
    if listings.isEmpty {
        print(styled("No sessions found.", .dim))
        return
    }

    // Compute column widths based on content
    let keyWidth = listings.map(\.key.count).max() ?? 0
    let modelWidth = listings.map { listing -> Int in
        guard listing.fileExists, let p = listing.entry.modelProvider, let m = listing.entry.model else {
            return "(deleted)".count
        }
        return "\(p)/\(m)".count
    }.max() ?? 0

    for listing in listings {
        let marker = listing.isCurrent ? "* " : "  "
        let key = listing.key.padding(toLength: keyWidth, withPad: " ", startingAt: 0)

        let modelField: String
        if listing.fileExists, let provider = listing.entry.modelProvider, let model = listing.entry.model {
            modelField = "\(provider)/\(model)"
        } else {
            modelField = "(deleted)"
        }
        let modelPadded = modelField.padding(toLength: modelWidth, withPad: " ", startingAt: 0)

        let age = relativeTime(fromUnixMs: listing.entry.updatedAt)
        let shortId = String(listing.entry.sessionId.prefix(8))

        let line = "\(marker)\(key)   \(modelPadded)   \(age.padding(toLength: 14, withPad: " ", startingAt: 0))   \(shortId)"

        if listing.isCurrent {
            print(styled(line, .bold, .brightGreen))
        } else if !listing.fileExists {
            print(styled(line, .dim))
        } else {
            print(line)
        }
    }
}

/// Returns a human-readable relative time string for a Unix millisecond timestamp.
func relativeTime(fromUnixMs ms: Int) -> String {
    let seconds = Int(Date().timeIntervalSince1970) - ms / 1000
    switch seconds {
    case ..<60:
        return "just now"
    case 60..<3_600:
        let mins = seconds / 60
        return "\(mins) minute\(mins == 1 ? "" : "s") ago"
    case 3_600..<86_400:
        let hours = seconds / 3_600
        return "\(hours) hour\(hours == 1 ? "" : "s") ago"
    case 86_400..<604_800:
        let days = seconds / 86_400
        return "\(days) day\(days == 1 ? "" : "s") ago"
    default:
        let weeks = seconds / 604_800
        return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
    }
}


// MARK: - Helpers

/// Print to stderr so it doesn't mix with the actual session output.
private func printToStderr(_ message: String) {
    let stderr = FileHandle.standardError
    stderr.write(Data((message + "\n").utf8))
}


extension FileHandle: @retroactive TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
    }
}
