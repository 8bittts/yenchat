import Foundation
import Testing
@testable import YEN

struct TokenUsageIndexTests {
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
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"r","message":{"id":"a","usage":{"input_tokens":12,"output_tokens":4,"cache_read_input_tokens":5,"cache_creation_input_tokens":6}}}
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
