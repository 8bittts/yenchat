#if os(macOS)
import CoreServices
import Foundation

struct GitDrawerRepositoryWatchPaths: Equatable, Sendable {
    let repositoryRoot: String
    let gitDirectories: Set<String>

    var paths: [String] {
        let candidates = Set([repositoryRoot]).union(gitDirectories)
        return candidates.filter { path in
            !candidates.contains { $0 != path && path.hasPrefix($0 + "/") }
        }.sorted()
    }

    /// Run off main: linked worktrees store their private and common Git directories elsewhere.
    static func resolve(repositoryRoot: String) -> Self? {
        let root = URL(fileURLWithPath: repositoryRoot, isDirectory: true).resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        let dotGit = root.appendingPathComponent(".git", isDirectory: true)
        var directories: Set<String> = []
        if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
            let gitDirectory: URL
            if isDirectory.boolValue {
                gitDirectory = dotGit.resolvingSymlinksInPath()
            } else if let contents = readPathFile(dotGit), contents.hasPrefix("gitdir: ") {
                gitDirectory = resolvedPath(String(contents.dropFirst(8)), relativeTo: root)
            } else {
                return nil
            }
            directories.insert(gitDirectory.path)
            if let common = readPathFile(gitDirectory.appendingPathComponent("commondir")) {
                directories.insert(resolvedPath(common, relativeTo: gitDirectory).path)
            }
        }
        return Self(repositoryRoot: root.path, gitDirectories: directories)
    }

    func shouldRefresh(path: String, flags: FSEventStreamEventFlags) -> Bool {
        let rescanFlags = kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
        if flags & UInt32(rescanFlags) != 0 { return true }
        for directory in gitDirectories {
            if path == directory + "/index.lock" { return false }
            if path == directory + "/index", flags & UInt32(kFSEventStreamEventFlagOwnEvent) != 0 {
                return false
            }
        }
        return true
    }

    private static func readPathFile(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 64 * 1024), bytes.count < 64 * 1024,
              let value = String(data: bytes, encoding: .utf8) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func resolvedPath(_ value: String, relativeTo directory: URL) -> URL {
        let url = value.hasPrefix("/") ? URL(fileURLWithPath: value, isDirectory: true)
            : directory.appendingPathComponent(value, isDirectory: true)
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

@MainActor
final class GitDrawerRepositoryWatcher {
    @MainActor
    private final class CallbackState {
        let paths: GitDrawerRepositoryWatchPaths
        let onChange: @MainActor () -> Void
        var active = true
        init(paths: GitDrawerRepositoryWatchPaths, onChange: @escaping @MainActor () -> Void) {
            self.paths = paths
            self.onChange = onChange
        }
    }

    private var stream: FSEventStreamRef?
    private let state: CallbackState

    init?(paths: GitDrawerRepositoryWatchPaths, onChange: @escaping @MainActor () -> Void) {
        state = CallbackState(paths: paths, onChange: onChange)
        var context = FSEventStreamContext(version: 0,
            info: Unmanaged.passUnretained(state).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<CallbackState>.fromOpaque(pointer).retain()
                return pointer
            },
            release: { pointer in
                if let pointer { Unmanaged<CallbackState>.fromOpaque(pointer).release() }
            }, copyDescription: nil)
        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagMarkSelf
        guard let stream = FSEventStreamCreate(nil, { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let state = Unmanaged<CallbackState>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            MainActor.assumeIsolated {
                guard state.active else { return }
                let needsRefresh = paths.count != count || paths.enumerated().contains {
                    state.paths.shouldRefresh(path: $0.element, flags: eventFlags[$0.offset])
                }
                if needsRefresh { state.onChange() }
            }
        }, &context, paths.paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25, FSEventStreamCreateFlags(flags)) else { return nil }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    func stop() {
        state.active = false
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    deinit { MainActor.assumeIsolated { stop() } }
}
#endif
