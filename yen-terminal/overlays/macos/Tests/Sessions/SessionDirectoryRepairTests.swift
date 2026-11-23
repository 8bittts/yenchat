import Darwin
import Foundation
import Testing
@testable import YEN

// The app's repair of the session directory never opens it further and
// never stops on a failed change (_docs/01-architecture.md -> Persistent
// sessions; _docs/04-security.md -> What the session directory exposes).
// PersistentSessionsTests covers the 0750 repair and the symlink rule.

/// A short /tmp path, as the socket limit needs, never the user's state.
private func scratchDirectory(_ prefix: String) throws -> String {
    let path = "/tmp/\(prefix)-\(UUID().uuidString.prefix(8))"
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

private func mode(_ path: String) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue
}

@Suite(.serialized)
struct SessionDirectoryRepairTests {
    private func sessionDirectory(directory: Int, logs: Int, bin: Int) throws -> (root: String, path: String) {
        let root = try scratchDirectory("ydr")
        let path = root + "/zmx"
        for name in ["/logs", "/bin"] {
            try FileManager.default.createDirectory(atPath: path + name, withIntermediateDirectories: true)
        }
        chmod(path + "/logs", mode_t(logs))
        chmod(path + "/bin", mode_t(bin))
        chmod(path, mode_t(directory))
        return (root, path)
    }

    private func remove(_ root: String) {
        for name in ["/zmx/logs", "/zmx/bin", "/zmx"] {
            chflags(root + name, 0)
            chmod(root + name, 0o700)
        }
        try? FileManager.default.removeItem(atPath: root)
    }

    @Test func onlyGroupAndOtherAccessIsRemoved() throws {
        let (root, path) = try sessionDirectory(directory: 0o750, logs: 0o000, bin: 0o570)
        defer { remove(root) }
        PersistentSessions.secureSocketDirectory(path)
        #expect(mode(path) == 0o700)
        // A deliberately locked directory stays locked, and owner bits are never added.
        #expect(mode(path + "/logs") == 0o000)
        #expect(mode(path + "/bin") == 0o500)
    }

    @Test func aChangeThatFailsLeavesThatDirectoryAndRepairsTheRest() throws {
        let (root, path) = try sessionDirectory(directory: 0o750, logs: 0o750, bin: 0o750)
        defer { remove(root) }
        // An immutable directory refuses fchmod, even from its owner.
        try #require(chflags(path + "/logs", UInt32(UF_IMMUTABLE)) == 0)
        PersistentSessions.secureSocketDirectory(path)
        #expect(mode(path) == 0o700)
        #expect(mode(path + "/logs") == 0o750)
        #expect(mode(path + "/bin") == 0o700)
    }
}
