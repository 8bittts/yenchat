import Foundation

enum TerminalCommandPaletteDiagnosticsResults {
    static func diagnosticsResults(
        query: String,
        projectRoot: String,
        projectHash: String? = nil,
        ideStateDirectoryOverride: String?
    ) -> [TerminalCommandPaletteSearchResult] {
        let diagnosticsFile = diagnosticsFilePath(
            projectRoot: projectRoot,
            projectHash: projectHash,
            ideStateDirectoryOverride: ideStateDirectoryOverride
        )
        guard let contents = try? String(contentsOfFile: diagnosticsFile, encoding: .utf8),
              let data = contents.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = payload["items"] as? [[String: Any]] else {
            return []
        }

        var results: [TerminalCommandPaletteSearchResult] = []
        results.reserveCapacity(items.count)

        for item in items {
            guard !Task.isCancelled else { break }
            let filePath = String(describing: item["file"] ?? item["path"] ?? "")
            let line = item["line"] as? Int ?? 1
            let col = item["col"] as? Int ?? 1
            let severity = String(describing: item["severity"] ?? "error")
            let message = String(describing: item["message"] ?? "")
            let code = String(describing: item["code"] ?? "")
            let diagnosticSource = String(describing: item["source"] ?? "")
            let location = "\(relativePath(for: filePath, root: projectRoot)):\(line):\(col)"
            let score = max(
                TerminalCommandPaletteSearchEngine.matchScore(query: query, text: message),
                TerminalCommandPaletteSearchEngine.matchScore(query: query, text: location),
                TerminalCommandPaletteSearchEngine.matchScore(query: query, text: code)
            )
            guard score > 0 else { continue }
            let preview = TerminalCommandPaletteSearchEngine.clipText("\(severity): \(message)")
            results.append(
                TerminalCommandPaletteSearchResult(
                    source: .diagnostic,
                    score: TerminalCommandPaletteResultSource.diagnostic.weight + score,
                    targetKey: location,
                    previewKey: preview,
                    title: location,
                    subtitle: preview,
                    execution: .openLocation(
                        TerminalCommandPaletteLocation(
                            path: filePath,
                            relativePath: relativePath(for: filePath, root: projectRoot),
                            line: line,
                            column: col,
                            severity: severity,
                            code: code.isEmpty ? nil : code,
                            diagnosticSource: diagnosticSource.isEmpty ? nil : diagnosticSource
                        )
                    )
                )
            )
        }

        return results
    }

    private static func diagnosticsFilePath(
        projectRoot: String,
        projectHash: String?,
        ideStateDirectoryOverride: String?
    ) -> String {
        let hash = projectHash ?? TerminalCommandPaletteProjectContextResolver.projectHash(root: projectRoot)
        return URL(fileURLWithPath: ReviewIDEStateDirectory.resolved(override: ideStateDirectoryOverride))
            .appendingPathComponent("lsp")
            .appendingPathComponent(hash)
            .appendingPathComponent("diagnostics.json")
            .path
    }

    private static func relativePath(for pathText: String, root: String) -> String {
        let normalizedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        let normalizedPath = URL(fileURLWithPath: pathText).resolvingSymlinksInPath().path
        guard normalizedPath.hasPrefix("\(normalizedRoot)/") else {
            return normalizedPath
        }
        return String(normalizedPath.dropFirst(normalizedRoot.count + 1))
    }

}
