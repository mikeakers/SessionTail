import Foundation
import Testing
@testable import SessionTail

// MARK: - SessionEvent Decoding Tests

@Suite("SessionEvent Decoding")
struct SessionEventDecodingTests {

    @Test func decodesSessionHeader() throws {
        let line = """
        {"type":"session","version":3,"id":"abc-123","timestamp":"2026-02-22T09:29:19.568Z","cwd":"/home/user/workspace"}
        """
        let event = try SessionEventDecoder.decode(line: line)
        guard case .session(let header) = event else {
            Issue.record("Expected .session, got \(String(describing: event))")
            return
        }
        #expect(header.id == "abc-123")
        #expect(header.version == 3)
        #expect(header.cwd == "/home/user/workspace")
        #expect(header.timestamp == "2026-02-22T09:29:19.568Z")
    }

    @Test func decodesModelChange() throws {
        let line = """
        {"type":"model_change","id":"d50221da","parentId":null,"timestamp":"2026-02-22T09:29:19.570Z","provider":"anthropic","modelId":"claude-sonnet-4-6"}
        """
        let event = try SessionEventDecoder.decode(line: line)
        guard case .modelChange(let change) = event else {
            Issue.record("Expected .modelChange, got \(String(describing: event))")
            return
        }
        #expect(change.provider == "anthropic")
        #expect(change.modelId == "claude-sonnet-4-6")
    }

    @Test func decodesThinkingLevelChange() throws {
        let line = """
        {"type":"thinking_level_change","id":"2403b711","parentId":"d50221da","timestamp":"2026-02-22T09:29:19.570Z","thinkingLevel":"low"}
        """
        let event = try SessionEventDecoder.decode(line: line)
        guard case .thinkingLevelChange(let change) = event else {
            Issue.record("Expected .thinkingLevelChange, got \(String(describing: event))")
            return
        }
        #expect(change.thinkingLevel == "low")
    }

    @Test func decodesCustomEvent() throws {
        let line = """
        {"type":"custom","customType":"model-snapshot","data":{"timestamp":1234},"id":"5f16e11c","parentId":"2403b711","timestamp":"2026-02-22T09:29:19.573Z"}
        """
        let event = try SessionEventDecoder.decode(line: line)
        guard case .custom(let custom) = event else {
            Issue.record("Expected .custom, got \(String(describing: event))")
            return
        }
        #expect(custom.customType == "model-snapshot")
    }

    @Test func decodesUserMessage() throws {
        let line = """
        {"type":"message","id":"9b8834d0","parentId":"5f16e11c","timestamp":"2026-02-22T09:29:19.577Z","message":{"role":"user","content":[{"type":"text","text":"Hello world"}],"timestamp":1771752559576}}
        """
        let event = try SessionEventDecoder.decode(line: line)
        guard case .message(let msg) = event else {
            Issue.record("Expected .message, got \(String(describing: event))")
            return
        }
        #expect(msg.message.role == .user)
        #expect(msg.message.content.count == 1)
        if case .text(let text) = msg.message.content.first {
            #expect(text == "Hello world")
        } else {
            Issue.record("Expected .text content block")
        }
    }

    @Test func decodesAssistantMessageWithThinking() throws {
        let line = """
        {"type":"message","id":"5cfe9d7c","parentId":"9b8834d0","timestamp":"2026-02-22T09:29:22.547Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"Let me think about this."},{"type":"text","text":"Here is my response."}],"provider":"anthropic","model":"claude-sonnet-4-6","usage":{"input":10,"output":125,"totalTokens":16698},"stopReason":"stop"}}
        """
        let event = try SessionEventDecoder.decode(line: line)
        guard case .message(let msg) = event else {
            Issue.record("Expected .message, got \(String(describing: event))")
            return
        }
        #expect(msg.message.role == .assistant)
        #expect(msg.message.model == "claude-sonnet-4-6")
        #expect(msg.message.provider == "anthropic")
        #expect(msg.message.stopReason == "stop")
        #expect(msg.message.content.count == 2)

        if case .thinking(let thought) = msg.message.content[0] {
            #expect(thought == "Let me think about this.")
        } else {
            Issue.record("Expected .thinking content block at index 0")
        }

        if case .text(let text) = msg.message.content[1] {
            #expect(text == "Here is my response.")
        } else {
            Issue.record("Expected .text content block at index 1")
        }

        #expect(msg.message.usage?.input == 10)
        #expect(msg.message.usage?.output == 125)
        #expect(msg.message.usage?.totalTokens == 16698)
    }

    @Test func decodesAssistantMessageWithToolCall() throws {
        let line = """
        {"type":"message","id":"abc","parentId":"def","timestamp":"2026-02-22T09:29:22.547Z","message":{"role":"assistant","content":[{"type":"toolCall","id":"toolu_123","name":"exec","arguments":{"command":"ls -la"}}],"provider":"anthropic","model":"claude-sonnet-4-6","stopReason":"toolUse"}}
        """
        let event = try SessionEventDecoder.decode(line: line)
        guard case .message(let msg) = event else {
            Issue.record("Expected .message, got \(String(describing: event))")
            return
        }
        #expect(msg.message.stopReason == "toolUse")
        #expect(msg.message.content.count == 1)

        if case .toolCall(let call) = msg.message.content.first {
            #expect(call.name == "exec")
            #expect(call.id == "toolu_123")
            #expect(call.arguments.contains("ls -la"))
        } else {
            Issue.record("Expected .toolCall content block")
        }
    }

    @Test func decodesToolResultMessage() throws {
        let line = """
        {"type":"message","id":"f8667d42","parentId":"5cfe9d7c","timestamp":"2026-02-22T09:29:22.768Z","message":{"role":"toolResult","toolCallId":"toolu_123","toolName":"exec","content":[{"type":"text","text":"file1.txt\\nfile2.txt"}],"details":{"status":"completed","exitCode":0,"durationMs":216,"aggregated":"file1.txt\\nfile2.txt"},"isError":false}}
        """
        let event = try SessionEventDecoder.decode(line: line)
        guard case .message(let msg) = event else {
            Issue.record("Expected .message, got \(String(describing: event))")
            return
        }
        #expect(msg.message.role == .toolResult)
        #expect(msg.message.toolName == "exec")
        #expect(msg.message.toolCallId == "toolu_123")
        #expect(msg.message.isError == false)
        #expect(msg.message.details?.exitCode == 0)
        #expect(msg.message.details?.durationMs == 216)
        #expect(msg.message.details?.status == "completed")
    }

    @Test func returnsNilForBlankLine() throws {
        let event = try SessionEventDecoder.decode(line: "")
        #expect(event == nil)
    }

    @Test func returnsNilForWhitespaceLine() throws {
        let event = try SessionEventDecoder.decode(line: "   \n  ")
        #expect(event == nil)
    }

    @Test func decodesUnknownTypeGracefully() throws {
        let line = """
        {"type":"future_event_type","id":"xyz","timestamp":"2026-01-01T00:00:00Z"}
        """
        let event = try SessionEventDecoder.decode(line: line)
        guard case .unknown(let type) = event else {
            Issue.record("Expected .unknown, got \(String(describing: event))")
            return
        }
        #expect(type == "future_event_type")
    }
}


// MARK: - EventRenderer Tests

@Suite("EventRenderer")
struct EventRendererTests {

    let renderer = EventRenderer(showThinking: true, fullOutput: false)
    let noThinkingRenderer = EventRenderer(showThinking: false, fullOutput: false)

    @Test func rendersSessionHeader() {
        let event = SessionEvent.session(SessionHeader(
            id: "abc-123",
            version: 3,
            timestamp: "2026-02-22T09:29:19.568Z",
            cwd: "/home/user"
        ))
        let output = renderer.render(event)
        #expect(output != nil)
        #expect(output!.contains("SESSION START"))
        #expect(output!.contains("abc-123"))
        #expect(output!.contains("/home/user"))
    }

    @Test func rendersModelChange() {
        let event = SessionEvent.modelChange(ModelChange(
            id: "d50",
            timestamp: "2026-02-22T09:29:19.570Z",
            provider: "anthropic",
            modelId: "claude-sonnet-4-6"
        ))
        let output = renderer.render(event)
        #expect(output != nil)
        #expect(output!.contains("anthropic/claude-sonnet-4-6"))
    }

    @Test func skipsCustomEvents() {
        let event = SessionEvent.custom(CustomEvent(
            id: "x",
            timestamp: "2026-01-01T00:00:00Z",
            customType: "cache-ttl"
        ))
        #expect(renderer.render(event) == nil)
    }

    @Test func rendersUserMessage() {
        let event = SessionEvent.message(MessageEvent(
            id: "msg1",
            parentId: nil,
            timestamp: "2026-02-22T14:04:00.769Z",
            message: MessagePayload(
                role: .user,
                content: [.text("Hello, how are you?")],
                provider: nil,
                model: nil,
                stopReason: nil,
                usage: nil,
                toolCallId: nil,
                toolName: nil,
                isError: nil,
                details: nil
            )
        ))
        let output = renderer.render(event)
        #expect(output != nil)
        #expect(output!.contains("USER"))
        #expect(output!.contains("Hello, how are you?"))
    }

    @Test func rendersAssistantMessage() {
        let event = SessionEvent.message(MessageEvent(
            id: "msg2",
            parentId: "msg1",
            timestamp: "2026-02-22T14:04:03.034Z",
            message: MessagePayload(
                role: .assistant,
                content: [
                    .thinking("Let me consider this."),
                    .text("Here is my answer."),
                ],
                provider: "anthropic",
                model: "claude-sonnet-4-6",
                stopReason: "stop",
                usage: UsageInfo(input: 10, output: 50, totalTokens: 100),
                toolCallId: nil,
                toolName: nil,
                isError: nil,
                details: nil
            )
        ))
        let output = renderer.render(event)
        #expect(output != nil)
        #expect(output!.contains("ASSISTANT"))
        #expect(output!.contains("claude-sonnet-4-6"))
        #expect(output!.contains("Here is my answer."))
        #expect(output!.contains("💭"))
        #expect(output!.contains("Let me consider this."))
    }

    @Test func hidesThinkingWhenDisabled() {
        let event = SessionEvent.message(MessageEvent(
            id: "msg2",
            parentId: "msg1",
            timestamp: "2026-02-22T14:04:03.034Z",
            message: MessagePayload(
                role: .assistant,
                content: [
                    .thinking("Secret thoughts."),
                    .text("Visible answer."),
                ],
                provider: nil,
                model: nil,
                stopReason: "stop",
                usage: nil,
                toolCallId: nil,
                toolName: nil,
                isError: nil,
                details: nil
            )
        ))
        let output = noThinkingRenderer.render(event)
        #expect(output != nil)
        #expect(!output!.contains("Secret thoughts."))
        #expect(output!.contains("Visible answer."))
    }

    @Test func rendersToolCallInAssistantMessage() {
        let event = SessionEvent.message(MessageEvent(
            id: "msg3",
            parentId: "msg2",
            timestamp: "2026-02-22T14:04:03.034Z",
            message: MessagePayload(
                role: .assistant,
                content: [
                    .toolCall(ToolCallBlock(id: "t1", name: "exec", arguments: "{\"command\":\"ls\"}")),
                ],
                provider: nil,
                model: nil,
                stopReason: "toolUse",
                usage: nil,
                toolCallId: nil,
                toolName: nil,
                isError: nil,
                details: nil
            )
        ))
        let output = renderer.render(event)
        #expect(output != nil)
        #expect(output!.contains("exec"))
        #expect(output!.contains("[tool call]"))
        #expect(output!.contains("[stop: toolUse]"))
    }

    @Test func rendersToolResult() {
        let event = SessionEvent.message(MessageEvent(
            id: "msg4",
            parentId: "msg3",
            timestamp: "2026-02-22T14:04:03.034Z",
            message: MessagePayload(
                role: .toolResult,
                content: [.text("output text")],
                provider: nil,
                model: nil,
                stopReason: nil,
                usage: nil,
                toolCallId: "t1",
                toolName: "exec",
                isError: false,
                details: ToolResultDetails(
                    status: "completed",
                    exitCode: 0,
                    durationMs: 150,
                    aggregated: "output text"
                )
            )
        ))
        let output = renderer.render(event)
        #expect(output != nil)
        #expect(output!.contains("[tool result]"))
        #expect(output!.contains("exec"))
        #expect(output!.contains("output text"))
        #expect(output!.contains("150ms"))
    }

    @Test func rendersToolResultWithError() {
        let event = SessionEvent.message(MessageEvent(
            id: "msg5",
            parentId: "msg3",
            timestamp: "2026-02-22T14:04:03.034Z",
            message: MessagePayload(
                role: .toolResult,
                content: [.text("command not found")],
                provider: nil,
                model: nil,
                stopReason: nil,
                usage: nil,
                toolCallId: "t1",
                toolName: "exec",
                isError: true,
                details: ToolResultDetails(
                    status: "completed",
                    exitCode: 127,
                    durationMs: 10,
                    aggregated: "command not found"
                )
            )
        ))
        let output = renderer.render(event)
        #expect(output != nil)
        #expect(output!.contains("ERROR"))
        #expect(output!.contains("exit: 127"))
    }

    @Test func rendersEmptyErrorAssistantMessageCompactly() {
        let event = SessionEvent.message(MessageEvent(
            id: "msg6",
            parentId: "msg5",
            timestamp: "2026-02-22T14:04:03.034Z",
            message: MessagePayload(
                role: .assistant,
                content: [],
                provider: "anthropic",
                model: "claude-sonnet-4-6",
                stopReason: "error",
                usage: UsageInfo(input: 0, output: 0, totalTokens: 0),
                toolCallId: nil,
                toolName: nil,
                isError: nil,
                details: nil
            )
        ))
        let output = renderer.render(event)
        #expect(output != nil)
        #expect(output!.contains("API error"))
        #expect(!output!.contains("ASSISTANT"))
    }

    @Test func truncatesLongOutput() {
        let renderer = EventRenderer(showThinking: true, fullOutput: false)
        let longText = String(repeating: "x", count: 1000)
        let event = SessionEvent.message(MessageEvent(
            id: "msg7",
            parentId: nil,
            timestamp: "2026-02-22T14:04:03.034Z",
            message: MessagePayload(
                role: .toolResult,
                content: [.text(longText)],
                provider: nil,
                model: nil,
                stopReason: nil,
                usage: nil,
                toolCallId: "t1",
                toolName: "exec",
                isError: false,
                details: ToolResultDetails(
                    status: "completed",
                    exitCode: 0,
                    durationMs: 100,
                    aggregated: longText
                )
            )
        ))
        let output = renderer.render(event)
        #expect(output != nil)
        #expect(output!.contains("..."))
    }
}


// MARK: - SessionDiscovery Listing Tests

@Suite("SessionDiscovery Listing")
struct SessionDiscoveryListingTests {

    /// Creates a temporary sessions directory containing a `sessions.json` and any specified `.jsonl` stubs.
    private func makeSessionsDir(
        entries: [(key: String, sessionId: String, updatedAt: Int)],
        presentSessionIds: Set<String>
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_sessions_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Write sessions.json
        var jsonEntries: [String] = []
        for entry in entries {
            jsonEntries.append("""
                "\(entry.key)": {"sessionId": "\(entry.sessionId)", "updatedAt": \(entry.updatedAt)}
                """)
        }
        let json = "{\n" + jsonEntries.joined(separator: ",\n") + "\n}"
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent("sessions.json"))

        // Write stub .jsonl files for sessions that should "exist"
        for sessionId in presentSessionIds {
            let stub = dir.appendingPathComponent("\(sessionId).jsonl")
            try "{}".data(using: .utf8)!.write(to: stub)
        }

        return dir
    }

    @Test func sortsByUpdatedAtDescending() throws {
        let dir = try makeSessionsDir(
            entries: [
                (key: "agent:main:a", sessionId: "aaaa0001", updatedAt: 100),
                (key: "agent:main:b", sessionId: "bbbb0002", updatedAt: 300),
                (key: "agent:main:c", sessionId: "cccc0003", updatedAt: 200),
            ],
            presentSessionIds: ["aaaa0001", "bbbb0002", "cccc0003"]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        let listings = try discovery.allSessions()

        #expect(listings.count == 3)
        #expect(listings[0].entry.sessionId == "bbbb0002")
        #expect(listings[1].entry.sessionId == "cccc0003")
        #expect(listings[2].entry.sessionId == "aaaa0001")
    }

    @Test func marksCurrentSession() throws {
        let dir = try makeSessionsDir(
            entries: [
                (key: "agent:main:a", sessionId: "aaaa0001", updatedAt: 100),
                (key: "agent:main:b", sessionId: "bbbb0002", updatedAt: 300),
            ],
            presentSessionIds: ["aaaa0001", "bbbb0002"]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        let listings = try discovery.allSessions()

        let current = listings.filter(\.isCurrent)
        #expect(current.count == 1)
        #expect(current[0].entry.sessionId == "bbbb0002")
        #expect(listings.first(where: { $0.entry.sessionId == "aaaa0001" })?.isCurrent == false)
    }

    @Test func excludesDeletedByDefault() throws {
        let dir = try makeSessionsDir(
            entries: [
                (key: "agent:main:live", sessionId: "live0001", updatedAt: 300),
                (key: "agent:main:gone", sessionId: "gone0002", updatedAt: 100),
            ],
            presentSessionIds: ["live0001"] // gone0002 has no .jsonl file
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        let listings = try discovery.allSessions(includeDeleted: false)

        #expect(listings.count == 1)
        #expect(listings[0].entry.sessionId == "live0001")
    }

    @Test func includesDeletedWhenFlagSet() throws {
        let dir = try makeSessionsDir(
            entries: [
                (key: "agent:main:live", sessionId: "live0001", updatedAt: 300),
                (key: "agent:main:gone", sessionId: "gone0002", updatedAt: 100),
            ],
            presentSessionIds: ["live0001"]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        let listings = try discovery.allSessions(includeDeleted: true)

        #expect(listings.count == 2)
        let gone = listings.first(where: { $0.entry.sessionId == "gone0002" })
        #expect(gone != nil)
        #expect(gone!.fileExists == false)
        #expect(gone!.isCurrent == false)
    }

    @Test func currentIsLiveSessionEvenIfDeletedHasHigherTimestamp() throws {
        // The deleted session has a higher updatedAt, but isCurrent should pick the highest *live* one
        let dir = try makeSessionsDir(
            entries: [
                (key: "agent:main:live", sessionId: "live0001", updatedAt: 200),
                (key: "agent:main:gone", sessionId: "gone0002", updatedAt: 999),
            ],
            presentSessionIds: ["live0001"] // gone0002 file is missing
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        let listings = try discovery.allSessions(includeDeleted: true)

        let current = listings.filter(\.isCurrent)
        #expect(current.count == 1)
        #expect(current[0].entry.sessionId == "live0001")
    }

    @Test func emptyIndexReturnsEmptyList() throws {
        let dir = try makeSessionsDir(entries: [], presentSessionIds: [])
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        let listings = try discovery.allSessions()
        #expect(listings.isEmpty)
    }

    @Test func throwsWhenSessionsJsonMissing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("no_such_dir_\(UUID().uuidString)")
        // Do NOT create the directory — sessions.json won't exist
        let discovery = SessionDiscovery(path: dir.path)
        #expect(throws: SessionDiscoveryError.self) {
            _ = try discovery.allSessions()
        }
    }
}


// MARK: - SessionDiscovery Resolve Tests

@Suite("SessionDiscovery Resolve")
struct SessionDiscoveryResolveTests {

    /// Creates a temporary sessions directory with a `sessions.json` and optional stub `.jsonl` files.
    private func makeSessionsDir(
        entries: [(key: String, sessionId: String, updatedAt: Int)],
        presentSessionIds: Set<String>
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_resolve_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var jsonEntries: [String] = []
        for entry in entries {
            jsonEntries.append("""
                "\(entry.key)": {"sessionId": "\(entry.sessionId)", "updatedAt": \(entry.updatedAt)}
                """)
        }
        let json = "{\n" + jsonEntries.joined(separator: ",\n") + "\n}"
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent("sessions.json"))

        for sessionId in presentSessionIds {
            try "{}".data(using: .utf8)!.write(to: dir.appendingPathComponent("\(sessionId).jsonl"))
        }

        return dir
    }

    @Test func resolvesBySessionKey() throws {
        let dir = try makeSessionsDir(
            entries: [
                (key: "agent:main:main", sessionId: "aaaa0001-0000-0000-0000-000000000000", updatedAt: 100),
                (key: "agent:main:other", sessionId: "bbbb0002-0000-0000-0000-000000000000", updatedAt: 200),
            ],
            presentSessionIds: ["aaaa0001-0000-0000-0000-000000000000", "bbbb0002-0000-0000-0000-000000000000"]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        let resolved = try discovery.resolveSession(byId: "agent:main:main")

        #expect(resolved.sessionKey == "agent:main:main")
        #expect(resolved.sessionId == "aaaa0001-0000-0000-0000-000000000000")
    }

    @Test func resolvesByUUIDFallback() throws {
        let dir = try makeSessionsDir(
            entries: [
                (key: "agent:main:main", sessionId: "aaaa0001-0000-0000-0000-000000000000", updatedAt: 100),
            ],
            presentSessionIds: ["aaaa0001-0000-0000-0000-000000000000"]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        let resolved = try discovery.resolveSession(byId: "aaaa0001-0000-0000-0000-000000000000")

        #expect(resolved.sessionKey == "agent:main:main")
        #expect(resolved.sessionId == "aaaa0001-0000-0000-0000-000000000000")
    }

    @Test func sessionKeyTakesPriorityOverUUID() throws {
        // A session whose key happens to equal another session's UUID — key match should win
        let dir = try makeSessionsDir(
            entries: [
                (key: "cccc0003-0000-0000-0000-000000000000", sessionId: "aaaa0001-0000-0000-0000-000000000000", updatedAt: 100),
                (key: "agent:main:other", sessionId: "cccc0003-0000-0000-0000-000000000000", updatedAt: 200),
            ],
            presentSessionIds: [
                "aaaa0001-0000-0000-0000-000000000000",
                "cccc0003-0000-0000-0000-000000000000",
            ]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        let resolved = try discovery.resolveSession(byId: "cccc0003-0000-0000-0000-000000000000")

        // Should match by key, not UUID fallback
        #expect(resolved.sessionKey == "cccc0003-0000-0000-0000-000000000000")
        #expect(resolved.sessionId == "aaaa0001-0000-0000-0000-000000000000")
    }

    @Test func throwsSessionKeyNotFoundForUnknownId() throws {
        let dir = try makeSessionsDir(
            entries: [
                (key: "agent:main:main", sessionId: "aaaa0001-0000-0000-0000-000000000000", updatedAt: 100),
            ],
            presentSessionIds: ["aaaa0001-0000-0000-0000-000000000000"]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        #expect(throws: SessionDiscoveryError.self) {
            _ = try discovery.resolveSession(byId: "agent:main:nonexistent")
        }
    }

    @Test func doesNotMatchPartialUUID() throws {
        let dir = try makeSessionsDir(
            entries: [
                (key: "agent:main:main", sessionId: "aaaa0001-0000-0000-0000-000000000000", updatedAt: 100),
            ],
            presentSessionIds: ["aaaa0001-0000-0000-0000-000000000000"]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        #expect(throws: SessionDiscoveryError.self) {
            _ = try discovery.resolveSession(byId: "aaaa0001")
        }
    }

    @Test func throwsSessionFileNotFoundWhenJsonlMissing() throws {
        let dir = try makeSessionsDir(
            entries: [
                (key: "agent:main:main", sessionId: "aaaa0001-0000-0000-0000-000000000000", updatedAt: 100),
            ],
            presentSessionIds: [] // no .jsonl file written
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let discovery = SessionDiscovery(path: dir.path)
        #expect(throws: SessionDiscoveryError.self) {
            _ = try discovery.resolveSession(byId: "agent:main:main")
        }
    }
}


// MARK: - relativeTime Tests

@Suite("relativeTime")
struct RelativeTimeTests {

    @Test func justNow() {
        let ms = Int(Date().timeIntervalSince1970 * 1000) - 30_000 // 30 seconds ago
        #expect(relativeTime(fromUnixMs: ms) == "just now")
    }

    @Test func minutesAgo() {
        let ms = Int(Date().timeIntervalSince1970 * 1000) - 5 * 60_000 // 5 minutes ago
        #expect(relativeTime(fromUnixMs: ms) == "5 minutes ago")
    }

    @Test func oneMinuteAgo() {
        let ms = Int(Date().timeIntervalSince1970 * 1000) - 90_000 // 90 seconds ago
        #expect(relativeTime(fromUnixMs: ms) == "1 minute ago")
    }

    @Test func hoursAgo() {
        let ms = Int(Date().timeIntervalSince1970 * 1000) - 3 * 3_600_000 // 3 hours ago
        #expect(relativeTime(fromUnixMs: ms) == "3 hours ago")
    }

    @Test func daysAgo() {
        let ms = Int(Date().timeIntervalSince1970 * 1000) - 2 * 86_400_000 // 2 days ago
        #expect(relativeTime(fromUnixMs: ms) == "2 days ago")
    }

    @Test func weeksAgo() {
        let ms = Int(Date().timeIntervalSince1970 * 1000) - 3 * 7 * 86_400_000 // 3 weeks ago
        #expect(relativeTime(fromUnixMs: ms) == "3 weeks ago")
    }
}


// MARK: - SessionIndex Tests

@Suite("SessionIndex")
struct SessionIndexTests {

    @Test func mostRecentSessionReturnsLatest() throws {
        let json = """
        {
            "session:a": {"sessionId": "aaa", "updatedAt": 100},
            "session:b": {"sessionId": "bbb", "updatedAt": 300},
            "session:c": {"sessionId": "ccc", "updatedAt": 200}
        }
        """
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_sessions_\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let index = try SessionIndex.load(from: tempURL)
        let recent = index.mostRecentSession()
        #expect(recent?.key == "session:b")
        #expect(recent?.entry.sessionId == "bbb")
    }

    @Test func emptyIndexReturnsNil() throws {
        let json = "{}"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_sessions_empty_\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let index = try SessionIndex.load(from: tempURL)
        #expect(index.mostRecentSession() == nil)
    }
}
