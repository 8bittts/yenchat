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
        guard bytes.range(of: Data(field.utf8)) != nil else { return nil }
        return try? JSONSerialization.jsonObject(with: bytes) as? Object
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

    private static func claude(_ bytes: Data, day: DateInterval) -> Self? {
        guard let data = object(bytes, containing: "\"usage\""), data["type"] as? String == "assistant",
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
