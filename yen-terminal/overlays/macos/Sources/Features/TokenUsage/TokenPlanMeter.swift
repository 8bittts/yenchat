import Foundation

/// Provider percentages have independent denominators. They never enter the daily token sum.
struct TokenPlanMeter: Codable, Equatable, Sendable, Identifiable {
    let label: String
    let percent: Double
    let reset: Date?
    var id: String { label }

    init?(_ label: String, percent: Any?, reset: Date?) {
        guard let value = percent as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        self.label = label
        // A pool past its included limit still fills its bar.
        self.percent = min(100, max(0, value.doubleValue))
        self.reset = reset
    }

    func isCurrent(at now: Date) -> Bool { reset.map { $0 > now } ?? true }
}

struct TokenPlanReading: Codable, Sendable {
    let date: Date
    let meters: [TokenPlanMeter]

    static func codex(_ raw: TokenRecord.Object, at date: Date) -> Self? {
        if let id = raw["limit_id"] as? String, id != "codex" { return nil }
        let meters = ["primary", "secondary"].compactMap { key -> TokenPlanMeter? in
            guard let row = raw[key] as? TokenRecord.Object, let minutes = (row["window_minutes"] as? NSNumber)?.doubleValue,
                  let end = row["resets_at"] as? Double, [300, 10080].contains(minutes) else { return nil }
            return TokenPlanMeter(minutes == 300 ? "5-hour" : "Weekly", percent: row["used_percent"],
                                  reset: Date(timeIntervalSince1970: end))
        }
        return meters.isEmpty ? nil : Self(date: date, meters: meters)
    }

    func isRollingPlaceholder(after previous: Self?) -> Bool {
        guard let previous, meters.count == 1, previous.meters.count == 1,
              let a = meters.first, let b = previous.meters.first, a.label == "Weekly", b.label == a.label,
              a.percent == 0, b.percent == 0, let end = a.reset, let old = b.reset else { return false }
        let elapsed = date.timeIntervalSince(previous.date)
        return elapsed > 0 && abs(end.timeIntervalSince(old) - elapsed) <= 2
    }
}

enum TokenLocalPlans {
    /// An existing JPtheCat opt-in can supply the same pools before a YEN connection is configured.
    static func sharedCursorPools(home: URL, now: Date) -> [TokenPlanMeter] {
        let root = home.appendingPathComponent("Library/Application Support/JPtheCat")
        let markers = ["grok-plan-usage.enabled", "cursor-plan-usage.enabled", "grok-bot-plan-usage.enabled"]
        guard markers.contains(where: { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }),
              let bytes = try? Data(contentsOf: root.appendingPathComponent("grok-plan-usage.json")),
              let obj = try? JSONSerialization.jsonObject(with: bytes) as? TokenRecord.Object,
              let stamp = obj["fetchedAt"] as? Double,
              let rows = obj["meters"] as? [TokenRecord.Object] else { return [] }
        let labels = ["cursor_models": "Cursor models", "other_models": "Cursor other models",
                      "all_models": "Cursor all models", "included_usage": "Cursor included", "grok_bot_weekly": "Grok Bot weekly"]
        return rows.compactMap { row in
            guard let key = row["key"] as? String, let label = labels[key] else { return nil }
            let end = (row["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
            guard end.map({ $0 > now }) ?? (0...3600).contains(now.timeIntervalSince1970 - stamp) else { return nil }
            return TokenPlanMeter(label, percent: row["usedPercent"], reset: end)
        }
    }

    static func openCodeWorkspace(home: URL) -> String? {
        let log = TokenTool.openCode.root(home: home).appendingPathComponent("log/opencode.log")
        guard let file = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd() else { return nil }
        let length = min(size, 1_048_576)
        guard (try? file.seek(toOffset: size - length)) != nil, let data = try? file.read(upToCount: Int(length)),
              let marker = data.range(of: Data("opencode.ai/workspace/".utf8), options: .backwards),
              data.count - marker.upperBound >= 30 else { return nil }
        let id = String(decoding: data[marker.upperBound...].prefix(30), as: UTF8.self)
        guard id.range(of: #"^wrk_[A-Z0-9]{26}$"#, options: .regularExpression) != nil else { return nil }
        return id
    }

    static func claude(home: URL, now: Date) -> [TokenPlanMeter] {
        guard let bytes = try? Data(contentsOf: home.appendingPathComponent(".claude.json")),
              let obj = try? JSONSerialization.jsonObject(with: bytes) as? TokenRecord.Object,
              let cache = obj["cachedUsageUtilization"] as? TokenRecord.Object,
              let account = cache["accountUuid"] as? String, !account.isEmpty,
              (obj["oauthAccount"] as? TokenRecord.Object)?["accountUuid"] as? String == account,
              let usage = cache["utilization"] as? TokenRecord.Object,
              let rows = usage["limits"] as? [TokenRecord.Object] else { return [] }
        return rows.compactMap { row in
            let label: String
            switch row["kind"] as? String {
            case "weekly_all": label = "Weekly"
            case "five_hour", "session": label = "5-hour"
            case "weekly_scoped":
                let scope = row["scope"] as? TokenRecord.Object
                guard let model = scope?["model"] as? TokenRecord.Object,
                      let name = model["display_name"] as? String, !name.isEmpty else { return nil }
                label = name + " weekly"
            default: return nil
            }
            guard let end = TokenRecord.date(row["resets_at"]), end > now else { return nil }
            return TokenPlanMeter(label, percent: row["percent"], reset: end)
        }
    }

    static func grok(home: URL, now: Date) -> [TokenPlanMeter] {
        let log = TokenTool.grok.root(home: home).deletingLastPathComponent().appendingPathComponent("logs/unified.jsonl")
        guard let file = try? FileHandle(forReadingFrom: log) else { return [] }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd() else { return [] }
        let length = min(size, 1_048_576)
        guard (try? file.seek(toOffset: size - length)) != nil,
              let tail = try? file.read(upToCount: Int(length)) else { return [] }
        for line in tail.split(separator: 10).reversed() {
            guard let obj = TokenRecord.object(Data(line), containing: "billing: fetched credits config"),
                  obj["msg"] as? String == "billing: fetched credits config",
                  let ctx = obj["ctx"] as? TokenRecord.Object, let config = ctx["config"] as? TokenRecord.Object,
                  let period = config["currentPeriod"] as? TokenRecord.Object,
                  let stamp = TokenRecord.date(obj["ts"]), (0...43200).contains(now.timeIntervalSince(stamp)),
                  let end = TokenRecord.date(period["end"]), end > now,
                  // Grok omits the percentage on some fetches, so keep looking for the last line that has one.
                  let meter = TokenPlanMeter(period["type"] as? String == "USAGE_PERIOD_TYPE_WEEKLY" ? "Grok weekly" : "Grok subscription",
                                             percent: config["creditUsagePercent"], reset: end) else { continue }
            return [meter]
        }
        return []
    }
}
