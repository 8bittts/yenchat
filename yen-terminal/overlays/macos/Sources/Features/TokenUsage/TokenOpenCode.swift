import Foundation

/// Projects OpenCode's local message store and decodes its log format.
struct TokenOpenCode {
    let db: SQLiteDatabase
    private static let total = """
        COALESCE(t_input,0)+COALESCE(t_output,0)+COALESCE(t_reasoning,0)+COALESCE(t_cache_read,0)+COALESCE(t_cache_write,0)
        """
    private static let sessions = """
        SELECT time_created AS created, NULL AS sid, tokens_input AS t_input, tokens_output AS t_output,
               tokens_reasoning AS t_reasoning, tokens_cache_read AS t_cache_read, tokens_cache_write AS t_cache_write
        FROM session
        """

    func count(in day: DateInterval) throws -> Int { try daily(in: day).values.reduce(0, +) }

    /// Tokens per local day inside the interval, read in one snapshot.
    func daily(in interval: DateInterval) throws -> [Int: Int] {
        try detail(in: interval).hours.mapValues { $0.values.reduce(0, +) }
    }

    /// Tokens by local day and hour, and by session folder, inside the interval, read in one snapshot.
    struct Detail: Codable, Equatable {
        var hours: [Int: [Int: Int]] = [:]
        var projects: [String: Int] = [:]
        var total: Int { hours.values.reduce(0) { $0 + $1.values.reduce(0, +) } }
    }

    func detail(in interval: DateInterval) throws -> Detail {
        var result = Detail()
        try db.transaction {
            let folders = try folderSource()
            let rows = try db.prepare("""
                SELECT created,\(Self.total),\(folders == nil ? "NULL" : "f.directory") FROM (\(try source())) AS m
                \(folders.map { "LEFT JOIN (\($0)) AS f ON f.id=m.sid" } ?? "")
                WHERE created >= ? AND created < ?
                """)
            rows.bind(1, Int(interval.start.timeIntervalSince1970 * 1000))
            rows.bind(2, Int(interval.end.timeIntervalSince1970 * 1000))
            while try rows.step() {
                let stamp = Date(timeIntervalSince1970: rows.double(0) / 1000), count = rows.int(1)
                result.hours[TokenRecord.localDay(stamp), default: [:]][TokenRecord.localHour(stamp), default: 0] += count
                if let folder = TokenRecord.folder(rows.text(2)) { result.projects[folder, default: 0] += count }
            }
        }
        return result
    }

    /// Session id to working folder, from whichever session tables the store has with both columns.
    /// Session counters carry no message, so usage read from them has no folder.
    private func folderSource() throws -> String? {
        let tables = try existingTables(["session", "session_v2"])
        let parts = try ["session", "session_v2"].filter(tables.contains).filter { table in
            let columns = try db.prepare("SELECT COUNT(*) FROM pragma_table_info('\(table)') WHERE name IN ('id','directory')")
            return try columns.step() && columns.int(0) == 2
        }.map { "SELECT id,directory FROM \($0)" }
        guard !parts.isEmpty else { return nil }
        return parts.count == 1 ? parts[0] : parts[0] + " UNION ALL " + parts[1] + " WHERE id NOT IN (SELECT id FROM session)"
    }

    private func source() throws -> String {
        let tables = try existingTables([Self.legacyMessageTable, Self.sessionMessageTable, "session"])
        guard let messages = Self.assistantProjection(tables: tables) else { return Self.sessions }
        // A day without usage does not justify attributing lifetime session counters to it.
        let history = try db.prepare("SELECT 1 FROM (\(messages)) WHERE created>0 AND (\(Self.total))>0 LIMIT 1")
        guard try !history.step(), tables.contains("session") else { return messages }
        // Modern schemas can have sessions without the legacy cumulative counters.
        let counters = try db.prepare("SELECT 1 FROM pragma_table_info('session') WHERE name='tokens_input'")
        return try counters.step() ? Self.sessions : messages
    }

	static let legacyMessageTable = "message"
	static let sessionMessageTable = "session_message"

	/// The subset of `names` that exist as tables. Throws when `sqlite_master` itself cannot be read.
	func existingTables(_ names: [String]) throws -> Set<String> {
		let stmt = try db.prepare("SELECT name FROM sqlite_master WHERE type='table'")
		var found = Set<String>()
		while try stmt.step() {
			if let name = stmt.text(0), names.contains(name) { found.insert(name) }
		}
		return found
	}

	/// One projection over every assistant row, whichever table holds it, with stable column names:
	/// `created, sid, t_input, t_output, t_reasoning, t_cache_read, t_cache_write`.
	/// Nil when neither table exists (a legacy session-only store).
	static func assistantProjection(tables: Set<String>) -> String? {
		let v2 = tables.contains(sessionMessageTable)
		let v1 = tables.contains(legacyMessageTable)
		let sessionMessages = """
			SELECT json_extract(data, '$.time.created') AS created, session_id AS sid,
			       json_extract(data, '$.tokens.input') AS t_input,
			       json_extract(data, '$.tokens.output') AS t_output,
			       json_extract(data, '$.tokens.reasoning') AS t_reasoning,
			       json_extract(data, '$.tokens.cache.read') AS t_cache_read,
			       json_extract(data, '$.tokens.cache.write') AS t_cache_write
			FROM session_message
			WHERE type = 'assistant'
			"""
		let legacyMessages = """
			SELECT json_extract(data, '$.time.created') AS created, session_id AS sid,
			       json_extract(data, '$.tokens.input') AS t_input,
			       json_extract(data, '$.tokens.output') AS t_output,
			       json_extract(data, '$.tokens.reasoning') AS t_reasoning,
			       json_extract(data, '$.tokens.cache.read') AS t_cache_read,
			       json_extract(data, '$.tokens.cache.write') AS t_cache_write
			FROM message
			WHERE json_extract(data, '$.role') = 'assistant'
			"""
		switch (v1, v2) {
		case (false, false): return nil
		case (true, false): return legacyMessages
		case (false, true): return sessionMessages
		case (true, true):
			return sessionMessages + "\nUNION ALL\n" + legacyMessages
				+ "  AND id NOT IN (SELECT id FROM session_message)\n"
		}
	}

	static func parseFields(_ line: String) -> [String: String] {
		var line = line
		return line.withUTF8 { bytes -> [String: String] in
			let space = UInt8(ascii: " ")
			let equals = UInt8(ascii: "=")
			let quote = UInt8(ascii: "\"")
			let backslash = UInt8(ascii: "\\")
			let count = bytes.count
			var fields: [String: String] = [:]
			var i = 0

			func slice(_ range: Range<Int>) -> String {
				range.isEmpty
					? "" : String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
			}

			while i < count {
				while i < count, bytes[i] == space { i += 1 }
				let keyStart = i
				while i < count, bytes[i] != equals, bytes[i] != space { i += 1 }
				guard i < count, bytes[i] == equals else {
					while i < count, bytes[i] != space { i += 1 }
					continue
				}
				let key = slice(keyStart..<i)
				i += 1

				let value: String
				if i < count, bytes[i] == quote {
					i += 1
					let valueStart = i
					var hasEscape = false
					while i < count {
						if bytes[i] == backslash, i + 1 < count {
							hasEscape = true
							i += 2
							continue
						}
						if bytes[i] == quote { break }
						i += 1
					}
					let valueEnd = min(i, count)
					if hasEscape {
						var out: [UInt8] = []
						out.reserveCapacity(valueEnd - valueStart)
						var j = valueStart
						while j < valueEnd {
							if bytes[j] == backslash, j + 1 < count {
								out.append(bytes[j + 1])
								j += 2
								continue
							}
							out.append(bytes[j])
							j += 1
						}
						value = String(decoding: out, as: UTF8.self)
					} else {
						value = slice(valueStart..<valueEnd)
					}
					if i < count, bytes[i] == quote { i += 1 }
				} else {
					let valueStart = i
					while i < count, bytes[i] != space { i += 1 }
					value = slice(valueStart..<i)
				}
				if !key.isEmpty { fields[key] = value }
			}

			return fields
		}
	}

}
