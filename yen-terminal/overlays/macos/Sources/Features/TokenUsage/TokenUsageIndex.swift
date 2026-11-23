import Foundation
import CryptoKit
import os

/// The worker opens its private day index only during a refresh. Cursors and
/// contributions commit together so a cancelled refresh can resume safely.
struct TokenUsageIndex: Sendable {
    let home: URL
    let directory: URL
    typealias Counts = [TokenTool: Int]
    /// The label of Grok's finished requests in the events table; never counted on its own.
    static let grokRequestsLabel = "Grok requests"
    /// Deduplicated events: the most complete copy of each record (`events` columns, plus `rank`).
    private static let best = """
        SELECT *,ROW_NUMBER() OVER (PARTITION BY tool,id ORDER BY output DESC,n DESC) AS rank FROM events
        """

    /// One connection at a time per cache file in this process. Two refreshes of one index can
    /// overlap (the menu switched off and on while a read runs), and SQLite answers "database is
    /// locked" without waiting where waiting could deadlock: switching a new file to WAL, or a
    /// connection that read and now wants to write. busy_timeout alone does not cover those.
    private static let fileLocks = OSAllocatedUnfairLock<[String: NSLock]>(initialState: [:])

    private static func serialized<T>(_ path: String, _ body: () throws -> T) rethrows -> T {
        let lock = fileLocks.withLock { locks in
            if let lock = locks[path] { return lock }
            let lock = NSLock()
            locks[path] = lock
            return lock
        }
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func read(now: Date = Date(), tools: Set<TokenTool>, changes: [TokenTool: Set<URL>] = [:]) throws -> Counts {
        let path = directory.appendingPathComponent("today.sqlite").path
        return try Self.serialized(path) { try readLocked(path: path, now: now, tools: tools, changes: changes) }
    }

    private func readLocked(path: String, now: Date, tools: Set<TokenTool>, changes: [TokenTool: Set<URL>]) throws -> Counts {
        guard let day = Calendar.current.dateInterval(of: .day, for: now) else { return [:] }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let db = try SQLiteDatabase(path: path)
        try prepareIndex(db)
        let start = Int(day.start.timeIntervalSince1970)
        let stored = try db.prepare("SELECT start FROM day")
        if try !stored.step() || stored.int(0) != start {
            try db.transaction {
                try db.execute("DELETE FROM cursors; DELETE FROM events; DELETE FROM opencode; DELETE FROM day; INSERT INTO day VALUES(\(start))")
            }
        }
        var counts: Counts = [:]
        for tool in tools {
            try Task.checkCancellation()
            do {
                counts[tool] = try count(tool, db: db, day: day, changes: changes[tool])
            } catch is CancellationError { throw CancellationError() }
            catch { counts[tool] = nil }
        }
        return counts
    }

    func latestCodexPlan() throws -> [TokenPlanMeter] {
        let db = try SQLiteDatabase(readOnlyPath: directory.appendingPathComponent("today.sqlite").path)
        let query = try db.prepare("""
            SELECT json_extract(state,'$.plan') FROM cursors WHERE tool=? AND json_type(state,'$.plan')='object'
            ORDER BY json_extract(state,'$.plan.date') DESC LIMIT 1
            """)
        query.bind(1, TokenTool.codex.rawValue)
        guard try query.step(), let state = query.text(0) else { return [] }
        return try JSONDecoder().decode(TokenPlanReading.self, from: Data(state.utf8)).meters
    }

    /// Today's tokens for each working folder and tool, from the cache the last `read` left.
    /// Usage whose record names no folder is left out.
    func projects() throws -> [String: TokenUsageIndex.Counts] {
        let db = try SQLiteDatabase(readOnlyPath: directory.appendingPathComponent("today.sqlite").path)
        var result: [String: Counts] = [:]
        let rows = try db.prepare("""
            SELECT tool,project,SUM(n) FROM (\(Self.best)) WHERE rank=1 AND project IS NOT NULL AND tool<>? GROUP BY tool,project
            """)
        rows.bind(1, Self.grokRequestsLabel)
        while try rows.step() {
            guard let tool = rows.text(0).flatMap(TokenTool.init(rawValue:)), let folder = rows.text(1) else { continue }
            result[folder, default: [:]][tool, default: 0] += rows.int(2)
        }
        for case let (folder?, count) in try grokRunning(db) where count > 0 { result[folder, default: [:]][.grok, default: 0] += count }
        for (folder, count) in try openCodeDetail(db)?.projects ?? [:] { result[folder, default: [:]][.openCode, default: 0] += count }
        return result
    }

    /// Today's tokens for each local hour, all tools together, from the cache the last `read` left.
    func hours() throws -> [Int] {
        let db = try SQLiteDatabase(readOnlyPath: directory.appendingPathComponent("today.sqlite").path)
        var result = Array(repeating: 0, count: 24)
        let rows = try db.prepare("SELECT hour,SUM(n) FROM (\(Self.best)) WHERE rank=1 AND tool<>? GROUP BY hour")
        rows.bind(1, Self.grokRequestsLabel)
        while try rows.step() {
            if (0..<24).contains(rows.int(0)) { result[rows.int(0)] += rows.int(1) }
        }
        for hours in try openCodeDetail(db)?.hours.values.map({ $0 }) ?? [] {
            for (hour, count) in hours where (0..<24).contains(hour) { result[hour] += count }
        }
        return result
    }

    private func openCodeDetail(_ db: SQLiteDatabase) throws -> TokenOpenCode.Detail? {
        let row = try db.prepare("SELECT detail FROM opencode LIMIT 1")
        guard try row.step(), let text = row.text(0) else { return nil }
        return try? JSONDecoder().decode(TokenOpenCode.Detail.self, from: Data(text.utf8))
    }

    /// Days of history before today. With today, the analytics view covers 90 days.
    static let historyDays = 89

    /// Tokens for each local day before today, oldest first. An unreadable source has no entry.
    /// A finished day never changes, so its total is kept and its source is not read again.
    func history(now: Date = Date()) throws -> [TokenTool: [Int]] {
        let path = directory.appendingPathComponent("history.sqlite").path
        return try Self.serialized(path) { try historyLocked(path: path, now: now) }
    }

    private func historyLocked(path: String, now: Date) throws -> [TokenTool: [Int]] {
        let calendar = Calendar.current, today = calendar.startOfDay(for: now)
        let days = (1...Self.historyDays).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.map(TokenRecord.localDay)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let db = try SQLiteDatabase(path: path)
        try prepareHistory(db)
        var result: [TokenTool: [Int]] = [:]
        for tool in TokenTool.allCases {
            try Task.checkCancellation()
            let saved = try db.prepare("SELECT day,n FROM totals WHERE tool=? AND day>=?")
            saved.bind(1, tool.rawValue); saved.bind(2, days[0])
            var known: [Int: Int] = [:]
            while try saved.step() { known[saved.int(0)] = saved.int(1) }
            if let gap = days.first(where: { known[$0] == nil }) {
                let fresh: [Int: [Int: Int]]
                do {
                    fresh = try totals(tool, in: DateInterval(start: Date(timeIntervalSince1970: Double(gap)), end: today))
                } catch is CancellationError { throw CancellationError() }
                catch { continue }
                try db.transaction {
                    let save = try db.prepare("INSERT OR REPLACE INTO totals VALUES(?,?,?)")
                    let saveHour = try db.prepare("INSERT OR REPLACE INTO hours VALUES(?,?,?,?)")
                    for day in days where day >= gap {
                        let hours = fresh[day] ?? [:]
                        known[day] = hours.values.reduce(0, +)
                        save.reset(); save.bind(1, tool.rawValue); save.bind(2, day); save.bind(3, known[day] ?? 0)
                        _ = try save.step()
                        for (hour, count) in hours where count > 0 {
                            saveHour.reset(); saveHour.bind(1, tool.rawValue); saveHour.bind(2, day)
                            saveHour.bind(3, hour); saveHour.bind(4, count)
                            _ = try saveHour.step()
                        }
                    }
                }
            }
            result[tool] = days.map { known[$0] ?? 0 }
        }
        try db.execute("DELETE FROM totals WHERE day<\(days[0]); DELETE FROM hours WHERE day<\(days[0])")
        return result
    }

    /// Version 2 keeps each finished day's hours beside its total; an older file is read again once.
    private func prepareHistory(_ db: SQLiteDatabase) throws {
        let version = try db.prepare("PRAGMA user_version")
        guard try version.step(), version.int(0) != 2 else { return }
        version.reset()
        try db.transaction {
            try db.execute("""
                DROP TABLE IF EXISTS totals; DROP TABLE IF EXISTS hours;
                CREATE TABLE totals(tool TEXT,day INTEGER,n INTEGER,PRIMARY KEY(tool,day)) WITHOUT ROWID;
                CREATE TABLE hours(tool TEXT,day INTEGER,hour INTEGER,n INTEGER,PRIMARY KEY(tool,day,hour)) WITHOUT ROWID;
                PRAGMA user_version=2;
                """)
        }
    }

    /// Tokens by weekday and hour over the analytics window, all tools together: 168 bins,
    /// Sunday's midnight hour first, in `Calendar.current` weekdays. Run after `history`.
    func rhythm(now: Date = Date()) throws -> [Int] {
        let calendar = Calendar.current, today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -Self.historyDays, to: today) else { return [] }
        var bins = Array(repeating: 0, count: 168)
        func add(day: Int, hour: Int, count: Int) {
            let weekday = calendar.component(.weekday, from: Date(timeIntervalSince1970: Double(day)))
            guard (1...7).contains(weekday), (0..<24).contains(hour) else { return }
            bins[(weekday - 1) * 24 + hour] += count
        }
        let path = directory.appendingPathComponent("history.sqlite").path
        if FileManager.default.fileExists(atPath: path) {
            let db = try SQLiteDatabase(readOnlyPath: path)
            let rows = try db.prepare("SELECT day,hour,SUM(n) FROM hours WHERE day>=? AND day<? GROUP BY day,hour")
            rows.bind(1, TokenRecord.localDay(first)); rows.bind(2, TokenRecord.localDay(today))
            while try rows.step() { add(day: rows.int(0), hour: rows.int(1), count: rows.int(2)) }
        }
        for (hour, count) in ((try? hours()) ?? []).enumerated() { add(day: TokenRecord.localDay(today), hour: hour, count: count) }
        return bins
    }

    /// Reads the interval into a scratch index, so the day index and its cursors stay untouched.
    /// Returns tokens by local day and hour.
    private func totals(_ tool: TokenTool, in interval: DateInterval) throws -> [Int: [Int: Int]] {
        let fm = FileManager.default
        let store = tool.root(home: home).resolvingSymlinksInPath().appendingPathComponent("opencode.db")
        if tool == .openCode, fm.fileExists(atPath: store.path) {
            return try TokenOpenCode(db: SQLiteDatabase(readOnlyPath: store.path)).detail(in: interval).hours
        }
        // The temporary folder is reclaimed by the system, so a quit in the middle of a read leaves nothing behind for good.
        let scratch = fm.temporaryDirectory.appendingPathComponent("yen-token-history-" + UUID().uuidString + ".sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? fm.removeItem(atPath: scratch + suffix) } }
        let db = try SQLiteDatabase(path: scratch)
        // One pass over finished days needs no lookup by rank; only Codex corrections look rows up.
        try prepareIndex(db, indexed: tool == .codex)
        _ = try count(tool, db: db, day: interval, changes: nil, live: false)
        let rows = try db.prepare("""
            SELECT day,hour,SUM(n) FROM (
                SELECT day,hour,n,ROW_NUMBER() OVER (PARTITION BY id ORDER BY output DESC,n DESC) AS rank
                FROM events WHERE tool=?) WHERE rank=1 GROUP BY day,hour
            """)
        rows.bind(1, tool.rawValue)
        var result: [Int: [Int: Int]] = [:]
        while try rows.step() { result[rows.int(0), default: [:]][rows.int(1)] = rows.int(2) }
        return result
    }

    private func prepareIndex(_ db: SQLiteDatabase, indexed: Bool = true) throws {
        let version = try db.prepare("PRAGMA user_version")
        guard try version.step(), version.int(0) != 5 else { return }
        version.reset()
        // Only YEN's disposable cache is migrated. Re-read unchanged logs using the new counting rules.
        try db.transaction {
            try db.execute("""
                DROP TABLE IF EXISTS day; DROP TABLE IF EXISTS opencode;
                DROP TABLE IF EXISTS cursors; DROP TABLE IF EXISTS events;
                CREATE TABLE day(start INTEGER);
                CREATE TABLE opencode(stamp TEXT PRIMARY KEY,count INTEGER,detail TEXT);
                CREATE TABLE cursors(path TEXT PRIMARY KEY,inode INTEGER,size INTEGER,stamp REAL,offset INTEGER,state TEXT,tail TEXT,tool TEXT);
                CREATE TABLE events(tool TEXT,path TEXT,id TEXT,n INTEGER,output INTEGER,input INTEGER,cached INTEGER,seq INTEGER,day INTEGER,
                    hour INTEGER,project TEXT,session TEXT,PRIMARY KEY(tool,path,id)) WITHOUT ROWID;
                PRAGMA user_version=5;
                """)
            if indexed {
                try db.execute("""
                    CREATE INDEX best ON events(tool,id,output DESC,n DESC);
                    CREATE INDEX recent ON events(path,seq DESC);
                    """)
            }
        }
    }

    private func forget(_ path: String, db: SQLiteDatabase) throws {
        try db.transaction {
            for sql in ["DELETE FROM cursors WHERE path=?", "DELETE FROM events WHERE path=?"] {
                let remove = try db.prepare(sql)
                remove.bind(1, path)
                _ = try remove.step()
            }
        }
    }

    private func count(_ tool: TokenTool, db: SQLiteDatabase, day: DateInterval, changes: Set<URL>?, live: Bool = true) throws -> Int {
        // A directory walk does not follow a provider directory that is itself a symbolic link.
        let root = tool.root(home: home).resolvingSymlinksInPath()
        let fm = FileManager.default
        let files: [URL]
        if tool == .openCode {
            let store = root.appendingPathComponent("opencode.db")
            if fm.fileExists(atPath: store.path) {
                return try openCodeCount(store, day: day, cache: db)
            }
            let log = root.appendingPathComponent("log/opencode.log")
            guard fm.isReadableFile(atPath: log.path) else { throw CocoaError(.fileReadNoSuchFile) }
            files = [log]
        } else if let changes {
            guard fm.isReadableFile(atPath: root.path) else { throw CocoaError(.fileReadNoSuchFile) }
            files = changes.filter { tool.accepts($0) && fm.fileExists(atPath: $0.path) }
        } else {
            guard fm.isReadableFile(atPath: root.path) else { throw CocoaError(.fileReadNoSuchFile) }
            var readError: Error?
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
            guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles],
                                             errorHandler: { _, error in readError = error; return false }) else {
                throw CocoaError(.fileReadUnknown)
            }
            var recent: [URL] = [], idle: (url: URL, modified: Date)?
            for case let url as URL in walker where tool.accepts(url) {
                try Task.checkCancellation()
                let values = try url.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true else { continue }
                let modified = values.contentModificationDate ?? .distantFuture
                if modified >= day.start {
                    recent.append(url)
                } else if tool == .codex, modified > idle?.modified ?? .distantPast {
                    idle = (url, modified)
                }
            }
            if let readError { throw readError }
            // Codex records its account limits only while it runs, and a weekly window outlives the day.
            files = recent + (idle.map { [$0.url] } ?? [])
        }
        if let changes {
            for url in changes where tool.accepts(url) && !fm.fileExists(atPath: url.path) {
                try forget(url.standardizedFileURL.resolvingSymlinksInPath().path, db: db)
            }
        } else {
            let known = try db.prepare("SELECT path FROM cursors WHERE tool=?")
            known.bind(1, tool.rawValue)
            var missing: [String] = []
            while try known.step() {
                if let path = known.text(0), !fm.fileExists(atPath: path) { missing.append(path) }
            }
            for path in missing { try forget(path, db: db) }
        }
        for file in files { try ingest(file.standardizedFileURL.resolvingSymlinksInPath(), tool: tool, day: day, db: db) }
        var running = 0
        if tool == .grok, live {
            // A failed read of the shell log leaves only the running turns out; completed turns still count.
            do {
                try ingestGrokRequests(day: day, db: db)
                running = try grokRunning(db).values.reduce(0, +)
            } catch is CancellationError { throw CancellationError() } catch {}
        }
        let query = try db.prepare("""
            SELECT COALESCE(SUM(n),0) FROM (
                SELECT n,ROW_NUMBER() OVER (PARTITION BY id ORDER BY output DESC,n DESC) AS rank
                FROM events WHERE tool=?) WHERE rank=1
            """)
        query.bind(1, tool.rawValue)
        guard try query.step() else { throw CocoaError(.fileReadUnknown) }
        return max(0, query.int(0)) + running
    }

    private func ingestGrokRequests(day: DateInterval, db: SQLiteDatabase) throws {
        let log = TokenTool.grok.grokLog(home: home).standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.isReadableFile(atPath: log.path) else {
            try forget(log.path, db: db)
            return
        }
        try ingest(log, tool: .grok, day: day, db: db, requests: true)
    }

    /// Tokens of Grok turns still running, by folder: a session's finished requests minus its
    /// completed turns. Requests of a finished turn add up to that turn, so they add nothing.
    private func grokRunning(_ db: SQLiteDatabase) throws -> [String?: Int] {
        let rows = try db.prepare("""
            SELECT r.project,MAX(0,r.n-COALESCE(t.n,0)) FROM
                (SELECT session,MAX(project) AS project,SUM(n) AS n FROM events WHERE tool=? GROUP BY session) r
            LEFT JOIN (SELECT session,SUM(n) AS n FROM (\(Self.best)) WHERE rank=1 AND tool=? GROUP BY session) t
            ON r.session=t.session
            """)
        rows.bind(1, Self.grokRequestsLabel); rows.bind(2, TokenTool.grok.rawValue)
        var result: [String?: Int] = [:]
        while try rows.step() { result[rows.text(0), default: 0] += rows.int(1) }
        return result
    }

    /// The working folder of a Grok session, from the folder its records are kept in.
    private func grokFolder(session: String) -> String? {
        let root = TokenTool.grok.root(home: home).resolvingSymlinksInPath()
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: root.path) else { return nil }
        for folder in folders where fm.fileExists(atPath: root.appendingPathComponent(folder).appendingPathComponent(session).path) {
            return TokenRecord.Source.of(root.appendingPathComponent(folder).appendingPathComponent(session)
                .appendingPathComponent("updates.jsonl"), tool: .grok).project
        }
        return nil
    }

    private func openCodeCount(_ url: URL, day: DateInterval, cache: SQLiteDatabase) throws -> Int {
        // Invalidate counts saved before the hour and folder detail was kept.
        let signature = "3:" + [url.path, url.path + "-wal"].map { path -> String in
            var info = Darwin.stat()
            guard lstat(path, &info) == 0 else { return "-" }
            return "\(info.st_ino)/\(info.st_size)/\(info.st_ctimespec.tv_sec)/\(info.st_ctimespec.tv_nsec)"
        }.joined(separator: "|")
        let cached = try cache.prepare("SELECT count FROM opencode WHERE stamp=?")
        cached.bind(1, signature)
        if try cached.step() { return cached.int(0) }
        let detail = try TokenOpenCode(db: SQLiteDatabase(readOnlyPath: url.path)).detail(in: day)
        try cache.transaction {
            try cache.execute("DELETE FROM opencode")
            let save = try cache.prepare("INSERT INTO opencode VALUES(?,?,?)")
            save.bind(1, signature)
            save.bind(2, detail.total)
            save.bind(3, String(decoding: try JSONEncoder().encode(detail), as: UTF8.self))
            _ = try save.step()
        }
        return detail.total
    }

    /// Reads a record file from its cursor. With `requests`, the file is Grok's shell log, whose
    /// finished requests are kept under their own label and only fill in turns still running.
    private func ingest(_ url: URL, tool: TokenTool, day: DateInterval, db: SQLiteDatabase, requests: Bool = false) throws {
        let label = requests ? Self.grokRequestsLabel : tool.rawValue
        var stat = Darwin.stat()
        guard lstat(url.path, &stat) == 0, stat.st_mode & S_IFMT == S_IFREG else { throw CocoaError(.fileReadUnknown) }
        let size = Int(stat.st_size), inode = Int(truncatingIfNeeded: stat.st_ino)
        let stamp = Double(stat.st_ctimespec.tv_sec) + Double(stat.st_ctimespec.tv_nsec) / 1e9
        let cursor = try db.prepare("SELECT inode,size,stamp,offset,state,tail FROM cursors WHERE path=?")
        cursor.bind(1, url.path)
        let exists = try cursor.step()
        if exists && cursor.int(0) == inode && cursor.int(1) == size && cursor.double(2) == stamp { return }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var offset = exists ? cursor.int(3) : 0
        let samePrefix = try exists && size > cursor.int(1) && cursor.int(0) == inode &&
            checkpoint(handle, offset: offset) == cursor.text(5)
        var codex = TokenCodex()
        if tool == .codex, !requests, samePrefix, let state = cursor.text(4) {
            codex = try JSONDecoder().decode(TokenCodex.self, from: Data(state.utf8))
        }
        if !samePrefix { offset = 0 }
        try handle.seek(toOffset: UInt64(offset))
        try db.transaction {
            if !samePrefix {
                let clear = try db.prepare("DELETE FROM events WHERE tool=? AND path=?")
                clear.bind(1, label); clear.bind(2, url.path); _ = try clear.step()
            }
            let insert = try db.prepare("""
                INSERT INTO events(tool,path,id,n,output,day,hour,project,session) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(tool,path,id)
                DO UPDATE SET n=excluded.n,output=excluded.output,day=excluded.day,hour=excluded.hour,project=excluded.project,
                    session=excluded.session WHERE (excluded.output,excluded.n)>(output,n)
                """)
            let rollout = tool == .codex ? TokenCodex.rolloutID(url) : ""
            let source = TokenRecord.Source.of(url, tool: tool)
            var folders: [String: String?] = [:]
            let markers = requests ? ["\"shell.turn.inference_done\""] : tool.markers
            let end = try stream(handle, from: offset, through: size, containing: markers,
                                 limit: requests ? 64 * 1024 : tool.recordLimit) { bytes in
                if tool == .codex && !requests {
                    try codex.ingest(bytes, file: url.path, rollout: rollout, day: day, db: db)
                    return
                }
                var entries = requests ? TokenRecord.grokRequest(bytes, day: day).map { [$0] } ?? []
                    : TokenRecord.decode(bytes, tool: tool, day: day, source: source)
                if requests {
                    // A turn in progress has no completed record yet, so its folder comes from the session folder.
                    for index in entries.indices {
                        guard let session = entries[index].session else { continue }
                        if folders[session] == nil { folders[session] = grokFolder(session: session) }
                        entries[index].project = folders[session] ?? nil
                    }
                }
                for entry in entries {
                    insert.reset()
                    insert.bind(1, label); insert.bind(2, url.path); insert.bind(3, entry.key)
                    insert.bind(4, entry.count); insert.bind(5, entry.output); insert.bind(6, entry.day)
                    insert.bind(7, entry.hour); insert.bind(8, entry.project); insert.bind(9, entry.session)
                    _ = try insert.step()
                }
            }
            let save = try db.prepare("INSERT OR REPLACE INTO cursors VALUES(?,?,?,?,?,?,?,?)")
            save.bind(1, url.path); save.bind(2, inode); save.bind(3, size); save.bind(4, stamp)
            save.bind(5, end)
            if tool == .codex && !requests { save.bind(6, String(decoding: try JSONEncoder().encode(codex), as: UTF8.self)) }
            save.bind(7, try checkpoint(handle, offset: end)); save.bind(8, label)
            _ = try save.step()
        }
    }

    private func checkpoint(_ handle: FileHandle, offset: Int) throws -> String {
        let length = min(offset, 128)
        try handle.seek(toOffset: UInt64(offset - length))
        // Hash the tail; the checkpoint must never retain transcript bytes.
        let data = length > 0 ? try handle.read(upToCount: length) ?? Data() : Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Calls `consume` with each complete line that holds one of `markers` (any line when there are
    /// none) and is no longer than `limit`,
    /// and returns the offset after the last complete line. A line is copied out of the read buffer
    /// only when it holds the marker, and a line over the limit is never held.
    private func stream(_ handle: FileHandle, from start: Int, through size: Int, containing markers: [String], limit: Int,
                        consume: (Data) throws -> Void) throws -> Int {
        let needles = markers.map { Array($0.utf8) }
        func wanted(_ bytes: UnsafeRawBufferPointer) -> Bool {
            needles.isEmpty || needles.contains { TokenRecord.contains(bytes, $0) }
        }
        var position = start, committed = start
        // The start of a line that began in an earlier chunk.
        var carry = Data()
        var skipping = false
        while position < size {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let chunk = try handle.read(upToCount: min(1 << 20, size - position)), !chunk.isEmpty else {
                    throw CocoaError(.fileReadUnknown)
                }
                try chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    guard let base = raw.baseAddress else { return }
                    var cursor = 0
                    while cursor < raw.count, let found = memchr(base + cursor, 10, raw.count - cursor) {
                        let lf = base.distance(to: UnsafeRawPointer(found))
                        let piece = UnsafeRawBufferPointer(rebasing: raw[cursor..<lf])
                        if skipping {
                            skipping = false
                        } else if carry.isEmpty {
                            if piece.count <= limit, wanted(piece) {
                                try autoreleasepool { try consume(Data(piece)) }
                            }
                        } else if carry.count + piece.count <= limit {
                            carry.append(contentsOf: piece)
                            if carry.withUnsafeBytes(wanted) { try autoreleasepool { try consume(carry) } }
                        }
                        carry.removeAll(keepingCapacity: false)
                        cursor = lf + 1
                        committed = position + cursor
                    }
                    let rest = UnsafeRawBufferPointer(rebasing: raw[cursor...])
                    guard !skipping, !rest.isEmpty else { return }
                    if carry.count + rest.count > limit {
                        carry.removeAll(keepingCapacity: false)
                        skipping = true
                    } else {
                        carry.append(contentsOf: rest)
                    }
                }
                position += chunk.count
            }
        }
        return committed
    }
}
