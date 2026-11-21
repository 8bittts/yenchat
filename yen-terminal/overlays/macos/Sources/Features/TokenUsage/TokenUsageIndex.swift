import Foundation
import CryptoKit

/// The worker opens its private day index only during a refresh. Cursors and
/// contributions commit together so a cancelled refresh can resume safely.
struct TokenUsageIndex: Sendable {
    let home: URL
    let directory: URL
    typealias Counts = [TokenTool: Int]

    func read(now: Date = Date(), tools: Set<TokenTool>, changes: [TokenTool: Set<URL>] = [:], calendar: Calendar = .current) throws -> Counts {
        guard let day = calendar.dateInterval(of: .day, for: now) else { return [:] }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let db = try SQLiteDatabase(path: directory.appendingPathComponent("today.sqlite").path)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS day(start INTEGER);
            CREATE TABLE IF NOT EXISTS opencode(stamp TEXT PRIMARY KEY, count INTEGER);
            CREATE TABLE IF NOT EXISTS cursors(path TEXT PRIMARY KEY, inode INTEGER, size INTEGER, stamp REAL, offset INTEGER, previous INTEGER, tail BLOB);
            CREATE TABLE IF NOT EXISTS events(tool TEXT,path TEXT,id TEXT,n INTEGER,PRIMARY KEY(tool,path,id)) WITHOUT ROWID;
            """)
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

    private func count(_ tool: TokenTool, db: SQLiteDatabase, day: DateInterval, changes: Set<URL>?) throws -> Int {
        let root = tool.root(home: home)
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
            var recent: [URL] = []
            for case let url as URL in walker {
                try Task.checkCancellation()
                if try tool.accepts(url) && url.resourceValues(forKeys: Set(keys)).isRegularFile == true
                    && (url.resourceValues(forKeys: Set(keys)).contentModificationDate ?? .distantFuture) >= day.start {
                    recent.append(url)
                }
            }
            if let readError { throw readError }
            files = recent
        }
        for file in files { try ingest(file.standardizedFileURL.resolvingSymlinksInPath(), tool: tool, day: day, db: db) }
        let query = try db.prepare("SELECT COALESCE(SUM(n),0) FROM (SELECT MAX(n) AS n FROM events WHERE tool=? GROUP BY id)")
        query.bind(1, tool.rawValue)
        guard try query.step() else { throw CocoaError(.fileReadUnknown) }
        return max(0, query.int(0))
    }

    private func openCodeCount(_ url: URL, day: DateInterval, cache: SQLiteDatabase) throws -> Int {
        let signature = [url.path, url.path + "-wal"].map { path -> String in
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
        let cursor = try db.prepare("SELECT inode,size,stamp,offset,previous,tail FROM cursors WHERE path=?")
        cursor.bind(1, url.path)
        let exists = try cursor.step()
        if exists && cursor.int(0) == inode && cursor.int(1) == size && cursor.double(2) == stamp { return }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var offset = exists ? cursor.int(3) : 0
        let samePrefix = try exists && size > cursor.int(1) && cursor.int(0) == inode &&
            checkpoint(handle, offset: offset) == cursor.text(5)
        var previous = samePrefix ? cursor.int(4) : 0
        if !samePrefix { offset = 0 }
        try handle.seek(toOffset: UInt64(offset))
        try db.transaction {
            if !samePrefix {
                let clear = try db.prepare("DELETE FROM events WHERE tool=? AND path=?")
                clear.bind(1, tool.rawValue); clear.bind(2, url.path); _ = try clear.step()
            }
            let insert = try db.prepare("INSERT INTO events VALUES(?,?,?,?) ON CONFLICT(tool,path,id) DO UPDATE SET n=MAX(n,excluded.n)")
            let basename = url.deletingPathExtension().lastPathComponent
            let end = try stream(handle, from: offset, through: size) { bytes, position in
                guard let entry = TokenRecord.decode(bytes, tool: tool, previous: &previous, ordinal: position),
                      entry.date >= day.start, entry.date < day.end else { return }
                insert.reset()
                insert.bind(1, tool.rawValue); insert.bind(2, url.path)
                insert.bind(3, tool == .codex ? basename + "/" + entry.key : entry.key)
                insert.bind(4, entry.count); _ = try insert.step()
            }
            let save = try db.prepare("INSERT OR REPLACE INTO cursors VALUES(?,?,?,?,?,?,?)")
            save.bind(1, url.path); save.bind(2, inode); save.bind(3, size); save.bind(4, stamp)
            save.bind(5, end); save.bind(6, previous); save.bind(7, try checkpoint(handle, offset: end))
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

    private func stream(_ handle: FileHandle, from start: Int, through size: Int,
                        consume: (Data, Int) throws -> Void) throws -> Int {
        var position = start, committed = start, line = Data()
        while position < size {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let chunk = try handle.read(upToCount: min(65536, size - position)), !chunk.isEmpty else {
                    throw CocoaError(.fileReadUnknown)
                }
                var rest = chunk[...]
                while let lf = rest.firstIndex(of: 10) {
                    line.append(rest[..<lf])
                    position += rest.distance(from: rest.startIndex, to: lf) + 1
                    try autoreleasepool { try consume(line, committed) }
                    committed = position
                    line.removeAll(keepingCapacity: false)
                    rest = rest[rest.index(after: lf)...]
                }
                line.append(rest)
                position += rest.count
                guard line.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            }
        }
        return committed
    }
}
