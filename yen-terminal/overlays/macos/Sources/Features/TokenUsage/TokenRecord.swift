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

    /// A line over this size is skipped without being held in memory. Usage records are small: on
    /// 12 GB of real records the largest was 163 KB for Claude Code, whose record carries the reply,
    /// and under 1 KB for Codex and Grok, whose compaction and image records reach many megabytes.
    var recordLimit: Int {
        switch self {
        case .claude, .openCode: return 8 * 1024 * 1024
        case .codex, .grok: return 1024 * 1024
        }
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

/// Numeric projection of local usage records. Source text never enters the index.
struct TokenRecord {
    typealias Object = [String: Any]
    let key: String
    let count: Int
    let output: Int
    let day: Int

    /// The local day an event belongs to, as the epoch second of its midnight.
    static func localDay(_ stamp: Date) -> Int { Int(Calendar.current.startOfDay(for: stamp).timeIntervalSince1970) }

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

    static func decode(_ bytes: Data, tool: TokenTool, day: DateInterval) -> [Self] {
        switch tool {
        case .claude: return claude(bytes, day: day).map { [$0] } ?? []
        case .grok: return grok(bytes, day: day)
        case .openCode: return openCode(bytes, day: day).map { [$0] } ?? []
        case .codex: return []
        }
    }

    /// The members the Claude counter reads; the reply's content is not among them.
    static let claudeMembers = [["type"], ["isApiErrorMessage"], ["requestId"], ["timestamp"],
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
            + number(usage["cache_read_input_tokens"]) + output, output: output, day: localDay(stamp))
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
                        output: output, day: localDay(stamp))
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
            + number(fields["tokens.cache.read"]) + number(fields["tokens.cache.write"]), output: output, day: localDay(stamp))
    }
}
