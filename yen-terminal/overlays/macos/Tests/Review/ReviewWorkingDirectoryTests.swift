import Foundation
import Testing
@testable import YEN

struct ReviewWorkingDirectoryTests {
    @Test func concurrentTimelineWritersAppendWholeRowsWithoutOverwriting() throws {
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-review-timeline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stateDirectory) }
        let failureLock = NSLock()
        var failures: [String] = []

        DispatchQueue.concurrentPerform(iterations: 120) { index in
            do {
                try ReviewTimelineWriter.append(
                    event: index.isMultiple(of: 2) ? "pr-review" : "merge-conflict",
                    projectRoot: "/tmp/repo-\(index)",
                    status: "recorded",
                    detail: "row=\(index)\nkept-whole",
                    ideStateDirectory: stateDirectory.path,
                    now: Date(timeIntervalSince1970: TimeInterval(index))
                )
            } catch {
                failureLock.lock()
                failures.append(error.localizedDescription)
                failureLock.unlock()
            }
        }

        let timeline = try String(
            contentsOf: stateDirectory.appendingPathComponent("timeline.log"),
            encoding: .utf8
        )
        let rows = timeline.split(whereSeparator: \.isNewline)

        #expect(failures.isEmpty)
        #expect(rows.count == 120)
        #expect(rows.allSatisfy { $0.split(separator: "\t", omittingEmptySubsequences: false).count == 5 })
        #expect(Set(rows.compactMap { row in row.split(separator: "\t").last.map(String.init) }).count == 120)
    }

    // MARK: Negative cases (kept verbatim from the original contract).
    // nil, empty, and a guaranteed-nonexistent path must all normalize to nil.
    @Test func returnsNilForEmptyOrMissingInput() {
        #expect(ReviewWorkingDirectory.normalized(for: nil) == nil)
        #expect(ReviewWorkingDirectory.normalized(for: "") == nil)
        // Regression catch: a path under no real on-disk entry must stay nil. If the
        // `fileExists` guard were ever dropped, this would start returning a string.
        #expect(ReviewWorkingDirectory.normalized(for: "/nonexistent/path/\(UUID().uuidString)") == nil)
    }

    // MARK: (1) "~" is expanded.
    // Independent oracle: we create a real fixture directly under NSHomeDirectory() and
    // feed the impl the "~/<name>" form. The expected value is a plain string built from
    // NSHomeDirectory() + "/" + name — it never calls expandingTildeInPath or
    // standardizedFileURL on the input, so it cannot mirror the impl expression.
    @Test func tildeIsExpandedToHomeDirectory() throws {
        let fm = FileManager.default
        let name = "review-wd-tilde-\(UUID().uuidString)"
        let home = NSHomeDirectory()
        let fixture = URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fixture) }

        // Expected value derived by string composition, NOT by re-running the impl.
        let expectedHomePath = home + "/" + name

        let resolved = ReviewWorkingDirectory.normalized(for: "~/\(name)")

        // Regression catch: if expandingTildeInPath were removed, the impl would test
        // fileExists("~/...") (a literal tilde, which does not exist on disk) and return
        // nil — this assertion would fail.
        #expect(resolved == expectedHomePath)
        // Belt-and-braces: result must be absolute, never a literal tilde-prefixed string.
        #expect(resolved?.hasPrefix("~") == false)
    }

    // MARK: (2) A path that does not exist returns nil — even when the parent is real.
    // Distinct from the negative-bundle case: here the PARENT directory genuinely exists,
    // so this pins the fileExists check on the full path rather than on any prefix.
    @Test func existingParentButMissingLeafReturnsNil() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("review-wd-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        // Parent exists; leaf does not. Regression catch: a relaxed existence check that
        // only validated the parent would wrongly return a string here.
        let missingLeaf = base.appendingPathComponent("does-not-exist-\(UUID().uuidString)").path
        #expect(ReviewWorkingDirectory.normalized(for: missingLeaf) == nil)
    }

    // MARK: (3) Symlinks are NOT resolved.
    // The impl uses standardizedFileURL (lexical only). standardizedFileURL does NOT chase
    // a symlink, so a link's normalized form is the LINK path, not the target path.
    // Independent oracle: both expected forms are built from captured path-component strings
    // (link.path and target.path), never from URL(input).standardizedFileURL.path.
    @Test func symlinkIsNotResolvedToItsTarget() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("review-wd-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let target = base.appendingPathComponent("real-target", isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link-to-target")
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)

        // Captured BEFORE the call; plain strings, not impl re-runs.
        let linkPath = link.path
        let targetPath = target.path

        let resolved = ReviewWorkingDirectory.normalized(for: linkPath)

        // Regression catch: this is the load-bearing guard. If someone "improves" the impl
        // by swapping standardizedFileURL -> resolvingSymlinksInPath(), the symlink would be
        // chased and `resolved` would become targetPath, flipping BOTH assertions below.
        #expect(resolved == linkPath)        // must come back UNRESOLVED (== the link path)
        #expect(resolved != targetPath)      // must NOT be its symlink target
    }

    // MARK: (4) ".." is collapsed lexically.
    // The component before ".." (here `subdir`, a real directory, NOT a symlink) makes the
    // lexical collapse of `base/subdir/..` to `base` correct on disk. fileExists also follows
    // "..", so the existence guard passes.
    // Independent oracle: expected value is `base.path`, the directory we created — captured
    // independently, not URL("<base>/subdir/..").standardizedFileURL.path.
    @Test func dotDotIsCollapsedToParent() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("review-wd-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let subdir = base.appendingPathComponent("subdir", isDirectory: true)
        try fm.createDirectory(at: subdir, withIntermediateDirectories: true)

        let basePath = base.path                       // captured independently
        let dotDotInput = basePath + "/subdir/.."       // string-built input

        let resolved = ReviewWorkingDirectory.normalized(for: dotDotInput)

        // Regression catch: if standardization (the ".." collapse) were dropped, the result
        // would still contain "/subdir/.." — this assertion would fail.
        #expect(resolved == basePath)
        #expect(resolved?.contains("..") == false)
    }

    // MARK: (5) A trailing slash is removed.
    // URL.path strips a trailing slash; standardizedFileURL preserves that. Independent oracle:
    // expected value is `base.path` (no trailing slash) captured independently; the input is
    // the same string with a "/" appended.
    @Test func trailingSlashIsRemoved() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("review-wd-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        let basePath = base.path                 // no trailing slash, captured independently
        let trailingInput = basePath + "/"       // string-built input with trailing slash

        let resolved = ReviewWorkingDirectory.normalized(for: trailingInput)

        // Regression catch: if normalization stopped trimming, the result would keep the
        // trailing "/" — both assertions would fail.
        #expect(resolved == basePath)
        #expect(resolved?.hasSuffix("/") == false)
    }
}
