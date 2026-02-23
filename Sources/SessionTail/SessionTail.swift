import ArgumentParser
import Foundation

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

    // MARK: - Run

    func run() async throws {
        let filePath: URL

        if let sessionFile {
            // User gave us an explicit file path
            let expanded = (sessionFile as NSString).expandingTildeInPath
            filePath = URL(fileURLWithPath: expanded)
            guard FileManager.default.fileExists(atPath: filePath.path) else {
                throw SessionTailError.fileNotFound(filePath.path)
            }
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

    var description: String {
        switch self {
        case .fileNotFound(let path):
            "Session file not found: \(path)"
        case .discoveryFailed(let reason):
            "Failed to discover session: \(reason)"
        }
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
