/// Renders `SessionEvent` values as formatted, color-coded terminal output.
struct EventRenderer: Sendable {

    let showThinking: Bool
    let truncateLength: Int

    /// Create a renderer.
    /// - Parameters:
    ///   - showThinking: Whether to display thinking blocks. Defaults to `true`.
    ///   - fullOutput: If `true`, don't truncate long outputs. Defaults to `false`.
    init(showThinking: Bool = true, fullOutput: Bool = false) {
        self.showThinking = showThinking
        self.truncateLength = fullOutput ? Int.max : 500
    }

    /// Render a session event to a displayable string.
    /// Returns `nil` if the event should be silently skipped.
    func render(_ event: SessionEvent) -> String? {
        switch event {
        case .session(let header):
            return renderSessionHeader(header)
        case .modelChange(let change):
            return renderModelChange(change)
        case .thinkingLevelChange(let change):
            return renderThinkingLevelChange(change)
        case .custom:
            // Skip custom events (cache-ttl, model-snapshot, etc.)
            return nil
        case .message(let msg):
            return renderMessage(msg)
        case .unknown:
            return nil
        }
    }

    // MARK: - Session Header

    private func renderSessionHeader(_ header: SessionHeader) -> String {
        var lines: [String] = []
        lines.append("")
        lines.append(separator())
        lines.append(styled("  SESSION START", .bold, .brightMagenta))
        lines.append(styled("  ID: \(header.id)", .dim))
        if let cwd = header.cwd {
            lines.append(styled("  CWD: \(cwd)", .dim))
        }
        lines.append(styled("  Time: \(formatTimestamp(header.timestamp))", .dim))
        lines.append(separator())
        return lines.joined(separator: "\n")
    }

    // MARK: - Model Change

    private func renderModelChange(_ change: ModelChange) -> String {
        styled("  [model] \(change.provider)/\(change.modelId)", .gray)
    }

    // MARK: - Thinking Level

    private func renderThinkingLevelChange(_ change: ThinkingLevelChange) -> String {
        styled("  [thinking: \(change.thinkingLevel)]", .gray)
    }

    // MARK: - Messages

    private func renderMessage(_ event: MessageEvent) -> String {
        let msg = event.message

        switch msg.role {
        case .user:
            return renderUserMessage(msg)
        case .assistant:
            return renderAssistantMessage(msg)
        case .toolResult:
            return renderToolResult(msg)
        case .system:
            return renderSystemMessage(msg)
        case .unknown:
            return styled("  [unknown role]", .dim)
        }
    }

    private func renderUserMessage(_ msg: MessagePayload) -> String {
        var lines: [String] = []
        lines.append("")
        lines.append(styled("  USER", .bold, .green))

        for block in msg.content {
            switch block {
            case .text(let text):
                let cleaned = cleanMessageText(text)
                for line in cleaned.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("  \(line)")
                }
            case .thinking(let text) where showThinking:
                lines.append(styled("  💭 \(truncate(text))", .gray))
            default:
                break
            }
        }

        return lines.joined(separator: "\n")
    }

    private func renderAssistantMessage(_ msg: MessagePayload) -> String {
        // Skip empty error responses (API failures with no content)
        let hasContent = msg.content.contains { block in
            switch block {
            case .text(let t): !t.isEmpty
            case .thinking(let t): showThinking && !t.isEmpty
            case .toolCall: true
            case .unknown: false
            }
        }

        if !hasContent && msg.stopReason == "error" {
            return styled("  [API error — empty response]", .dim, .red)
        }

        var lines: [String] = []
        lines.append("")

        // Role label with optional model info
        lines.append(styled("  ASSISTANT", .bold, .blue) + (msg.model.map { styled(" (\($0))", .dim) } ?? ""))

        for block in msg.content {
            switch block {
            case .text(let text):
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("  \(line)")
                }
            case .thinking(let text) where showThinking:
                lines.append(styled("  💭 \(truncate(text))", .gray))
            case .toolCall(let call):
                lines.append(renderToolCall(call))
            default:
                break
            }
        }

        // Usage summary — only show if there are meaningful values
        if let usage = msg.usage {
            var parts: [String] = []
            if let input = usage.input, input > 0 { parts.append("in:\(input)") }
            if let output = usage.output, output > 0 { parts.append("out:\(output)") }
            if let total = usage.totalTokens, total > 0 { parts.append("total:\(total)") }
            if !parts.isEmpty {
                lines.append(styled("  [tokens: \(parts.joined(separator: " "))]", .dim))
            }
        }

        if let stop = msg.stopReason, stop != "stop" && stop != "end_turn" {
            lines.append(styled("  [stop: \(stop)]", .dim))
        }

        return lines.joined(separator: "\n")
    }

    private func renderToolCall(_ call: ToolCallBlock) -> String {
        let args = truncate(call.arguments)
        return styled("  [tool call] ", .yellow) + styled(call.name, .bold, .yellow) + styled(" \(args)", .dim)
    }

    private func renderToolResult(_ msg: MessagePayload) -> String {
        var lines: [String] = []

        let toolLabel = msg.toolName ?? "tool"
        let errorMarker = (msg.isError == true) ? styled(" ERROR", .red, .bold) : ""
        lines.append(styled("  [tool result] ", .cyan) + styled(toolLabel, .bold, .cyan) + errorMarker)

        // Show aggregated output from details if available, otherwise fall back to content
        if let details = msg.details, let aggregated = details.aggregated, !aggregated.isEmpty {
            let output = truncate(aggregated)
            for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append(styled("  | \(line)", .dim))
            }
            if let exit = details.exitCode, exit != 0 {
                lines.append(styled("  [exit: \(exit)]", .red))
            }
            if let ms = details.durationMs {
                lines.append(styled("  [\(ms)ms]", .dim))
            }
        } else {
            for block in msg.content {
                if case .text(let text) = block {
                    let output = truncate(text)
                    for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
                        lines.append(styled("  | \(line)", .dim))
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func renderSystemMessage(_ msg: MessagePayload) -> String {
        var lines: [String] = []
        lines.append(styled("  SYSTEM", .bold, .magenta))
        for block in msg.content {
            if case .text(let text) = block {
                lines.append(styled("  \(truncate(text))", .dim))
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Strip "Conversation info (untrusted metadata)" wrappers from user messages.
    private func cleanMessageText(_ text: String) -> String {
        var cleaned = text

        // Remove the metadata JSON block that OpenClaw prepends to user messages
        if cleaned.contains("Conversation info (untrusted metadata):") {
            // Find the end of the JSON block (closing ```) and take everything after
            if let range = cleaned.range(of: "```\n\n", options: [],
                                         range: cleaned.startIndex..<cleaned.endIndex) {
                cleaned = String(cleaned[range.upperBound...])
            } else if let range = cleaned.range(of: "```\n") {
                cleaned = String(cleaned[range.upperBound...])
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func truncate(_ text: String) -> String {
        guard text.count > truncateLength else { return text }
        let index = text.index(text.startIndex, offsetBy: truncateLength)
        return String(text[..<index]) + "..."
    }

    private func formatTimestamp(_ ts: String) -> String {
        // Timestamps are ISO8601 strings like "2026-02-22T09:29:19.568Z"
        // Display a shorter human-readable version
        if let tIndex = ts.firstIndex(of: "T"),
           let dotIndex = ts.firstIndex(of: ".") {
            let date = ts[ts.startIndex..<tIndex]
            let time = ts[ts.index(after: tIndex)..<dotIndex]
            return "\(date) \(time) UTC"
        }
        return ts
    }
}
