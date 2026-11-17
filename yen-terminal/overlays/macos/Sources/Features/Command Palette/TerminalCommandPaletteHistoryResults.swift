import Foundation

enum TerminalCommandPaletteHistoryResults {
    static func historyResults(
        query: String,
        projectRoot: String,
        projectHash: String? = nil,
        ideStateDirectoryOverride: String?
    ) -> [TerminalCommandPaletteSearchResult] {
        let historyFile = historyFilePath(
            projectRoot: projectRoot,
            projectHash: projectHash,
            ideStateDirectoryOverride: ideStateDirectoryOverride
        )
        guard let contents = try? String(contentsOfFile: historyFile, encoding: .utf8) else {
            return []
        }

        let lines = contents.split(whereSeparator: \.isNewline)
        var results: [TerminalCommandPaletteSearchResult] = []
        results.reserveCapacity(min(TerminalCommandPaletteSearchEngine.maxHistoryEntries, lines.count))

        for (offset, line) in lines.suffix(TerminalCommandPaletteSearchEngine.maxHistoryEntries).enumerated() {
            if Task.isCancelled {
                break
            }
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }

            let timestamp = String(fields[0])
            let cwd = String(fields[1])
            let command = String(fields[2])
            let score = TerminalCommandPaletteSearchEngine.matchScore(query: query, text: command)
            guard score > 0 else { continue }

            let cwdRelative: String
            if cwd == projectRoot {
                cwdRelative = "."
            } else if cwd.hasPrefix("\(projectRoot)/") {
                cwdRelative = String(cwd.dropFirst(projectRoot.count + 1))
            } else {
                cwdRelative = cwd
            }

            let preview = "\(command) (cwd=\(cwdRelative))"
            results.append(
                TerminalCommandPaletteSearchResult(
                source: .history,
                score: TerminalCommandPaletteResultSource.history.weight + score,
                targetKey: "\(timestamp)#\(String(format: "%06d", offset))",
                previewKey: preview,
                title: command,
                subtitle: "cwd=\(cwdRelative)",
                execution: .insertHistoryCommand(command: command)
                )
            )
        }

        return results
    }

    private static func historyFilePath(
        projectRoot: String,
        projectHash: String?,
        ideStateDirectoryOverride: String?
    ) -> String {
        let hash = projectHash ?? TerminalCommandPaletteProjectContextResolver.projectHash(root: projectRoot)
        return URL(fileURLWithPath: ReviewIDEStateDirectory.resolved(override: ideStateDirectoryOverride))
            .appendingPathComponent("history")
            .appendingPathComponent("\(hash).log")
            .path
    }

}
