import Foundation

enum TokenTool: String, CaseIterable, Sendable {
    case claude = "Claude Code", codex = "Codex", grok = "Grok", openCode = "OpenCode"

    func root(home: URL) -> URL {
        let paths: [Self: String] = [.claude: ".claude/projects", .codex: ".codex/sessions",
            .grok: ".grok/sessions", .openCode: ".local/share/opencode"]
        return home.resolvingSymlinksInPath().appendingPathComponent(paths[self]!)
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

struct TokenRecord {
    typealias Object = [String: Any]
    let key: String
    let date: Date
    let count: Int

    static func decode(_ bytes: Data, tool: TokenTool, previous: inout Int, ordinal: Int) -> Self? {
        if tool == .openCode {
            let fields = TokenOpenCode.parseFields(String(decoding: bytes, as: UTF8.self))
            guard let id = fields["id"] ?? fields["session.id"], let date = date(fields["timestamp"]) else { return nil }
            let keys = ["tokens.input", "tokens.output", "tokens.reasoning", "tokens.cache.read", "tokens.cache.write"]
            let total = keys.reduce(0) { $0 + min(1_000_000_000_000, max(0, Int(fields[$1] ?? "") ?? 0)) }
            return Self(key: id + "/" + (fields["run"] ?? ""), date: date, count: total)
        }
        let needle: String
        switch tool {
        case .claude: needle = "\"usage\""
        case .codex: needle = "\"total_token_usage\""
        case .grok: needle = "\"turn_completed\""
        case .openCode: return nil
        }
        guard bytes.range(of: Data(needle.utf8)) != nil,
              let obj = try? JSONSerialization.jsonObject(with: bytes) as? Object else { return nil }
        switch tool {
        case .claude: return claude(obj)
        case .grok: return grok(obj)
        case .codex:
            guard obj["type"] as? String == "event_msg", let p = obj["payload"] as? Object,
                  p["type"] as? String == "token_count", let info = p["info"] as? Object,
                  let usage = info["total_token_usage"] as? Object, let timestamp = date(obj["timestamp"]) else { return nil }
            let current = number(usage, "input_tokens") + number(usage, "output_tokens")
            let delta = current * 2 < previous ? current : current - previous
            previous = current
            return Self(key: String(ordinal), date: timestamp, count: delta)
        case .openCode: return nil
        }
    }

    private static func number(_ data: Object, _ key: String) -> Int {
        min(1_000_000_000_000, max(0, (data[key] as? NSNumber)?.intValue ?? 0))
    }

    private static func date(_ raw: Any?) -> Date? {
        guard let text = raw as? String else { return nil }
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: text.contains(".")))
    }

    private static func claude(_ data: Object) -> Self? {
        guard data["type"] as? String == "assistant", data["isApiErrorMessage"] as? Bool != true,
              let msg = data["message"] as? Object, let usage = msg["usage"] as? Object,
              let id = msg["id"] as? String, let request = data["requestId"] as? String,
              let timestamp = date(data["timestamp"]) else { return nil }
        let writes = (usage["cache_creation"] as? Object).map {
            number($0, "ephemeral_5m_input_tokens") + number($0, "ephemeral_1h_input_tokens")
        } ?? number(usage, "cache_creation_input_tokens")
        return Self(key: id + "/" + request, date: timestamp, count: writes + number(usage, "input_tokens")
            + number(usage, "cache_read_input_tokens") + number(usage, "output_tokens"))
    }

    private static func grok(_ data: Object) -> Self? {
        guard let params = data["params"] as? Object, let update = params["update"] as? Object,
              update["sessionUpdate"] as? String == "turn_completed", let usage = update["usage"] as? Object else { return nil }
        let meta = data["_meta"] as? Object
        guard let id = (meta?["eventId"] ?? update["prompt_id"]) as? String else { return nil }
        let stamp = (meta?["agentTimestampMs"] as? Double).map { $0 / 1000 }
            ?? (data["timestamp"] as? Double).map { $0 > 1e12 ? $0 / 1000 : $0 }
        guard let stamp else { return nil }
        let models = usage["modelUsage"] as? [String: Object] ?? [:]
        let total = (models.isEmpty ? [usage] : Array(models.values)).reduce(0) {
            $0 + max(number($1, "inputTokens"), number($1, "cachedReadTokens"))
                + number($1, "outputTokens") + number($1, "reasoningTokens")
        }
        return Self(key: id + "/" + (params["sessionId"] as? String ?? ""), date: Date(timeIntervalSince1970: stamp), count: total)
    }
}
