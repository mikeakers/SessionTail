import Foundation

// MARK: - Top-Level Event

/// A single line from a session JSONL file, discriminated by the `type` field.
enum SessionEvent: Sendable {
    case session(SessionHeader)
    case modelChange(ModelChange)
    case thinkingLevelChange(ThinkingLevelChange)
    case custom(CustomEvent)
    case message(MessageEvent)
    case unknown(type: String)
}


// MARK: - Event Payloads

struct SessionHeader: Sendable {
    let id: String
    let version: Int
    let timestamp: String
    let cwd: String?
}


struct ModelChange: Sendable {
    let id: String
    let timestamp: String
    let provider: String
    let modelId: String
}


struct ThinkingLevelChange: Sendable {
    let id: String
    let timestamp: String
    let thinkingLevel: String
}


struct CustomEvent: Sendable {
    let id: String
    let timestamp: String
    let customType: String
}


struct MessageEvent: Sendable {
    let id: String
    let parentId: String?
    let timestamp: String
    let message: MessagePayload
}


// MARK: - Message Payload

struct MessagePayload: Sendable {
    let role: MessageRole
    let content: [ContentBlock]
    let provider: String?
    let model: String?
    let stopReason: String?
    let usage: UsageInfo?
    /// For toolResult messages
    let toolCallId: String?
    let toolName: String?
    let isError: Bool?
    let details: ToolResultDetails?
}


enum MessageRole: String, Sendable {
    case user
    case assistant
    case toolResult
    case system
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "user": self = .user
        case "assistant": self = .assistant
        case "toolResult": self = .toolResult
        case "system": self = .system
        default: self = .unknown
        }
    }
}


// MARK: - Content Blocks

enum ContentBlock: Sendable {
    case text(String)
    case thinking(String)
    case toolCall(ToolCallBlock)
    case unknown(type: String)
}


struct ToolCallBlock: Sendable {
    let id: String
    let name: String
    let arguments: String
}


struct ToolResultDetails: Sendable {
    let status: String?
    let exitCode: Int?
    let durationMs: Int?
    let aggregated: String?
}


struct UsageInfo: Sendable {
    let input: Int?
    let output: Int?
    let totalTokens: Int?
}


// MARK: - Decoding

enum SessionEventDecoder {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    /// Decode a single JSONL line into a `SessionEvent`.
    /// Returns `nil` for blank lines, throws for malformed JSON.
    static func decode(line: String) throws -> SessionEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = trimmed.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Line is not valid UTF-8")
            )
        }

        let raw = try decoder.decode(RawEvent.self, from: data)

        switch raw.type {
        case "session":
            return .session(SessionHeader(
                id: raw.id ?? "",
                version: raw.version ?? 0,
                timestamp: raw.timestamp ?? "",
                cwd: raw.cwd
            ))

        case "model_change":
            return .modelChange(ModelChange(
                id: raw.id ?? "",
                timestamp: raw.timestamp ?? "",
                provider: raw.provider ?? "",
                modelId: raw.modelId ?? ""
            ))

        case "thinking_level_change":
            return .thinkingLevelChange(ThinkingLevelChange(
                id: raw.id ?? "",
                timestamp: raw.timestamp ?? "",
                thinkingLevel: raw.thinkingLevel ?? ""
            ))

        case "custom":
            return .custom(CustomEvent(
                id: raw.id ?? "",
                timestamp: raw.timestamp ?? "",
                customType: raw.customType ?? ""
            ))

        case "message":
            guard let msg = raw.message else {
                return .unknown(type: "message(no payload)")
            }
            let payload = decodeMessagePayload(msg)
            return .message(MessageEvent(
                id: raw.id ?? "",
                parentId: raw.parentId,
                timestamp: raw.timestamp ?? "",
                message: payload
            ))

        default:
            return .unknown(type: raw.type)
        }
    }

    private static func decodeMessagePayload(_ raw: RawMessage) -> MessagePayload {
        let role = MessageRole(rawValue: raw.role)

        var contentBlocks: [ContentBlock] = []

        if let contentArray = raw.content {
            for block in contentArray {
                switch block.type {
                case "text":
                    contentBlocks.append(.text(block.text ?? ""))
                case "thinking":
                    contentBlocks.append(.thinking(block.thinking ?? ""))
                case "toolCall":
                    let args: String
                    if let argsDict = block.arguments {
                        // Convert AnyCodable values to Foundation-compatible types
                        let foundation = argsDict.mapValues { $0.foundationValue }
                        if let jsonData = try? JSONSerialization.data(
                            withJSONObject: foundation, options: [.sortedKeys]
                        ) {
                            args = String(data: jsonData, encoding: .utf8) ?? "{}"
                        } else {
                            args = "{}"
                        }
                    } else {
                        args = "{}"
                    }
                    contentBlocks.append(.toolCall(ToolCallBlock(
                        id: block.id ?? "",
                        name: block.name ?? "",
                        arguments: args
                    )))
                default:
                    contentBlocks.append(.unknown(type: block.type ?? "nil"))
                }
            }
        }

        var details: ToolResultDetails?
        if let rawDetails = raw.details {
            details = ToolResultDetails(
                status: rawDetails.status,
                exitCode: rawDetails.exitCode,
                durationMs: rawDetails.durationMs,
                aggregated: rawDetails.aggregated
            )
        }

        var usage: UsageInfo?
        if let rawUsage = raw.usage {
            usage = UsageInfo(
                input: rawUsage.input,
                output: rawUsage.output,
                totalTokens: rawUsage.totalTokens
            )
        }

        return MessagePayload(
            role: role,
            content: contentBlocks,
            provider: raw.provider,
            model: raw.model,
            stopReason: raw.stopReason,
            usage: usage,
            toolCallId: raw.toolCallId,
            toolName: raw.toolName,
            isError: raw.isError,
            details: details
        )
    }
}


// MARK: - Raw Decodable Types (internal)

/// Flat decodable struct that captures all possible top-level fields across event types.
private struct RawEvent: Decodable {
    let type: String
    let id: String?
    let parentId: String?
    let timestamp: String?
    let version: Int?
    let cwd: String?
    // model_change
    let provider: String?
    let modelId: String?
    // thinking_level_change
    let thinkingLevel: String?
    // custom
    let customType: String?
    // message
    let message: RawMessage?
}


private struct RawMessage: Decodable {
    let role: String
    let content: [RawContentBlock]?
    let timestamp: Int?
    // assistant fields
    let provider: String?
    let model: String?
    let stopReason: String?
    let usage: RawUsage?
    // toolResult fields
    let toolCallId: String?
    let toolName: String?
    let isError: Bool?
    let details: RawDetails?
}


private struct RawContentBlock: Decodable {
    let type: String?
    let text: String?
    let thinking: String?
    // toolCall fields
    let id: String?
    let name: String?
    let arguments: [String: AnyCodable]?
}


private struct RawDetails: Decodable {
    let status: String?
    let exitCode: Int?
    let durationMs: Int?
    let aggregated: String?
}


private struct RawUsage: Decodable {
    let input: Int?
    let output: Int?
    let totalTokens: Int?
}


// MARK: - AnyCodable helper

/// A type-erased Codable value for handling arbitrary JSON arguments.
/// We use `@unchecked Sendable` because the stored `value` is only ever
/// set during `init(from:)` and is never mutated afterward.
private struct AnyCodable: Decodable, @unchecked Sendable {
    let value: Any

    /// Returns a Foundation-compatible value safe for `JSONSerialization`.
    var foundationValue: Any {
        AnyCodable.toFoundation(value)
    }

    private static func toFoundation(_ value: Any) -> Any {
        switch value {
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let double as Double:
            return double
        case let string as String:
            return string
        case let array as [Any]:
            return array.map { toFoundation($0) }
        case let dict as [String: Any]:
            return dict.mapValues { toFoundation($0) }
        default:
            if isNil(value) { return NSNull() }
            return "\(value)"
        }
    }

    /// Check if an `Any` value is actually `nil` (wrapped in Optional).
    private static func isNil(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            return mirror.children.isEmpty
        }
        return false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = Optional<String>.none as Any
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = Optional<String>.none as Any
        }
    }
}
