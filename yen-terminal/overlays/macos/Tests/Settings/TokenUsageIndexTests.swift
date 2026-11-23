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

    @Test func oversizedImageRecordBetweenGrokTurnsKeepsProviderAvailable() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let file = TokenTool.grok.root(home: home).appendingPathComponent("project/session/updates.jsonl")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let now = Date()
        func turn(_ id: String, _ input: Int) -> String {
            """
            {"_meta":{"agentTimestampMs":\(Int(now.timeIntervalSince1970 * 1000)),"eventId":"\(id)"},"params":{"update":{"sessionUpdate":"turn_completed","usage":{"modelUsage":{"one":{"inputTokens":\(input),"outputTokens":1}}}}}}
            """
        }
        // Grok Build stores a pasted image as one record; real ones exceed 14 MB.
        let image = """
            {"params":{"update":{"sessionUpdate":"user_message_chunk","content":{"type":"image","data":"\(String(repeating: "x", count: 9 * 1024 * 1024))"}}}}
            """
        try Data(([turn("a", 5), image, turn("b", 7)].joined(separator: "\n") + "\n").utf8).write(to: file)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        #expect(try index.read(now: now, tools: [.grok])[.grok] == 14)
    }

    @Test func recordsThatCrossReadBuffersAreEachCountedOnce() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let file = TokenTool.claude.root(home: home).appendingPathComponent("project/session.jsonl")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let now = Date()
        let stamp = now.ISO8601Format()
        // 40 replies of about 300 KB end at many offsets inside the reader's buffer, and a line
        // without usage sits between each pair.
        let reply = String(repeating: "word \\\" } ] ", count: 25_000)
        var rows: [String] = []
        for turn in 1...40 {
            rows.append("""
                {"type":"assistant","timestamp":"\(stamp)","requestId":"r\(turn)","message":{"id":"m\(turn)","model":"claude-sonnet","content":[{"type":"text","text":"\(reply)"}],"usage":{"input_tokens":\(turn),"output_tokens":1}}}
                """)
            rows.append(#"{"type":"user","message":{"content":"\#(String(repeating: "y", count: turn * 4_099))"}}"#)
        }
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: file)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        #expect(try index.read(now: now, tools: [.claude])[.claude] == (1...40).reduce(0, +) + 40)
    }

    @Test func recordLimitFollowsTheTool() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let now = Date()
        let stamp = now.ISO8601Format()
        let twoMegabytes = String(repeating: "x", count: 2 * 1024 * 1024)
        #expect(TokenTool.grok.recordLimit < twoMegabytes.utf8.count)
        #expect(TokenTool.claude.recordLimit > twoMegabytes.utf8.count)

        // Grok's usage records are under 1 KB, so a 2 MB line is never one and is not counted.
        let grok = TokenTool.grok.root(home: home).appendingPathComponent("project/session/updates.jsonl")
        try fm.createDirectory(at: grok.deletingLastPathComponent(), withIntermediateDirectories: true)
        func turn(_ id: String, _ input: Int, padding: String = "") -> String {
            """
            {"_meta":{"agentTimestampMs":\(Int(now.timeIntervalSince1970 * 1000)),"eventId":"\(id)"},"padding":"\(padding)","params":{"update":{"sessionUpdate":"turn_completed","usage":{"modelUsage":{"one":{"inputTokens":\(input),"outputTokens":1}}}}}}
            """
        }
        try Data(([turn("a", 5), turn("large", 100, padding: twoMegabytes), turn("b", 7)].joined(separator: "\n") + "\n").utf8)
            .write(to: grok)

        // A Claude Code record carries the reply, so the same size is still a usage record.
        let claude = TokenTool.claude.root(home: home).appendingPathComponent("project/session.jsonl")
        try fm.createDirectory(at: claude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
            {"type":"assistant","timestamp":"\(stamp)","requestId":"r","message":{"id":"m","model":"claude-sonnet","content":[{"type":"text","text":"\(twoMegabytes)"}],"usage":{"input_tokens":30,"output_tokens":3}}}

            """.utf8).write(to: claude)

        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        let counts = try index.read(now: now, tools: [.grok, .claude])
        #expect(counts[.grok] == 14)
        #expect(counts[.claude] == 33)
    }

    @Test func projectionKeepsExactlyTheRequestedMembers() throws {
        // Skipped values hold every character that could end a value early, and one key is spelled
        // with an escape: keys are compared as written, so it is not matched.
        let record = #"""
             { "skipped" : {"text":"} ] \" , {","list":[1,[2,{"a":"]"}]]}, "kept\u0041" : 1,
              "title":"quote \" slash \\","number":-1.5e3,"flag":true,"nothing":null ,
              "message":{"content":[{"text":"\"usage\":{\"input_tokens\":9}"}],"id":"m\\",
                         "usage":{"input_tokens":3,"cache_creation":{"ephemeral_1h_input_tokens":2}}},
              "list":[{"usage":1}], "empty":{} }
            """#
        let paths = [["title"], ["number"], ["flag"], ["nothing"], ["message", "id"], ["message", "usage"],
                     ["list"], ["empty", "inside"], ["absent"], ["keptA"]]
        let projected = try #require(Data(record.utf8).withUnsafeBytes { TokenRecordProjection.project($0, keeping: paths) })
        let whole = try #require(try JSONSerialization.jsonObject(with: Data(record.utf8)) as? NSDictionary)
        let message = try #require(whole["message"] as? NSDictionary)
        let expected: NSDictionary = [
            "title": try #require(whole["title"]), "number": try #require(whole["number"]),
            "flag": try #require(whole["flag"]), "nothing": NSNull(),
            "message": ["id": try #require(message["id"]), "usage": try #require(message["usage"])] as NSDictionary,
            "list": try #require(whole["list"]), "empty": NSDictionary(),
        ]
        #expect(try JSONSerialization.jsonObject(with: projected) as? NSDictionary == expected)
        // The reply's content never enters the projection.
        #expect(!String(decoding: projected, as: UTF8.self).contains("content"))
    }

    @Test func projectionRefusesARecordItCannotWalk() {
        func project(_ text: String) -> Data? {
            Data(text.utf8).withUnsafeBytes { TokenRecordProjection.project($0, keeping: [["a"]]) }
        }
        #expect(project(#"{"a":1}"#) != nil)
        for broken in [#"[{"a":1}]"#, #"{"a":1"#, #"{"a":"unfinished}"#, #"{"a":{"b":[1,2}"#, #"{"a":1} trailing"#,
                       #"{"a" 1}"#, #"{a:1}"#, "", "   "] {
            #expect(project(broken) == nil, "\(broken)")
        }
    }

    @Test func claudeRecordsCountTheSameWhateverSurroundsTheirUsage() throws {
        let stamp = Date().ISO8601Format()
        let day = try #require(Calendar.current.dateInterval(of: .day, for: Date()))
        func count(_ line: String) -> Int? { TokenRecord.decode(Data(line.utf8), tool: .claude, day: day).first?.count }
        let usage = #""usage":{"input_tokens":4,"cache_read_input_tokens":2,"cache_creation":{"ephemeral_5m_input_tokens":1,"ephemeral_1h_input_tokens":1},"output_tokens":3}"#
        let plain = #"{"type":"assistant","timestamp":"\#(stamp)","requestId":"r","message":{"id":"m","model":"claude-sonnet",\#(usage)}}"#
        #expect(count(plain) == 11)
        // Members in another order, spaces between tokens, and a reply that quotes a usage object.
        let reordered = #"{ "message" : {\#(usage), "content":[{"type":"text","text":"\"usage\":{\"input_tokens\":900} }]"}], "model":"claude-sonnet", "id":"m"} , "requestId":"r", "timestamp":"\#(stamp)", "type":"assistant" }"#
        #expect(count(reordered) == 11)
        // A user record that quotes usage, an API error and a record without a request are not counted.
        #expect(count(#"{"type":"user","timestamp":"\#(stamp)","requestId":"r","message":{"id":"m","model":"x",\#(usage)}}"#) == nil)
        #expect(count(#"{"type":"assistant","isApiErrorMessage":true,"timestamp":"\#(stamp)","requestId":"r","message":{"id":"m","model":"x",\#(usage)}}"#) == nil)
        #expect(count(#"{"type":"assistant","timestamp":"\#(stamp)","message":{"id":"m","model":"x",\#(usage)}}"#) == nil)
        // A record cut short is not a record.
        #expect(count(String(plain.dropLast(2))) == nil)
    }

    @Test func markerSearchFindsTextAnywhereInARecord() {
        func contains(_ text: String, _ needle: String) -> Bool {
            Data(text.utf8).withUnsafeBytes { TokenRecord.contains($0, Array(needle.utf8)) }
        }
        #expect(contains(#""usage" at the start"#, #""usage""#))
        #expect(contains(#"at the end "usage""#, #""usage""#))
        #expect(contains(String(repeating: "\"usag", count: 500) + "\"usage\"" + "tail", #""usage""#))
        #expect(!contains(#""usag" "usage "usag\e""#, #""usage""#))
        #expect(!contains("", #""usage""#))
    }

    @Test func codexLimitsSurviveADayWithoutCodexActivity() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let root = TokenTool.codex.root(home: home)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date(), lastNight = Calendar.current.startOfDay(for: now).addingTimeInterval(-3600)
        let file = root.appendingPathComponent("rollout-last-night.jsonl")
        // The weekly window outlives the day that reported it.
        let row = """
            {"type":"event_msg","timestamp":"\(lastNight.ISO8601Format())","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100}},"rate_limits":{"limit_id":"codex","primary":{"window_minutes":10080,"used_percent":40,"resets_at":\(Int(now.timeIntervalSince1970) + 86400)}}}}
            """
        try Data((row + "\n").utf8).write(to: file)
        try fm.setAttributes([.modificationDate: lastNight], ofItemAtPath: file.path)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        #expect(try index.read(now: now, tools: [.codex])[.codex] == 0)
        let meters = try index.latestCodexPlan()
        #expect(meters.map(\.label) == ["Weekly"])
        #expect(meters.map(\.percent) == [40])
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

    @Test func historyCountsEachFinishedDayOnceAndKeepsItAfterTheSourceIsGone() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let calendar = Calendar.current, now = Date(), today = calendar.startOfDay(for: now)
        func at(_ daysAgo: Int) -> Date { calendar.date(byAdding: .day, value: -daysAgo, to: today)!.addingTimeInterval(3600) }
        func write(_ path: String, _ rows: [String]) throws {
            let file = home.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: file)
        }
        func claude(_ id: String, _ date: Date, input: Int, output: Int) -> String {
            """
            {"type":"assistant","timestamp":"\(date.ISO8601Format())","requestId":"r","message":{"id":"\(id)","model":"claude-sonnet","usage":{"input_tokens":\(input),"output_tokens":\(output)}}}
            """
        }
        func codex(_ total: Int, _ date: Date) -> String {
            """
            {"type":"event_msg","timestamp":"\(date.ISO8601Format())","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(total)}}}}
            """
        }
        try write(".claude/projects/a.jsonl", [claude("old", at(3), input: 20, output: 1), claude("new", at(1), input: 10, output: 2),
                                               claude("today", now, input: 100, output: 1)])
        // A resumed session logs the same request again; the fuller copy is the one counted.
        try write(".claude/projects/b.jsonl", [claude("old", at(3), input: 5, output: 0)])
        try write(".codex/sessions/rollout-history.jsonl", [codex(100, at(2)), codex(150, at(1))])
        let store = TokenTool.openCode.root(home: home)
        try fm.createDirectory(at: store, withIntermediateDirectories: true)
        try SQLiteDatabase(path: store.appendingPathComponent("opencode.db").path).execute("""
            CREATE TABLE message(id TEXT,session_id TEXT,data TEXT);
            INSERT INTO message VALUES('m','s','{"role":"assistant","time":{"created":\(Int(at(1).timeIntervalSince1970 * 1000))},"tokens":{"input":7}}');
            """)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        let history = try index.history(now: now)
        #expect(history[.claude]?.count == TokenUsageIndex.historyDays)
        #expect(history[.claude]?.suffix(3) == [21, 0, 12])
        #expect(history[.codex]?.suffix(3) == [0, 100, 50])
        #expect(history[.openCode]?.suffix(2) == [0, 7])
        // Grok has no records here, so it has no entry instead of a row of zeros.
        #expect(history[.grok] == nil)
        try fm.removeItem(at: home.appendingPathComponent(".claude"))
        #expect(try index.history(now: now)[.claude]?.suffix(3) == [21, 0, 12])
    }

    @MainActor @Test func observesAndCountsAppendsThroughAnAliasedProviderDirectory() async throws {
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
        let now = Date()
        let row = """
            {"type":"assistant","timestamp":"\(now.ISO8601Format())","requestId":"r","message":{"id":"a","model":"claude-sonnet","usage":{"input_tokens":3,"output_tokens":2}}}
            """
        try Data((row + "\n").utf8).write(to: file)
        for _ in 0..<100 where !observed { try await Task.sleep(for: .milliseconds(100)) }
        #expect(observed)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        #expect(try index.read(now: now, tools: [.claude])[.claude] == 5)
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

    /// Two reads of one index can overlap in the shipped menu: switching the
    /// menu off and on while a read runs starts a new read before the
    /// cancelled one has stopped. Neither may fail with "database is locked",
    /// including the first reads of a new index, which create its tables.
    @Test func overlappingReadsOfOneIndexAllSucceed() async throws {
        let fm = FileManager.default
        let line = """
            {"type":"assistant","timestamp":"\(Date().ISO8601Format())","requestId":"r","message":{"id":"m","model":"claude-sonnet","usage":{"input_tokens":4,"output_tokens":1}}}

            """
        var failures: [String] = []
        for _ in 0..<40 {
            let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at: home) }
            let file = TokenTool.claude.root(home: home).appendingPathComponent("project/session.jsonl")
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(line.utf8).write(to: file)
            let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
            let reads = (0..<4).map { _ in
                Task.detached { () -> String? in
                    do {
                        let counts = try index.read(tools: [.claude])
                        return counts[.claude] == 5 ? nil : "counted \(String(describing: counts[.claude]))"
                    } catch {
                        return "\(error)"
                    }
                }
            }
            for read in reads {
                if let failure = await read.value { failures.append(failure) }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) of 160 reads failed: \(Set(failures))")
    }
}
