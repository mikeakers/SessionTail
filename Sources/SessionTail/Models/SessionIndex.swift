import struct Foundation.URL
import struct Foundation.Data
import class Foundation.JSONDecoder

/// Represents the structure of `sessions.json`, mapping session keys to session metadata.
struct SessionIndex: Sendable {

    struct SessionEntry: Sendable {
        let sessionId: String
        let updatedAt: Int
        let sessionFile: String?
        let model: String?
        let modelProvider: String?
    }

    let entries: [String: SessionEntry]

    /// Load and parse a `sessions.json` file.
    static func load(from url: URL) throws(SessionIndexError) -> SessionIndex {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .fileNotReadable(path: url.path, underlying: error)
        }

        let raw: [String: RawSessionEntry]
        do {
            raw = try JSONDecoder().decode([String: RawSessionEntry].self, from: data)
        } catch {
            throw .invalidJSON(path: url.path, underlying: error)
        }

        var entries: [String: SessionEntry] = [:]
        for (key, value) in raw {
            entries[key] = SessionEntry(
                sessionId: value.sessionId,
                updatedAt: value.updatedAt ?? 0,
                sessionFile: value.sessionFile,
                model: value.model,
                modelProvider: value.modelProvider
            )
        }

        return SessionIndex(entries: entries)
    }

    /// Returns the most recently updated session entry, if any.
    func mostRecentSession() -> (key: String, entry: SessionEntry)? {
        guard let result = entries.max(by: { $0.value.updatedAt < $1.value.updatedAt }) else {
            return nil
        }
        return (key: result.key, entry: result.value)
    }
}


// MARK: - Errors

enum SessionIndexError: Error, CustomStringConvertible {
    case fileNotReadable(path: String, underlying: any Error)
    case invalidJSON(path: String, underlying: any Error)

    var description: String {
        switch self {
        case .fileNotReadable(let path, let err):
            "Cannot read sessions.json at \(path): \(err)"
        case .invalidJSON(let path, let err):
            "Invalid JSON in sessions.json at \(path): \(err)"
        }
    }
}


// MARK: - Raw Decodable

private struct RawSessionEntry: Decodable {
    let sessionId: String
    let updatedAt: Int?
    let sessionFile: String?
    let model: String?
    let modelProvider: String?
}
