import Foundation

/// A rollout reports cumulative input, cached input (inside input), and output.
/// Keep just the last counters in memory. Correct earlier deltas newest-first on disk.
struct TokenCodex: Codable {
    private var previousReading: TokenPlanReading?
    private(set) var plan: TokenPlanReading?
    private var footprint = 0
    private var buckets = [0, 0, 0]
    private var ordinal = 0

    static func rolloutID(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let uuid = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        return name.range(of: uuid, options: .regularExpression).map { String(name[$0]) } ?? name
    }

    mutating func ingest(_ bytes: Data, file: String, rollout: String, day: DateInterval, db: SQLiteDatabase) throws {
        guard let obj = TokenRecord.object(bytes, containing: "\"token_count\""), obj["type"] as? String == "event_msg",
              let payload = obj["payload"] as? TokenRecord.Object, payload["type"] as? String == "token_count" else { return }
        if let limits = payload["rate_limits"] as? TokenRecord.Object, let date = TokenRecord.date(obj["timestamp"]),
           let reading = TokenPlanReading.codex(limits, at: date) {
            plan = reading.isRollingPlaceholder(after: previousReading) ? nil : reading
            previousReading = reading
        }
        guard let info = payload["info"] as? TokenRecord.Object, let usage = info["total_token_usage"] as? TokenRecord.Object else { return }
        let input = TokenRecord.number(usage["input_tokens"]), cached = TokenRecord.number(usage["cached_input_tokens"])
        let output = TokenRecord.number(usage["output_tokens"]), next = input + cached + output
        if next * 2 < footprint { buckets = [0, 0, 0] }
        footprint = next
        let target = [max(0, input - cached), cached, output]
        let delta = zip(target, buckets).map(-)
        buckets = target
        let columns = ["input", "cached", "output"]
        for i in columns.indices where delta[i] < 0 {
            try correct(column: columns[i], amount: -delta[i], file: file, db: db)
        }
        let added = delta.map { max(0, $0) }
        guard added.contains(where: { $0 > 0 }) else { return }
        defer { ordinal += 1 }
        guard let stamp = TokenRecord.date(obj["timestamp"]), stamp >= day.start, stamp < day.end else { return }
        let insert = try db.prepare("INSERT INTO events(tool,path,id,n,output,input,cached,seq,day) VALUES(?,?,?,?,?,?,?,?,?)")
        insert.bind(1, TokenTool.codex.rawValue); insert.bind(2, file)
        insert.bind(3, TokenRecord.key(rollout, String(ordinal))); insert.bind(4, added.reduce(0, +))
        insert.bind(5, added[2]); insert.bind(6, added[0]); insert.bind(7, added[1]); insert.bind(8, ordinal)
        insert.bind(9, TokenRecord.localDay(stamp))
        _ = try insert.step()
    }

    private func correct(column: String, amount: Int, file: String, db: SQLiteDatabase) throws {
        let newest = try db.prepare("SELECT id,\(column) FROM events WHERE path=? AND \(column)>0 ORDER BY seq DESC LIMIT 1")
        let update = try db.prepare("UPDATE events SET \(column)=\(column)-?,n=n-? WHERE path=? AND id=?")
        var remaining = amount
        while remaining > 0 {
            try Task.checkCancellation()
            newest.reset(); newest.bind(1, file)
            guard try newest.step(), let id = newest.text(0) else { break }
            let take = min(remaining, newest.int(1))
            newest.reset()
            update.reset(); update.bind(1, take); update.bind(2, take); update.bind(3, file); update.bind(4, id)
            _ = try update.step()
            remaining -= take
        }
    }
}
