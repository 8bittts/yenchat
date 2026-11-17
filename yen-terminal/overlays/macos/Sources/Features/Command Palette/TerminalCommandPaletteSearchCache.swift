import Foundation

struct TerminalCommandPaletteTextDocument: Sendable {
    let contents: String
    let lowercasedLines: [String]
    let byteCost: Int

    init(_ contents: String) {
        self.contents = contents
        var lines: [String] = []
        contents.enumerateLines { line, _ in lines.append(line.lowercased()) }
        lowercasedLines = lines
        byteCost = contents.utf8.count + lines.reduce(0) { $0 + $1.utf8.count }
            + lines.count * MemoryLayout<String>.stride
    }
}

/// Session-owned text storage. All mutable state is protected by the lock; file reads run outside it.
final class TerminalCommandPaletteSearchCache: @unchecked Sendable {
    struct Fingerprint: Equatable, Sendable {
        let size: UInt64
        let modified: Date
        let inode: UInt64
        let permissions: UInt16

        nonisolated static func read(_ path: String) -> Self? {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber,
                  let modified = attributes[.modificationDate] as? Date,
                  let inode = attributes[.systemFileNumber] as? NSNumber,
                  let permissions = attributes[.posixPermissions] as? NSNumber else { return nil }
            return Self(size: size.uint64Value, modified: modified, inode: inode.uint64Value,
                permissions: permissions.uint16Value)
        }

        static let synthetic = Self(size: 0, modified: .distantPast, inode: 0, permissions: 0)
    }

    struct ContentScan: Sendable {
        let root: String
        let query: String
        let fingerprints: [String: Fingerprint]
        let matchingPaths: Set<String>
    }

    struct SymbolScan: Sendable {
        let root: String
        let files: [TerminalCommandPaletteIndexedFile]
        let symbols: [TerminalCommandPaletteIndexedSymbol]
        let fingerprints: [String: Fingerprint]
    }

    struct Ticket: Sendable {
        fileprivate let epoch: UInt64
        fileprivate let request: UInt64
        let content: ContentScan?
        let symbols: SymbolScan?
    }

    struct Read {
        let document: TerminalCommandPaletteTextDocument
        let fingerprint: Fingerprint?
    }

    private struct Entry {
        let fingerprint: Fingerprint
        let document: TerminalCommandPaletteTextDocument
        var access: UInt64
    }

    private let lock = NSLock()
    private let maximumBytes: Int
    private let maximumEntries: Int
    private let fingerprintReader: @Sendable (String) -> Fingerprint?
    private var entries: [String: Entry] = [:]
    private var bytes = 0
    private var access: UInt64 = 0
    private var epoch: UInt64 = 0
    private var request: UInt64 = 0
    private var content: ContentScan?
    private var symbols: SymbolScan?

    init(maximumBytes: Int = 16 * 1024 * 1024, maximumEntries: Int = 3000,
         fingerprint: @escaping @Sendable (String) -> Fingerprint? = { Fingerprint.read($0) }) {
        self.maximumBytes = max(0, maximumBytes)
        self.maximumEntries = max(0, maximumEntries)
        fingerprintReader = fingerprint
    }

    var retainedBytes: Int { lock.lock(); defer { lock.unlock() }; return bytes }
    var retainedEntries: Int { lock.lock(); defer { lock.unlock() }; return entries.count }

    func fingerprint(for path: String) -> Fingerprint? { fingerprintReader(path) }

    func begin() -> Ticket {
        lock.lock()
        defer { lock.unlock() }
        request &+= 1
        return Ticket(epoch: epoch, request: request, content: content, symbols: symbols)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        epoch &+= 1
        request &+= 1
        entries.removeAll()
        bytes = 0
        content = nil
        symbols = nil
    }

    func read(_ path: String, fingerprint: Fingerprint?, ticket: Ticket,
              loader: (String) -> String?) -> Read? {
        lock.lock()
        guard epoch == ticket.epoch else { lock.unlock(); return nil }
        if let fingerprint, var entry = entries[path], entry.fingerprint == fingerprint {
            access &+= 1
            entry.access = access
            entries[path] = entry
            lock.unlock()
            return Read(document: entry.document, fingerprint: fingerprint)
        }
        if let removed = entries.removeValue(forKey: path) { bytes -= removed.document.byteCost }
        lock.unlock()

        guard !Task.isCancelled, let contents = loader(path) else { return nil }
        let document = TerminalCommandPaletteTextDocument(contents)
        let stable = fingerprint != nil && fingerprintReader(path) == fingerprint
        if stable, let fingerprint { store(document, path: path, fingerprint: fingerprint, ticket: ticket) }
        return Read(document: document, fingerprint: stable ? fingerprint : nil)
    }

    private func store(_ document: TerminalCommandPaletteTextDocument, path: String,
                       fingerprint: Fingerprint, ticket: Ticket) {
        lock.lock()
        defer { lock.unlock() }
        guard epoch == ticket.epoch, !Task.isCancelled,
              document.byteCost <= maximumBytes, maximumEntries > 0 else { return }
        if let removed = entries.removeValue(forKey: path) { bytes -= removed.document.byteCost }
        while bytes + document.byteCost > maximumBytes || entries.count >= maximumEntries {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key,
                  let removed = entries.removeValue(forKey: oldest) else { break }
            bytes -= removed.document.byteCost
        }
        access &+= 1
        entries[path] = Entry(fingerprint: fingerprint, document: document, access: access)
        bytes += document.byteCost
    }

    func record(content: ContentScan?, symbols: SymbolScan?, ticket: Ticket) {
        lock.lock()
        defer { lock.unlock() }
        guard epoch == ticket.epoch, request == ticket.request, !Task.isCancelled else { return }
        self.content = content
        self.symbols = symbols
    }
}
