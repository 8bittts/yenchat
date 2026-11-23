import CoreServices
import Foundation

/// One kernel stream for the four permitted directories and Grok's log folder, including roots
/// that providers may create after enable. Dropped events request a fresh inventory.
@MainActor
final class TokenSourceWatcher {
    private var stream: FSEventStreamRef?
    private let roots: [(tool: TokenTool, path: String)]
    private let change: (TokenTool, Set<URL>?) -> Void

    init?(home: URL, change: @escaping (TokenTool, Set<URL>?) -> Void) {
        roots = TokenTool.allCases.map { ($0, Self.physicalPath($0.root(home: home))) }
            + [(.grok, Self.physicalPath(TokenTool.grok.grokLog(home: home).deletingLastPathComponent()))]
        self.change = change
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: { pointer in
                                               guard let pointer else { return nil }
                                               _ = Unmanaged<TokenSourceWatcher>.fromOpaque(pointer).retain()
                                               return pointer
                                           }, release: { pointer in
                                               if let pointer { Unmanaged<TokenSourceWatcher>.fromOpaque(pointer).release() }
                                           }, copyDescription: nil)
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
        guard let stream = FSEventStreamCreate(nil, { _, info, count, raw, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<TokenSourceWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(raw, to: NSArray.self) as? [String] ?? []
            MainActor.assumeIsolated {
                guard watcher.stream != nil else { return }
                if paths.count != count || (0..<count).contains(where: {
                    flags[$0] & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0
                }) {
                    for tool in TokenTool.allCases { watcher.change(tool, nil) }
                } else {
                    for (index, path) in paths.enumerated() { watcher.receive(path, flags: flags[index]) }
                }
            }
        }, &context, roots.map(\.path) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2,
            FSEventStreamCreateFlags(flags)) else { return nil }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); return nil
        }
        self.stream = stream
    }

    // FSEvents reports physical paths, even when Foundation abbreviates /private/var.
    // Resolve the existing parent when a provider has never created its log directory.
    private static func physicalPath(_ url: URL) -> String {
        if let resolved = realpath(url.path, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path else { return url.path }
        return (physicalPath(parent) as NSString).appendingPathComponent(url.lastPathComponent)
    }

    private func receive(_ path: String, flags: FSEventStreamEventFlags) {
        for (tool, root) in roots {
            guard path == root || path.hasPrefix(root + "/") else { continue }
            if path == root || flags & UInt32(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemRenamed)
                == UInt32(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemRenamed) {
                change(tool, nil)
                return
            }
            let url = URL(fileURLWithPath: path)
            if tool.accepts(url) || (tool == .openCode && ["opencode.db", "opencode.db-wal"].contains(url.lastPathComponent))
                || (tool == .grok && url.lastPathComponent == "unified.jsonl") {
                change(tool, [url])
            }
        }
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
