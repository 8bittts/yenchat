import Foundation

enum TerminalCommandPaletteContentResults {
    static func contentResults(
        query: String,
        files: [TerminalCommandPaletteIndexedFile],
        maximumMatches: Int = TerminalCommandPaletteSearchEngine.maxContentMatches,
        textContents: (TerminalCommandPaletteIndexedFile) -> TerminalCommandPaletteTextDocument?
    ) -> [TerminalCommandPaletteSearchResult] {
        var results: [TerminalCommandPaletteSearchResult] = []
        results.reserveCapacity(min(maximumMatches, files.count))

        for file in files {
            if Task.isCancelled {
                break
            }
            if results.count >= maximumMatches {
                break
            }
            guard let document = textContents(file) else { continue }

            var lineNumber = 0
            document.contents.enumerateLines { line, stop in
                if Task.isCancelled {
                    stop = true
                    return
                }
                lineNumber += 1
                let score = TerminalCommandPaletteSearchEngine.matchScore(query: query, normalizedText: document.lowercasedLines[lineNumber - 1])
                guard score > 0 else { return }

                let column = firstMatchColumn(query: query, line: line)
                let target = locationTarget(
                    relativePath: file.relativePath,
                    line: lineNumber,
                    column: column
                )
                let preview = TerminalCommandPaletteSearchEngine.clipText(line)
                results.append(
                    TerminalCommandPaletteSearchResult(
                        source: .content,
                        score: TerminalCommandPaletteResultSource.content.weight + score,
                        targetKey: target,
                        previewKey: preview,
                        title: target,
                        subtitle: preview,
                        execution: .openLocation(
                            TerminalCommandPaletteLocation(
                                path: file.absolutePath,
                                relativePath: file.relativePath,
                                line: lineNumber,
                                column: column,
                                severity: nil,
                                code: nil,
                                diagnosticSource: nil
                            )
                        )
                    )
                )
                if results.count >= maximumMatches {
                    stop = true
                }
            }
        }

        return results
    }

    private static func locationTarget(relativePath: String, line: Int?, column: Int?) -> String {
        guard let line else { return relativePath }
        guard let column else { return "\(relativePath):\(line)" }
        return "\(relativePath):\(line):\(column)"
    }

    private static func firstMatchColumn(query: String, line: String) -> Int? {
        guard let range = line.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return nil
        }
        return line.distance(from: line.startIndex, to: range.lowerBound) + 1
    }

}
