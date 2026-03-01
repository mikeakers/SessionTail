import struct Foundation.URL
import class Foundation.FileManager
import class Foundation.NSString
import struct Foundation.Date

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

    /// Returns all sessions from `sessions.json`, sorted by `updatedAt` descending.
    ///
    /// - Parameter includeDeleted: When `false` (default), entries whose `.jsonl` file does not
    ///   exist on disk are omitted. Pass `true` to include them.
    func allSessions(includeDeleted: Bool = false) throws(SessionDiscoveryError) -> [SessionListing] {
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

        // Sort all entries by updatedAt descending
        let sorted = index.entries
            .map { (key: $0.key, entry: $0.value) }
            .sorted { $0.entry.updatedAt > $1.entry.updatedAt }

        // Determine which session would be auto-selected (highest updatedAt with existing file)
        let currentSessionId = sorted
            .first {
                let file = sessionsDirectory.appendingPathComponent("\($0.entry.sessionId).jsonl")
                return FileManager.default.fileExists(atPath: file.path)
            }?
            .entry.sessionId

        var listings: [SessionListing] = []
        for item in sorted {
            let resolvedFile = resolveJsonlFile(sessionId: item.entry.sessionId)
            let exists = resolvedFile != nil
            let filePath = resolvedFile
                ?? sessionsDirectory.appendingPathComponent("\(item.entry.sessionId).jsonl")

            if !includeDeleted && !exists {
                continue
            }

            listings.append(SessionListing(
                key: item.key,
                entry: item.entry,
                filePath: filePath,
                fileExists: exists,
                isCurrent: item.entry.sessionId == currentSessionId
            ))
        }

        return listings
    }

    /// Resolve a session by session key (e.g. `agent:main:main`) or UUID, with key taking priority.
    func resolveSession(byId id: String) throws(SessionDiscoveryError) -> ResolvedSession {
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

        // Try exact key match first, then fall back to UUID match
        let matchedKey: String
        let matchedEntry: SessionIndex.SessionEntry
        if let entry = index.entries[id] {
            matchedKey = id
            matchedEntry = entry
        } else if let pair = index.entries.first(where: { $0.value.sessionId == id }) {
            matchedKey = pair.key
            matchedEntry = pair.value
        } else {
            throw .sessionKeyNotFound(id: id)
        }

        guard let jsonlFile = resolveJsonlFile(sessionId: matchedEntry.sessionId) else {
            let expectedPath = sessionsDirectory.appendingPathComponent("\(matchedEntry.sessionId).jsonl").path
            throw .sessionFileNotFound(sessionId: matchedEntry.sessionId, path: expectedPath)
        }

        return ResolvedSession(
            sessionKey: matchedKey,
            sessionId: matchedEntry.sessionId,
            filePath: jsonlFile,
            model: matchedEntry.model,
            provider: matchedEntry.modelProvider
        )
    }

    /// Finds the JSONL file for a session ID, checking for the live path first, then a
    /// `.deleted.<timestamp>` variant. Returns `nil` if neither exists on disk.
    private func resolveJsonlFile(sessionId: String) -> URL? {
        let live = sessionsDirectory.appendingPathComponent("\(sessionId).jsonl")
        if FileManager.default.fileExists(atPath: live.path) {
            return live
        }

        // Glob for a deleted variant: <sessionId>.jsonl.deleted.<timestamp>
        let prefix = "\(sessionId).jsonl.deleted."
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: sessionsDirectory.path)) ?? []
        if let match = contents.first(where: { $0.hasPrefix(prefix) }) {
            return sessionsDirectory.appendingPathComponent(match)
        }

        return nil
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


// MARK: - Session Listing

/// A single entry in the sessions listing, enriched with filesystem and recency metadata.
struct SessionListing: Sendable {
    let key: String
    let entry: SessionIndex.SessionEntry
    let filePath: URL
    /// Whether the corresponding `.jsonl` file currently exists on disk.
    let fileExists: Bool
    /// Whether this session would be auto-selected by `resolveCurrentSession()`.
    let isCurrent: Bool
}


// MARK: - Errors

enum SessionDiscoveryError: Error, CustomStringConvertible {
    case sessionsFileNotFound(path: String)
    case indexLoadFailed(underlying: any Error)
    case noSessionsFound
    case sessionFileNotFound(sessionId: String, path: String)
    case sessionKeyNotFound(id: String)

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
        case .sessionKeyNotFound(let id):
            "No session found with key '\(id)'"
        }
    }
}
