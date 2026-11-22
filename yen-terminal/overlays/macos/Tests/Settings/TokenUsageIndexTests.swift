import Foundation
import Testing
@testable import YEN

struct TokenUsageIndexTests {
    @Test func largeCompactionBetweenCodexCountsKeepsProviderAvailable() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let root = TokenTool.codex.root(home: home)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date()
        let stamp = now.ISO8601Format()
        func row(_ input: Int) -> String {
            """
            {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input)}}}}
            """
        }
        let compacted = """
            {"timestamp":"\(stamp)","ordinal":42,"type":"compacted","payload":{"message":"\(String(repeating: "x", count: 9 * 1024 * 1024))"}}
            """
        let file = root.appendingPathComponent("rollout-large.jsonl")
        try Data(([row(15), compacted, row(28)].joined(separator: "\n") + "\n").utf8).write(to: file)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        #expect(try index.read(now: now, tools: [.codex])[.codex] == 28)
    }

    @Test func resumedSessionsMatchReferenceProviderTotals() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let instant = Date()
        let stamp = instant.ISO8601Format()
        func write(_ path: String, _ rows: String) throws {
            let file = home.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((rows + "\n").utf8).write(to: file)
        }
        try write(".claude/projects/a.jsonl", """
        {"type":"assistant","timestamp":"\(stamp)","requestId":"r","message":{"id":"a","model":"claude-sonnet","usage":{"input_tokens":100,"output_tokens":1}}}
        {"type":"assistant","timestamp":"\(stamp)","requestId":"r","message":{"id":"a","model":"claude-sonnet","usage":{"input_tokens":5,"output_tokens":9}}}
        {"type":"assistant","timestamp":"\(stamp)","requestId":"","message":{"id":"a","model":"claude-sonnet","usage":{"input_tokens":500,"output_tokens":1}}}
        """)
        try write(".codex/sessions/rollout-example.jsonl", """
        {"type":"event_msg","timestamp":"\(stamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":90,"output_tokens":2}}}}
        {"type":"event_msg","timestamp":"\(stamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":50,"cached_input_tokens":0,"output_tokens":2}}}}
        """)
        try write(".grok/sessions/project/session/updates.jsonl", """
        {"timestamp":\(instant.timeIntervalSince1970),"_meta":{"eventId":"turn"},"params":{"sessionId":"session","update":{"sessionUpdate":"turn_completed","prompt_id":"prompt","usage":{"modelUsage":{"one":{"inputTokens":5,"outputTokens":1}}}}}}
        {"timestamp":\(instant.timeIntervalSince1970),"_meta":{"eventId":"turn"},"params":{"sessionId":"session","update":{"sessionUpdate":"turn_completed","prompt_id":"prompt","usage":{"modelUsage":{"two":{"inputTokens":7,"outputTokens":3}}}}}}
        """)
        try write(".local/share/opencode/log/opencode.log", """
        timestamp=\(stamp) id=undefined session.id=session-1 tokens.input=4.0 tokens.output=1 model=sample
        timestamp=\(stamp) id=undefined session.id=session-2 tokens.input=4.0 tokens.output=1 model=sample
        """)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        let counts = try index.read(now: instant, tools: Set(TokenTool.allCases))
        #expect(counts[.claude] == 14)
        #expect(counts[.codex] == 154)
        #expect(counts[.grok] == 16)
        #expect(counts[.openCode] == 10)
    }

    @Test func todayCountsSurvivePartialLinesReplayAndRotation() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        let tools = Set(TokenTool.allCases)
        let instant = Date()
        let timestamp = instant.ISO8601Format()
        let roots = tools.map { $0.root(home: home) }
        for root in roots { try fm.createDirectory(at: root, withIntermediateDirectories: true) }
        let claude = TokenTool.claude.root(home: home).appendingPathComponent("a.jsonl")
        let first = """
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"r","message":{"id":"a","model":"claude-sonnet","usage":{"input_tokens":12,"output_tokens":4,"cache_read_input_tokens":5,"cache_creation_input_tokens":6}}}
        """
        try Data((first + "\n" + first + "\n" + first.replacingOccurrences(of: "\"a\"", with: "\"b\"")).utf8).write(to: claude)
        let codex = TokenTool.codex.root(home: home).appendingPathComponent("rollout-test.jsonl")
        func cumulative(_ n: Int) -> String {
            """
            {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(n),"cached_input_tokens":7,"output_tokens":3,"reasoning_output_tokens":2}}}}
            """
        }
        try Data(([100,100,110,105,9].map(cumulative).joined(separator: "\n") + "\n").utf8).write(to: codex)
        let grok = TokenTool.grok.root(home: home).appendingPathComponent("updates.jsonl")
        let turn = """
        {"_meta":{"agentTimestampMs":\(Int(instant.timeIntervalSince1970 * 1000)),"eventId":"x"},"params":{"update":{"sessionUpdate":"turn_completed","usage":{"modelUsage":{"one":{"inputTokens":12,"cachedReadTokens":4,"outputTokens":8,"reasoningTokens":1}}}}}}
        """
        try Data((turn + "\n" + turn + "\n").utf8).write(to: grok)
        let counts = try index.read(now: instant, tools: tools)
        #expect(counts == [.claude: 27, .codex: 120, .grok: 21])
        let append = try FileHandle(forWritingTo: claude)
        try append.seekToEnd()
        try append.write(contentsOf: Data([10]))
        try append.close()
        #expect(try index.read(now: instant, tools: [.claude], changes: [.claude: [claude]])[.claude] == 54)
        try Data((first + "\n").utf8).write(to: claude, options: .atomic)
        #expect(try index.read(now: instant, tools: [.claude])[.claude] == 27)
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: instant))
        #expect(try index.read(now: tomorrow, tools: [.claude])[.claude] == 0)
    }

    @Test func codexCorrectionsStayInTheirRolloutAndRespectMidnight() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let root = TokenTool.codex.root(home: home)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date(), yesterday = Calendar.current.startOfDay(for: now).addingTimeInterval(-1)
        func row(_ input: Int, _ cached: Int, _ date: Date) -> String {
            """
            {"type":"event_msg","timestamp":"\(date.ISO8601Format())","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached)}}}}
            """ + "\n"
        }
        let uuid = UUID().uuidString
        let original = root.appendingPathComponent("rollout-a-\(uuid).jsonl")
        let replay = root.appendingPathComponent("rollout-b-\(uuid).jsonl")
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        let prefix = row(100, 10, yesterday) + row(110, 10, now)
        try Data(prefix.utf8).write(to: original)
        #expect(try index.read(now: now, tools: [.codex])[.codex] == 10)
        let correction = row(100, 15, now)
        let handle = try FileHandle(forWritingTo: original)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(correction.utf8))
        try handle.close()
        // Remove today's ten uncached tokens, then add five cached tokens.
        #expect(try index.read(now: now, tools: [.codex])[.codex] == 5)
        try Data(("{}\n" + prefix + correction).utf8).write(to: replay)
        #expect(try index.read(now: now, tools: [.codex])[.codex] == 5)
        try fm.removeItem(at: original)
        try fm.removeItem(at: replay)
        #expect(try index.read(now: now, tools: [.codex])[.codex] == 0)
    }

    @MainActor @Test func observesAppendsThroughAnAliasedProviderDirectory() async throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let real = home.appendingPathComponent("logs")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        let root = TokenTool.claude.root(home: home)
        try fm.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root, withDestinationURL: real)
        let file = root.appendingPathComponent("session.jsonl")
        var observed = false
        let watcher = try #require(TokenSourceWatcher(home: home) { tool, paths in
            if tool == .claude && paths?.contains(where: { $0.lastPathComponent == file.lastPathComponent }) == true {
                observed = true
            }
        })
        defer { watcher.stop() }
        try Data("record\n".utf8).write(to: file)
        for _ in 0..<100 where !observed { try await Task.sleep(for: .milliseconds(100)) }
        #expect(observed)
    }

    @Test func openCodeUsesSessionCountersOnlyWhenMessageHistoryHasNoUsage() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let root = TokenTool.openCode.root(home: home)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: root.appendingPathComponent("opencode.db").path)
        let now = Date()
        let today = Int(now.timeIntervalSince1970 * 1000)
        let yesterday = Int(Calendar.current.startOfDay(for: now).timeIntervalSince1970 * 1000) - 1
        try db.execute("""
            CREATE TABLE message(id TEXT,session_id TEXT,data TEXT);
            CREATE TABLE session(time_created INTEGER,tokens_input INTEGER,tokens_output INTEGER,
                tokens_reasoning INTEGER,tokens_cache_read INTEGER,tokens_cache_write INTEGER);
            INSERT INTO session VALUES(\(today),100,25,3,10,4);
            """)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        func count() throws -> Int? { try index.read(now: now, tools: [.openCode])[.openCode] }
        #expect(try count() == 142)
        try db.execute("""
            INSERT INTO message VALUES('old','s','{"role":"assistant","time":{"created":\(yesterday)},"tokens":{"input":8}}');
            """)
        #expect(try count() == 0)
        try db.execute("""
            INSERT INTO message VALUES('new','s','{"role":"assistant","time":{"created":\(today)},"tokens":{"output":5}}');
            """)
        #expect(try count() == 5)
    }

    @Test func openCodeMigrationCountsARecordOnceAcrossGateways() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let root = TokenTool.openCode.root(home: home)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("opencode.db")
        let db = try SQLiteDatabase(path: url.path)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        try db.execute("""
            CREATE TABLE message(id TEXT,session_id TEXT,data TEXT);
            CREATE TABLE session_message(id TEXT,session_id TEXT,type TEXT,data TEXT);
            INSERT INTO message VALUES('x','s','{"role":"assistant","time":{"created":\(stamp)},"tokens":{"input":100}}');
            INSERT INTO session_message VALUES('x','s','assistant','{"time":{"created":\(stamp)},"tokens":{"input":10,"output":4,"cache":{"read":2}}}');
            INSERT INTO message VALUES('y','s','{"role":"assistant","time":{"created":\(stamp)},"tokens":{"input":3}}');
            """)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        #expect(try index.read(tools: [.openCode])[.openCode] == 19)
        try db.execute("DROP TABLE message; DROP TABLE session_message")
        #expect(try index.read(tools: [.openCode])[.openCode] == nil)
    }
}
