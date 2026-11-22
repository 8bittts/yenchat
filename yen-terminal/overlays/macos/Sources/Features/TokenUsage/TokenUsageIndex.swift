import Foundation
import CryptoKit

/// The worker opens its private day index only during a refresh. Cursors and
/// contributions commit together so a cancelled refresh can resume safely.
struct TokenUsageIndex: Sendable {
    let home: URL
    let directory: URL
    typealias Counts = [TokenTool: Int]

    func read(now: Date = Date(), tools: Set<TokenTool>, changes: [TokenTool: Set<URL>] = [:]) throws -> Counts {
        guard let day = Calendar.current.dateInterval(of: .day, for: now) else { return [:] }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let db = try SQLiteDatabase(path: directory.appendingPathComponent("today.sqlite").path)
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

    /// Days of history before today. With today, the analytics view covers 90 days.
    static let historyDays = 89

    /// Tokens for each local day before today, oldest first. An unreadable source has no entry.
    /// A finished day never changes, so its total is kept and its source is not read again.
    func history(now: Date = Date()) throws -> [TokenTool: [Int]] {
        let calendar = Calendar.current, today = calendar.startOfDay(for: now)
        let days = (1...Self.historyDays).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.map(TokenRecord.localDay)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let db = try SQLiteDatabase(path: directory.appendingPathComponent("history.sqlite").path)
        try db.execute("CREATE TABLE IF NOT EXISTS totals(tool TEXT,day INTEGER,n INTEGER,PRIMARY KEY(tool,day)) WITHOUT ROWID")
        var result: [TokenTool: [Int]] = [:]
        for tool in TokenTool.allCases {
            try Task.checkCancellation()
            let saved = try db.prepare("SELECT day,n FROM totals WHERE tool=? AND day>=?")
            saved.bind(1, tool.rawValue); saved.bind(2, days[0])
            var known: [Int: Int] = [:]
            while try saved.step() { known[saved.int(0)] = saved.int(1) }
            if let gap = days.first(where: { known[$0] == nil }) {
                let fresh: [Int: Int]
                do {
                    fresh = try totals(tool, in: DateInterval(start: Date(timeIntervalSince1970: Double(gap)), end: today))
                } catch is CancellationError { throw CancellationError() }
                catch { continue }
                try db.transaction {
                    let save = try db.prepare("INSERT OR REPLACE INTO totals VALUES(?,?,?)")
                    for day in days where day >= gap {
                        known[day] = fresh[day] ?? 0
                        save.reset(); save.bind(1, tool.rawValue); save.bind(2, day); save.bind(3, fresh[day] ?? 0)
                        _ = try save.step()
                    }
                }
            }
            result[tool] = days.map { known[$0] ?? 0 }
        }
        try db.execute("DELETE FROM totals WHERE day<\(days[0])")
        return result
    }

    /// Reads the interval into a scratch index, so the day index and its cursors stay untouched.
    private func totals(_ tool: TokenTool, in interval: DateInterval) throws -> [Int: Int] {
        let fm = FileManager.default
        let store = tool.root(home: home).resolvingSymlinksInPath().appendingPathComponent("opencode.db")
        if tool == .openCode, fm.fileExists(atPath: store.path) {
            return try TokenOpenCode(db: SQLiteDatabase(readOnlyPath: store.path)).daily(in: interval)
        }
        let scratch = directory.appendingPathComponent("history-scan.sqlite").path
        let discard = { for suffix in ["", "-wal", "-shm"] { try? fm.removeItem(atPath: scratch + suffix) } }
        discard()
        defer { discard() }
        let db = try SQLiteDatabase(path: scratch)
        try prepareIndex(db)
        _ = try count(tool, db: db, day: interval, changes: nil)
        let rows = try db.prepare("""
            SELECT day,SUM(n) FROM (
                SELECT day,n,ROW_NUMBER() OVER (PARTITION BY id ORDER BY output DESC,n DESC) AS rank
                FROM events WHERE tool=?) WHERE rank=1 GROUP BY day
            """)
        rows.bind(1, tool.rawValue)
        var result: [Int: Int] = [:]
        while try rows.step() { result[rows.int(0)] = rows.int(1) }
        return result
    }

    private func prepareIndex(_ db: SQLiteDatabase) throws {
        let version = try db.prepare("PRAGMA user_version")
        guard try version.step(), version.int(0) != 4 else { return }
        version.reset()
        // Only YEN's disposable cache is migrated. Re-read unchanged logs using the new counting rules.
        try db.transaction {
            try db.execute("""
                DROP TABLE IF EXISTS day; DROP TABLE IF EXISTS opencode;
                DROP TABLE IF EXISTS cursors; DROP TABLE IF EXISTS events;
                CREATE TABLE day(start INTEGER);
                CREATE TABLE opencode(stamp TEXT PRIMARY KEY,count INTEGER);
                CREATE TABLE cursors(path TEXT PRIMARY KEY,inode INTEGER,size INTEGER,stamp REAL,offset INTEGER,state TEXT,tail TEXT,tool TEXT);
                CREATE TABLE events(tool TEXT,path TEXT,id TEXT,n INTEGER,output INTEGER,input INTEGER,cached INTEGER,seq INTEGER,day INTEGER,
                    PRIMARY KEY(tool,path,id)) WITHOUT ROWID;
                CREATE INDEX best ON events(tool,id,output DESC,n DESC);
                CREATE INDEX recent ON events(path,seq DESC);
                PRAGMA user_version=4;
                """)
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

    private func count(_ tool: TokenTool, db: SQLiteDatabase, day: DateInterval, changes: Set<URL>?) throws -> Int {
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
        let query = try db.prepare("""
            SELECT COALESCE(SUM(n),0) FROM (
                SELECT n,ROW_NUMBER() OVER (PARTITION BY id ORDER BY output DESC,n DESC) AS rank
                FROM events WHERE tool=?) WHERE rank=1
            """)
        query.bind(1, tool.rawValue)
        guard try query.step() else { throw CocoaError(.fileReadUnknown) }
        return max(0, query.int(0))
    }

    private func openCodeCount(_ url: URL, day: DateInterval, cache: SQLiteDatabase) throws -> Int {
        // Invalidate counts saved before legacy session fallback was supported.
        let signature = "2:" + [url.path, url.path + "-wal"].map { path -> String in
            var info = Darwin.stat()
            guard lstat(path, &info) == 0 else { return "-" }
            return "\(info.st_ino)/\(info.st_size)/\(info.st_ctimespec.tv_sec)/\(info.st_ctimespec.tv_nsec)"
        }.joined(separator: "|")
        let cached = try cache.prepare("SELECT count FROM opencode WHERE stamp=?")
        cached.bind(1, signature)
        if try cached.step() { return cached.int(0) }
        let count = try TokenOpenCode(db: SQLiteDatabase(readOnlyPath: url.path)).count(in: day)
        try cache.transaction {
            try cache.execute("DELETE FROM opencode")
            let save = try cache.prepare("INSERT INTO opencode VALUES(?,?)")
            save.bind(1, signature)
            save.bind(2, count)
            _ = try save.step()
        }
        return count
    }

    private func ingest(_ url: URL, tool: TokenTool, day: DateInterval, db: SQLiteDatabase) throws {
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
        if tool == .codex, samePrefix, let state = cursor.text(4) {
            codex = try JSONDecoder().decode(TokenCodex.self, from: Data(state.utf8))
        }
        if !samePrefix { offset = 0 }
        try handle.seek(toOffset: UInt64(offset))
        try db.transaction {
            if !samePrefix {
                let clear = try db.prepare("DELETE FROM events WHERE tool=? AND path=?")
                clear.bind(1, tool.rawValue); clear.bind(2, url.path); _ = try clear.step()
            }
            let insert = try db.prepare("""
                INSERT INTO events(tool,path,id,n,output,day) VALUES(?,?,?,?,?,?) ON CONFLICT(tool,path,id)
                DO UPDATE SET n=excluded.n,output=excluded.output,day=excluded.day WHERE (excluded.output,excluded.n)>(output,n)
                """)
            let rollout = tool == .codex ? TokenCodex.rolloutID(url) : ""
            let end = try stream(handle, from: offset, through: size) { bytes in
                if tool == .codex {
                    try codex.ingest(bytes, file: url.path, rollout: rollout, day: day, db: db)
                    return
                }
                for entry in TokenRecord.decode(bytes, tool: tool, day: day) {
                    insert.reset()
                    insert.bind(1, tool.rawValue); insert.bind(2, url.path); insert.bind(3, entry.key)
                    insert.bind(4, entry.count); insert.bind(5, entry.output); insert.bind(6, entry.day)
                    _ = try insert.step()
                }
            }
            let save = try db.prepare("INSERT OR REPLACE INTO cursors VALUES(?,?,?,?,?,?,?,?)")
            save.bind(1, url.path); save.bind(2, inode); save.bind(3, size); save.bind(4, stamp)
            save.bind(5, end)
            if tool == .codex { save.bind(6, String(decoding: try JSONEncoder().encode(codex), as: UTF8.self)) }
            save.bind(7, try checkpoint(handle, offset: end)); save.bind(8, tool.rawValue)
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

    private func stream(_ handle: FileHandle, from start: Int, through size: Int, consume: (Data) throws -> Void) throws -> Int {
        var position = start, committed = start, line = Data()
        var skipping = false
        while position < size {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let chunk = try handle.read(upToCount: min(65536, size - position)), !chunk.isEmpty else {
                    throw CocoaError(.fileReadUnknown)
                }
                var rest = chunk[...]
                while let lf = rest.firstIndex(of: 10) {
                    if !skipping { line.append(rest[..<lf]) }
                    position += rest.distance(from: rest.startIndex, to: lf) + 1
                    if !skipping { try autoreleasepool { try consume(line) } }
                    skipping = false
                    committed = position
                    line.removeAll(keepingCapacity: false)
                    rest = rest[rest.index(after: lf)...]
                }
                if !skipping { line.append(rest) }
                position += rest.count
                if line.count > 8 * 1024 * 1024 {
                    // Usage records are small. Compactions and image or tool payloads between them are not.
                    line.removeAll(keepingCapacity: false)
                    skipping = true
                }
            }
        }
        return committed
    }
}
