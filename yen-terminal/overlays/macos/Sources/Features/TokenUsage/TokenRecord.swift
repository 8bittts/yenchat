import Foundation

enum TokenTool: String, CaseIterable, Sendable {
    case claude = "Claude Code", codex = "Codex", grok = "Grok", openCode = "OpenCode"

    func root(home: URL) -> URL {
        if self == .grok, home == FileManager.default.homeDirectoryForCurrentUser,
           let override = ProcessInfo.processInfo.environment["GROK_HOME"], override.hasPrefix("/") {
            return URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent("sessions")
        }
        let paths: [Self: String] = [.claude: ".claude/projects", .codex: ".codex/sessions",
            .grok: ".grok/sessions", .openCode: ".local/share/opencode"]
        return home.appendingPathComponent(paths[self]!)
    }

    /// Text every usage record of this tool contains. The reader parses only the lines that hold it.
    var marker: String? {
        switch self {
        case .claude: return "\"usage\""
        case .codex: return "\"token_count\""
        case .grok: return "\"turn_completed\""
        case .openCode: return nil
        }
    }

    /// Text a line must contain for the reader to parse it. Codex also names its working folder in
    /// its session header and in each turn's context.
    var markers: [String] {
        self == .codex ? TokenCodex.markers : marker.map { [$0] } ?? []
    }

    /// A line over this size is skipped without being held in memory. Usage records are small: in
    /// 6.8 GB of real records the largest was 163 KB for Claude Code, whose record carries the reply,
    /// and under 1 KB for Codex and Grok, whose compaction and image records reach many megabytes.
    var recordLimit: Int {
        switch self {
        case .claude, .openCode: return 8 * 1024 * 1024
        case .codex, .grok: return 1024 * 1024
        }
    }

    /// Grok's shell log, beside its sessions folder: it records each model request as it finishes,
    /// while a session's record counts a turn only once the whole turn completes.
    func grokLog(home: URL) -> URL {
        root(home: home).deletingLastPathComponent().appendingPathComponent("logs/unified.jsonl")
    }

    func accepts(_ url: URL) -> Bool {
        switch self {
        case .claude: return url.pathExtension == "jsonl"
        case .codex: return url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl"
        case .grok: return url.lastPathComponent == "updates.jsonl"
        case .openCode: return url.lastPathComponent == "opencode.log"
        }
    }
}

/// Numeric projection of local usage records. Source text never enters the index; the working
/// folder and session id are kept so usage can be shown per project and per pane.
struct TokenRecord {
    typealias Object = [String: Any]
    let key: String
    let count: Int
    let output: Int
    let day: Int
    var hour = 0
    var project: String?
    var session: String?

    /// What a record file says about every record in it: Grok keeps one folder per working
    /// folder, named by its percent-encoded path, and one folder per session inside it.
    struct Source {
        var project: String?
        var session: String?

        static func of(_ url: URL, tool: TokenTool) -> Self {
            guard tool == .grok else { return Self() }
            let sessionFolder = url.deletingLastPathComponent()
            let decoded = sessionFolder.deletingLastPathComponent().lastPathComponent.removingPercentEncoding
            return Self(project: decoded.flatMap { $0.hasPrefix("/") ? $0 : nil }, session: sessionFolder.lastPathComponent)
        }
    }

    /// The local day an event belongs to, as the epoch second of its midnight.
    static func localDay(_ stamp: Date) -> Int { Int(Calendar.current.startOfDay(for: stamp).timeIntervalSince1970) }

    /// The local hour of the day, 0 to 23, for the hour-by-weekday chart.
    static func localHour(_ stamp: Date) -> Int { Calendar.current.component(.hour, from: stamp) }

    /// A folder path a record names, or nil. Only absolute paths count as a project.
    static func folder(_ raw: Any?) -> String? {
        guard let path = raw as? String, path.hasPrefix("/") else { return nil }
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    static func object(_ bytes: Data, containing field: String) -> Object? {
        guard bytes.withUnsafeBytes({ contains($0, Array(field.utf8)) }) else { return nil }
        return try? JSONSerialization.jsonObject(with: bytes) as? Object
    }

    /// A libc search: `Data.range(of:)` and `Data.firstIndex(of:)` cost several times more per byte,
    /// and the reader runs one of them over every byte of every record file.
    static func contains(_ bytes: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        guard let base = bytes.baseAddress, !needle.isEmpty else { return needle.isEmpty }
        return memmem(base, bytes.count, needle, needle.count) != nil
    }

    static func number(_ raw: Any?) -> Int {
        let value = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init) ?? 0
        return value.isFinite ? Int(min(1_000_000_000_000, max(0, value))) : 0
    }

    static func date(_ raw: Any?) -> Date? {
        guard let text = raw as? String else { return nil }
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: text.contains(".")))
    }

    private static func text(_ raw: Any?) -> String? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        return value
    }

    /// Length-prefix the first component so slashes inside either identifier remain unambiguous.
    static func key(_ first: String, _ second: String) -> String { "\(first.utf8.count):\(first)\(second)" }

    static func decode(_ bytes: Data, tool: TokenTool, day: DateInterval, source: Source = Source()) -> [Self] {
        switch tool {
        case .claude: return claude(bytes, day: day).map { [$0] } ?? []
        case .grok: return grok(bytes, day: day).map { var record = $0; record.project = source.project; record.session = source.session; return record }
        case .openCode: return openCode(bytes, day: day).map { [$0] } ?? []
        case .codex: return []
        }
    }

    /// One finished model request from Grok's shell log, keyed by its session. Its count uses the
    /// same fields as a completed turn, so the requests of a finished turn add up to that turn.
    static func grokRequest(_ bytes: Data, day: DateInterval) -> Self? {
        guard let data = object(bytes, containing: "\"shell.turn.inference_done\""),
              data["msg"] as? String == "shell.turn.inference_done", let session = text(data["sid"]),
              let stamp = date(data["ts"]), stamp >= day.start, stamp < day.end,
              let ctx = data["ctx"] as? Object else { return nil }
        let output = number(ctx["completion_tokens"]) + number(ctx["reasoning_tokens"])
        let loop = (ctx["loop_index"] as? NSNumber).map { String($0.intValue) } ?? ""
        var record = Self(key: key(session, (data["ts"] as? String ?? "") + "#" + loop),
                          count: max(number(ctx["prompt_tokens"]), number(ctx["cached_prompt_tokens"])) + output,
                          output: output, day: localDay(stamp), hour: localHour(stamp))
        record.session = session
        return record
    }

    /// The members the Claude counter reads; the reply's content is not among them.
    static let claudeMembers = [["type"], ["isApiErrorMessage"], ["requestId"], ["timestamp"], ["cwd"], ["sessionId"],
                                ["message", "model"], ["message", "id"], ["message", "usage"]]

    /// A usage record reduced to `claudeMembers`. A record the projection cannot walk is parsed whole.
    static func claudeObject(_ bytes: Data) -> Object? {
        guard let members = bytes.withUnsafeBytes({ TokenRecordProjection.project($0, keeping: claudeMembers) }) else {
            return try? JSONSerialization.jsonObject(with: bytes) as? Object
        }
        return try? JSONSerialization.jsonObject(with: members) as? Object
    }

    private static func claude(_ bytes: Data, day: DateInterval) -> Self? {
        guard let data = claudeObject(bytes), data["type"] as? String == "assistant",
              data["isApiErrorMessage"] as? Bool != true, let msg = data["message"] as? Object,
              text(msg["model"]) != nil, let usage = msg["usage"] as? Object, !usage.isEmpty,
              let id = text(msg["id"]), let request = text(data["requestId"]),
              let stamp = date(data["timestamp"]), stamp >= day.start, stamp < day.end else { return nil }
        let writes = (usage["cache_creation"] as? Object).map {
            number($0["ephemeral_5m_input_tokens"]) + number($0["ephemeral_1h_input_tokens"])
        } ?? number(usage["cache_creation_input_tokens"])
        let output = number(usage["output_tokens"])
        return Self(key: key(id, request), count: writes + number(usage["input_tokens"])
            + number(usage["cache_read_input_tokens"]) + output, output: output, day: localDay(stamp),
            hour: localHour(stamp), project: folder(data["cwd"]), session: text(data["sessionId"]))
    }

    private static func grok(_ bytes: Data, day: DateInterval) -> [Self] {
        guard let data = object(bytes, containing: "\"turn_completed\""),
              let params = data["params"] as? Object, let update = params["update"] as? Object,
              update["sessionUpdate"] as? String == "turn_completed", let usage = update["usage"] as? Object else { return [] }
        let meta = data["_meta"] as? Object
        let prompt = text(update["prompt_id"])
        guard let id = text(meta?["eventId"]) ?? prompt else { return [] }
        let ms = (meta?["agentTimestampMs"] as? NSNumber)?.doubleValue ?? 0
        let raw = (data["timestamp"] as? NSNumber)?.doubleValue ?? 0
        let seconds = ms > 0 ? ms / 1000 : (raw > 1e12 ? raw / 1000 : raw)
        let stamp = Date(timeIntervalSince1970: seconds)
        guard stamp >= day.start, stamp < day.end else { return [] }
        let request = prompt ?? text(params["sessionId"]) ?? id
        func record(_ bag: Object, message: String) -> Self {
            let output = number(bag["outputTokens"]) + number(bag["reasoningTokens"])
            return Self(key: key(message, request), count: max(number(bag["inputTokens"]), number(bag["cachedReadTokens"])) + output,
                        output: output, day: localDay(stamp), hour: localHour(stamp))
        }
        if let models = usage["modelUsage"] as? Object, !models.isEmpty {
            return models.compactMap { name, raw in (raw as? Object).map { record($0, message: key(id, name.isEmpty ? "grok" : name)) } }
        }
        return [record(usage, message: id)]
    }

    private static func openCode(_ bytes: Data, day: DateInterval) -> Self? {
        let fields = TokenOpenCode.parseFields(String(decoding: bytes, as: UTF8.self))
        func field(_ name: String) -> String? {
            guard let value = text(fields[name]), value != "undefined", value != "\"\"" else { return nil }
            return value
        }
        guard let id = field("id") ?? field("session.id"), let stamp = date(field("timestamp")),
              stamp >= day.start, stamp < day.end else { return nil }
        let output = number(fields["tokens.output"]) + number(fields["tokens.reasoning"])
        return Self(key: key(id, field("run") ?? "opencode-log"), count: output + number(fields["tokens.input"])
            + number(fields["tokens.cache.read"]) + number(fields["tokens.cache.write"]), output: output, day: localDay(stamp),
            hour: localHour(stamp))
    }
}
