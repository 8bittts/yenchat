import Foundation
import Testing
@testable import YEN

/// Per-folder counts, today's hours, Grok turns still running and the weekday-hour chart.
struct TokenProjectUsageTests {
    private let fm = FileManager.default

    private func makeHome() throws -> URL {
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func write(_ lines: [String], to file: URL) throws {
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)
    }

    private func claude(_ id: String, input: Int, cwd: String, at stamp: Date) -> String {
        """
        {"type":"assistant","timestamp":"\(stamp.ISO8601Format())","cwd":"\(cwd)","sessionId":"s","requestId":"r\(id)","message":{"id":"m\(id)","model":"claude-sonnet","usage":{"input_tokens":\(input),"output_tokens":1}}}
        """
    }

    private func grokTurn(_ id: String, input: Int, at stamp: Date) -> String {
        """
        {"_meta":{"agentTimestampMs":\(Int(stamp.timeIntervalSince1970 * 1000)),"eventId":"\(id)"},"params":{"update":{"sessionUpdate":"turn_completed","usage":{"modelUsage":{"one":{"inputTokens":\(input),"outputTokens":1}}}}}}
        """
    }

    private func grokRequest(_ session: String, loop: Int, prompt: Int, at stamp: Date) -> String {
        """
        {"ts":"\(stamp.ISO8601Format())","src":"shell","sid":"\(session)","msg":"shell.turn.inference_done","ctx":{"loop_index":\(loop),"prompt_tokens":\(prompt),"cached_prompt_tokens":0,"completion_tokens":1,"reasoning_tokens":0}}
        """
    }

    @Test func eachToolsUsageLandsOnItsWorkingFolder() throws {
        let home = try makeHome()
        defer { try? fm.removeItem(at: home) }
        let now = Date()
        try write([claude("1", input: 10, cwd: "/Users/dev/app", at: now), claude("2", input: 20, cwd: "/Users/dev/site/", at: now)],
                  to: TokenTool.claude.root(home: home).appendingPathComponent("-Users-dev-app/one.jsonl"))
        let stamp = now.ISO8601Format()
        try write([
            #"{"timestamp":"\#(stamp)","type":"session_meta","payload":{"cwd":"/Users/dev/app","base_instructions":"x"}}"#,
            #"{"timestamp":"\#(stamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":5}}}}"#,
            #"{"timestamp":"\#(stamp)","type":"turn_context","payload":{"cwd":"/Users/dev/tool"}}"#,
            #"{"timestamp":"\#(stamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":12}}}}"#,
        ], to: TokenTool.codex.root(home: home).appendingPathComponent("2026/11/23/rollout-a.jsonl"))
        try write([grokTurn("a", input: 6, at: now)],
                  to: TokenTool.grok.root(home: home).appendingPathComponent("%2FUsers%2Fdev%2Fapp/sess/updates.jsonl"))
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        let counts = try index.read(now: now, tools: [.claude, .codex, .grok])
        #expect(counts[.claude] == 32 && counts[.codex] == 12 && counts[.grok] == 7)
        let projects = try index.projects()
        #expect(projects["/Users/dev/app"] == [.claude: 11, .codex: 5, .grok: 7])
        #expect(projects["/Users/dev/site"] == [.claude: 21])
        #expect(projects["/Users/dev/tool"] == [.codex: 7])
        #expect(try index.hours()[TokenRecord.localHour(now)] == 51)
    }

    @Test func grokRequestsCountOnlyTheTurnStillRunning() throws {
        let home = try makeHome()
        defer { try? fm.removeItem(at: home) }
        let now = Date()
        let session = TokenTool.grok.root(home: home).appendingPathComponent("%2FUsers%2Fdev%2Fapp/s1/updates.jsonl")
        // The finished turn made two requests that add up to it; a second turn has made one so far.
        try write([grokTurn("t1", input: 30, at: now)], to: session)
        let log = TokenTool.grok.grokLog(home: home)
        try write([grokRequest("s1", loop: 0, prompt: 10, at: now), grokRequest("s1", loop: 1, prompt: 19, at: now),
                   grokRequest("s1", loop: 2, prompt: 40, at: now)], to: log)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        #expect(try index.read(now: now, tools: [.grok])[.grok] == 31 + 41)
        #expect(try index.projects()["/Users/dev/app"] == [.grok: 72])

        // The turn completes: its record now holds what the request log held, so nothing is counted twice.
        try write([grokTurn("t1", input: 30, at: now), grokTurn("t2", input: 40, at: now)], to: session)
        #expect(try index.read(now: now, tools: [.grok], changes: [.grok: [session]])[.grok] == 72)

        // A session that has not completed a turn yet still finds its folder.
        try write([grokRequest("s1", loop: 0, prompt: 10, at: now), grokRequest("s1", loop: 1, prompt: 19, at: now),
                   grokRequest("s1", loop: 2, prompt: 40, at: now), grokRequest("s2", loop: 0, prompt: 99, at: now)], to: log)
        try fm.createDirectory(at: TokenTool.grok.root(home: home).appendingPathComponent("%2FUsers%2Fdev%2Fother/s2"),
                               withIntermediateDirectories: true)
        #expect(try index.read(now: now, tools: [.grok], changes: [.grok: [log]])[.grok] == 172)
        #expect(try index.projects()["/Users/dev/other"] == [.grok: 100])
    }

    @Test func finishedDaysKeepTheirHoursForTheWeekdayChart() throws {
        let home = try makeHome()
        defer { try? fm.removeItem(at: home) }
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let earlier = try #require(calendar.date(byAdding: .hour, value: 14, to: calendar.date(byAdding: .day, value: -3, to: today)!))
        try write([claude("old", input: 99, cwd: "/Users/dev/app", at: earlier), claude("new", input: 9, cwd: "/Users/dev/app", at: now)],
                  to: TokenTool.claude.root(home: home).appendingPathComponent("p/one.jsonl"))
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        _ = try index.read(now: now, tools: Set(TokenTool.allCases))
        let history = try index.history(now: now)
        #expect(history[.claude]?.reduce(0, +) == 100)
        let bins = try index.rhythm(now: now)
        #expect(bins.count == 168)
        let weekday = calendar.component(.weekday, from: earlier)
        #expect(bins[(weekday - 1) * 24 + 14] == 100)
        let todayBin = (calendar.component(.weekday, from: now) - 1) * 24 + calendar.component(.hour, from: now)
        #expect(bins[todayBin] >= 10)
        #expect(bins.reduce(0, +) == 110)
    }

    @Test func openCodeUsageLandsOnItsSessionFolder() throws {
        let home = try makeHome()
        defer { try? fm.removeItem(at: home) }
        let root = TokenTool.openCode.root(home: home)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let db = try SQLiteDatabase(path: root.appendingPathComponent("opencode.db").path)
        let now = Date()
        let stamp = Int(now.timeIntervalSince1970 * 1000)
        try db.execute("""
            CREATE TABLE session(id TEXT PRIMARY KEY,directory TEXT);
            CREATE TABLE session_v2(id TEXT PRIMARY KEY,directory TEXT);
            CREATE TABLE session_message(id TEXT,session_id TEXT,type TEXT,data TEXT);
            INSERT INTO session VALUES('a','/Users/dev/app');
            INSERT INTO session_v2 VALUES('b','/Users/dev/site');
            INSERT INTO session_message VALUES('1','a','assistant','{"time":{"created":\(stamp)},"tokens":{"input":7}}');
            INSERT INTO session_message VALUES('2','b','assistant','{"time":{"created":\(stamp)},"tokens":{"output":3}}');
            INSERT INTO session_message VALUES('3','gone','assistant','{"time":{"created":\(stamp)},"tokens":{"input":1}}');
            """)
        let index = TokenUsageIndex(home: home, directory: home.appendingPathComponent("cache"))
        #expect(try index.read(now: now, tools: [.openCode])[.openCode] == 11)
        let projects = try index.projects()
        #expect(projects["/Users/dev/app"] == [.openCode: 7])
        #expect(projects["/Users/dev/site"] == [.openCode: 3])
        #expect(projects.count == 2)
        #expect(try index.hours()[TokenRecord.localHour(now)] == 11)
    }

    @Test func aTabFindsItsFolderOrTheNearestOneAbove() {
        let projects: [String: TokenUsageIndex.Counts] = ["/Users/dev/app": [.claude: 100], "/Users/dev/app/web": [.codex: 5],
                                                          "/Users/dev/apple": [.grok: 1]]
        #expect(TokenProjectUsage.tokens(forDirectory: "/Users/dev/app", in: projects) == 105)
        #expect(TokenProjectUsage.tokens(forDirectory: "/Users/dev/app/", in: projects) == 105)
        #expect(TokenProjectUsage.tokens(forDirectory: "/Users/dev/app/src/lib", in: projects) == 100)
        #expect(TokenProjectUsage.tokens(forDirectory: "/Users/dev/app/web", in: projects) == 5)
        #expect(TokenProjectUsage.tokens(forDirectory: "/Users/dev/other", in: projects) == nil)
        #expect(TokenProjectUsage.tokens(forDirectory: "relative", in: projects) == nil)
    }

    @Test func theReportCarriesNumbersFoldersAndCurrentLimitsOnly() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let current = TokenPlanMeter("Weekly", percent: NSNumber(value: 64), reset: now.addingTimeInterval(3600))!
        let expired = TokenPlanMeter("5-hour", percent: NSNumber(value: 90), reset: now.addingTimeInterval(-60))!
        let report = TokenUsageReport.make(counts: [.claude: 100, .codex: 5], plans: [.claude: [current, expired]],
                                           projects: ["/b": [.claude: 1], "/a": [.claude: 99, .codex: 5]], now: now)
        #expect(report.total == 105 && report.sources == 2)
        #expect(report.folders.map(\.path) == ["/a", "/b"])
        #expect(report.tools.first?.limits.map(\.label) == ["Weekly"])
        let url = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("usage.json")
        defer { try? fm.removeItem(at: url.deletingLastPathComponent()) }
        try TokenUsageReport.write(report, to: url)
        let attributes = try fm.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(TokenUsageReport.Report.self, from: Data(contentsOf: url)).folders == report.folders)
        TokenUsageReport.remove(at: url)
        #expect(!fm.fileExists(atPath: url.path))
    }

    @Test func busiestHourAndWeekdayOrderFollowTheCalendar() {
        var bins = Array(repeating: 0, count: 168)
        bins[2 * 24 + 15] = 7
        let busiest = TokenRhythmChart.busiest(bins)
        #expect(busiest?.weekday == 3 && busiest?.hour == 15)
        #expect(TokenRhythmChart.busiest(Array(repeating: 0, count: 168)) == nil)
        var monday = Calendar(identifier: .gregorian)
        monday.firstWeekday = 2
        #expect(TokenRhythmChart.weekdays(monday) == [2, 3, 4, 5, 6, 7, 1])
    }
}
