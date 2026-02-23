import struct Foundation.URL
import class Foundation.FileManager
import class Foundation.NSString

/// Discovers session files from the OpenClaw sessions directory.
struct SessionDiscovery: Sendable {

    /// The base directory containing session files and `sessions.json`.
    let sessionsDirectory: URL

    /// Initialize with the default or a custom sessions directory path.
    /// - Parameter path: Override path to the sessions directory.
    ///   Defaults to `~/.openclaw/agents/main/sessions`.
    init(path: String? = nil) {
        if let path {
            self.sessionsDirectory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.sessionsDirectory = home
                .appendingPathComponent(".openclaw")
                .appendingPathComponent("agents")
                .appendingPathComponent("main")
                .appendingPathComponent("sessions")
        }
    }

    /// Resolve the JSONL file path for the current (most recently updated) session.
    func resolveCurrentSession() throws(SessionDiscoveryError) -> ResolvedSession {
        let indexURL = sessionsDirectory.appendingPathComponent("sessions.json")

        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            throw .sessionsFileNotFound(path: indexURL.path)
        }

        let index: SessionIndex
        do {
            index = try SessionIndex.load(from: indexURL)
        } catch {
            throw .indexLoadFailed(underlying: error)
        }

        guard let (key, entry) = index.mostRecentSession() else {
            throw .noSessionsFound
        }

        // Build the JSONL file path from the session ID
        let jsonlFile = sessionsDirectory
            .appendingPathComponent("\(entry.sessionId).jsonl")

        guard FileManager.default.fileExists(atPath: jsonlFile.path) else {
            throw .sessionFileNotFound(
                sessionId: entry.sessionId,
                path: jsonlFile.path
            )
        }

        return ResolvedSession(
            sessionKey: key,
            sessionId: entry.sessionId,
            filePath: jsonlFile,
            model: entry.model,
            provider: entry.modelProvider
        )
    }
}


// MARK: - Resolved Session

struct ResolvedSession: Sendable {
    let sessionKey: String
    let sessionId: String
    let filePath: URL
    let model: String?
    let provider: String?
}


// MARK: - Errors

enum SessionDiscoveryError: Error, CustomStringConvertible {
    case sessionsFileNotFound(path: String)
    case indexLoadFailed(underlying: any Error)
    case noSessionsFound
    case sessionFileNotFound(sessionId: String, path: String)

    var description: String {
        switch self {
        case .sessionsFileNotFound(let path):
            "sessions.json not found at \(path)"
        case .indexLoadFailed(let err):
            "Failed to load sessions.json: \(err)"
        case .noSessionsFound:
            "No sessions found in sessions.json"
        case .sessionFileNotFound(let id, let path):
            "Session file for \(id) not found at \(path)"
        }
    }
}
