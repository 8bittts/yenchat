import Foundation

/// Copies a few members out of one JSON record without parsing the rest.
///
/// A Claude Code assistant record carries its usage beside the whole reply: text, tool input and
/// signed thinking blocks. Parsing all of it to read a dozen numbers was most of the reader's work.
/// The projection walks the record's structure, skips every value it was not asked for, and returns
/// a small JSON document that holds only the kept members, byte for byte. `JSONSerialization` then
/// parses that document, so numbers, strings and escapes are read by the same parser as before.
///
/// It returns nil when the record is not an object or its structure ends early. Skipped values are
/// not validated.
enum TokenRecordProjection {
    /// `paths` are member paths from the root, such as `["message", "usage"]`. A path's last member
    /// is copied whole. Keys are compared as written, so a key spelled with an escape is not matched.
    static func project(_ bytes: UnsafeRawBufferPointer, keeping paths: [[String]]) -> Data? {
        guard let base = bytes.baseAddress else { return nil }
        var scanner = Scanner(base: base.assumingMemoryBound(to: UInt8.self), count: bytes.count)
        var output = Data()
        scanner.skipWhitespace()
        guard scanner.object(keeping: paths.map { $0.map { Array($0.utf8) } }, into: &output) else { return nil }
        scanner.skipWhitespace()
        return scanner.atEnd ? output : nil
    }

    private struct Scanner {
        let base: UnsafePointer<UInt8>
        let count: Int
        var position = 0

        var atEnd: Bool { position >= count }

        mutating func skipWhitespace() {
            while position < count, [0x20, 0x09, 0x0A, 0x0D].contains(base[position]) { position += 1 }
        }

        /// Reads the object at the cursor and writes the kept members. `paths` are relative to it.
        mutating func object(keeping paths: [[[UInt8]]], into output: inout Data) -> Bool {
            guard position < count, base[position] == UInt8(ascii: "{") else { return false }
            position += 1
            output.append(UInt8(ascii: "{"))
            var wrote = false
            skipWhitespace()
            if position < count, base[position] == UInt8(ascii: "}") {
                position += 1
                output.append(UInt8(ascii: "}"))
                return true
            }
            while true {
                skipWhitespace()
                let keyStart = position
                guard string() else { return false }
                let key = UnsafeBufferPointer(start: base + keyStart + 1, count: position - keyStart - 2)
                skipWhitespace()
                guard position < count, base[position] == UInt8(ascii: ":") else { return false }
                position += 1
                skipWhitespace()
                let matching = paths.filter { $0.first.map { $0.elementsEqual(key) } ?? false }
                if matching.isEmpty {
                    guard value() else { return false }
                } else {
                    if wrote { output.append(UInt8(ascii: ",")) }
                    wrote = true
                    output.append(base + keyStart, count: position - keyStart)
                    let deeper = matching.map { Array($0.dropFirst()) }
                    if deeper.contains(where: \.isEmpty) || position >= count || base[position] != UInt8(ascii: "{") {
                        // Copy the whole value: it was asked for, or it is not an object to look inside.
                        let valueStart = position
                        guard value() else { return false }
                        output.append(base + valueStart, count: position - valueStart)
                    } else {
                        guard object(keeping: deeper, into: &output) else { return false }
                    }
                }
                skipWhitespace()
                guard position < count else { return false }
                if base[position] == UInt8(ascii: ",") { position += 1; continue }
                guard base[position] == UInt8(ascii: "}") else { return false }
                position += 1
                output.append(UInt8(ascii: "}"))
                return true
            }
        }

        /// Moves past the string at the cursor, quotes included.
        mutating func string() -> Bool {
            guard position < count, base[position] == UInt8(ascii: "\"") else { return false }
            var cursor = position + 1
            while cursor < count, let found = memchr(base + cursor, 0x22, count - cursor) {
                let quote = base.distance(to: found.assumingMemoryBound(to: UInt8.self))
                // A quote after an odd run of backslashes is escaped.
                var slashes = 0
                while quote - slashes - 1 > position, base[quote - slashes - 1] == UInt8(ascii: "\\") { slashes += 1 }
                cursor = quote + 1
                if slashes.isMultiple(of: 2) {
                    position = cursor
                    return true
                }
            }
            return false
        }

        /// Moves past the value at the cursor without reading it.
        mutating func value() -> Bool {
            guard position < count else { return false }
            switch base[position] {
            case UInt8(ascii: "\""):
                return string()
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                var depth = 0
                while position < count {
                    switch base[position] {
                    case UInt8(ascii: "\""):
                        guard string() else { return false }
                        continue
                    case UInt8(ascii: "{"), UInt8(ascii: "["):
                        depth += 1
                    case UInt8(ascii: "}"), UInt8(ascii: "]"):
                        depth -= 1
                        if depth == 0 {
                            position += 1
                            return true
                        }
                    default:
                        break
                    }
                    position += 1
                }
                return false
            default:
                // A number or a literal ends at the next separator.
                let start = position
                while position < count, ![0x2C, 0x7D, 0x5D, 0x20, 0x09, 0x0A, 0x0D].contains(base[position]) { position += 1 }
                return position > start
            }
        }
    }
}
