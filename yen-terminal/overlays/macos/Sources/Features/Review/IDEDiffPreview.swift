#if os(macOS)
import Foundation

enum IDEDiffPreviewSource: String, Equatable, Hashable, Sendable {
    case delta
    case plain

    var label: String {
        switch self {
        case .delta:
            return "Delta Preview"
        case .plain:
            return "Plain Preview"
        }
    }
}

struct IDEDiffRenderedPreview: Equatable, Hashable, Sendable {
    let text: String
    let source: IDEDiffPreviewSource
}

enum IDEDiffPreviewBuilder {
    static func syntheticUnifiedDiff(
        path: String,
        startLine: Int,
        oldLines: [String],
        newLines: [String]
    ) -> String {
        var lines = [
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -\(rangeText(start: startLine, count: oldLines.count)) +\(rangeText(start: startLine, count: newLines.count)) @@",
        ]
        lines.append(contentsOf: oldLines.map { "-\($0)" })
        lines.append(contentsOf: newLines.map { "+\($0)" })
        return lines.joined(separator: "\n")
    }

    private static func rangeText(start: Int, count: Int) -> String {
        let normalizedStart = max(1, start)
        return count == 1 ? "\(normalizedStart)" : "\(normalizedStart),\(count)"
    }
}

enum IDEDiffPreviewRenderer {
    /// Renders the merge-conflict resolution patch without blocking the main
    /// actor. PR Review intentionally displays its raw unified diff and does not
    /// launch a second renderer for every file or hunk.
    static func renderAsync(
        diff: String,
        renderCommand: ((String) -> String?)? = nil
    ) async -> IDEDiffRenderedPreview {
        let normalizedDiff = diff.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalizedDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return IDEDiffRenderedPreview(text: normalizedDiff, source: .plain)
        }

        if let renderCommand,
           let rendered = renderCommand(normalizedDiff),
           !rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return IDEDiffRenderedPreview(
                text: stripANSI(from: rendered),
                source: .delta
            )
        }

        if let deltaPath = cachedDeltaPath,
           let rendered = await runDeltaPreviewOffMainActor(diff: normalizedDiff, binaryPath: deltaPath),
           !rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return IDEDiffRenderedPreview(
                text: stripANSI(from: rendered),
                source: .delta
            )
        }

        return IDEDiffRenderedPreview(text: normalizedDiff, source: .plain)
    }

    /// Process-lifetime memo of the resolved `delta` binary path; binary presence
    /// won't change mid-process, so resolve (incl. the `nil`/absent case) only once.
    private static let cachedDeltaPath: String? = resolveDeltaBinary()

    private static func resolveDeltaBinary() -> String? {
        let fileManager = FileManager.default

        if let resourcePath = Bundle.main.resourcePath {
            let bundledPath = URL(fileURLWithPath: resourcePath)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("delta", isDirectory: false)
                .path
            if fileManager.isExecutableFile(atPath: bundledPath) {
                return bundledPath
            }
        }

        var devRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            devRoot.deleteLastPathComponent()
        }
        let devPath = devRoot
            .appendingPathComponent("customizations", isDirectory: true)
            .appendingPathComponent("vendor", isDirectory: true)
            .appendingPathComponent("delta", isDirectory: true)
            .appendingPathComponent("delta", isDirectory: false)
            .path
        if fileManager.isExecutableFile(atPath: devPath) {
            return devPath
        }

        return nil
    }

    private enum DeltaPreviewSpawnError: Error {
        case spawnFailed
    }

    /// Routes the delta subprocess through `IDEBlockingProcessRunner` (its own
    /// detached task + concurrent stdin/stdout drains) so the merge-conflict
    /// preview never forks/execs on the main actor. Launch failure or a non-zero
    /// exit yields nil and therefore the plain-diff fallback.
    private static func runDeltaPreviewOffMainActor(diff: String, binaryPath: String) async -> String? {
        do {
            let output = try await IDEBlockingProcessRunner.run(
                executableURL: URL(fileURLWithPath: binaryPath),
                arguments: ["--paging=never"],
                currentDirectory: FileManager.default.currentDirectoryPath,
                allowAnyExitCode: true,
                standardInput: Data(diff.utf8),
                toolUnavailable: DeltaPreviewSpawnError.spawnFailed,
                commandFailed: { _ in DeltaPreviewSpawnError.spawnFailed }
            )
            guard output.terminationStatus == 0 else { return nil }
            return output.stdout
        } catch {
            return nil
        }
    }

    /// ANSI escape-sequence matchers, compiled once. The patterns are constant, so
    /// recompiling them on every `stripANSI` call was pure waste on the diff-render path.
    private static let ansiEscapeRegexes: [NSRegularExpression] = {
        [
            #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#,
            #"\u{001B}\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{001B}\\)"#,
        ].compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    static func stripANSI(from value: String) -> String {
        var cleaned = value
        for regex in ansiEscapeRegexes {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        return cleaned
    }
}
#endif
