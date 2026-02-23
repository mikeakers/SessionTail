import Foundation

/// Reads a session JSONL file line-by-line, with optional tail (follow) support.
struct SessionReader: Sendable {

    let filePath: URL

    init(filePath: URL) {
        self.filePath = filePath
    }

    /// Read all existing lines from the file as an `AsyncStream` of raw strings.
    /// If `follow` is true, continues watching for new lines after reaching EOF.
    func lines(follow: Bool) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await readLines(follow: follow, continuation: continuation)
                } catch {
                    if !Task.isCancelled {
                        continuation.finish()
                    }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func readLines(
        follow: Bool,
        continuation: AsyncStream<String>.Continuation
    ) async throws {
        guard let handle = FileHandle(forReadingAtPath: filePath.path) else {
            throw SessionReaderError.cannotOpenFile(path: filePath.path)
        }
        defer { handle.closeFile() }

        var buffer = Data()
        let newline = UInt8(ascii: "\n")
        let chunkSize = 64 * 1024  // 64 KB read chunks

        // Read existing content
        while !Task.isCancelled {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            buffer.append(chunk)

            // Extract complete lines from buffer
            while let newlineIndex = buffer.firstIndex(of: newline) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer = Data(buffer[(newlineIndex + 1)...])

                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    continuation.yield(line)
                }
            }
        }

        // Yield any remaining data without a trailing newline
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
            continuation.yield(line)
            buffer.removeAll()
        }

        guard follow, !Task.isCancelled else {
            continuation.finish()
            return
        }

        // Follow mode: poll for new data
        let pollInterval: UInt64 = 250_000_000  // 250ms

        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: pollInterval)

            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { continue }

            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: newline) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer = Data(buffer[(newlineIndex + 1)...])

                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    continuation.yield(line)
                }
            }
        }

        continuation.finish()
    }
}


// MARK: - Errors

enum SessionReaderError: Error, CustomStringConvertible {
    case cannotOpenFile(path: String)

    var description: String {
        switch self {
        case .cannotOpenFile(let path):
            "Cannot open file: \(path)"
        }
    }
}
