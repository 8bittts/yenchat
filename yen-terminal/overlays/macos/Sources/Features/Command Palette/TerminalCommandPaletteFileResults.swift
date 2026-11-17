import Foundation

enum TerminalCommandPaletteFileResults {
    static func fileResults(
        query: String,
        files: [TerminalCommandPaletteIndexedFile]
    ) -> [TerminalCommandPaletteSearchResult] {
        files.compactMap { file in
            let score = max(
                TerminalCommandPaletteSearchEngine.matchScore(query: query, normalizedText: file.lowercasedRelativePath),
                TerminalCommandPaletteSearchEngine.matchScore(query: query, normalizedText: file.lowercasedBaseName)
            )
            guard score > 0 else { return nil }

            return TerminalCommandPaletteSearchResult(
                source: .file,
                score: TerminalCommandPaletteResultSource.file.weight + score,
                targetKey: file.relativePath,
                previewKey: file.baseName,
                title: file.baseName,
                subtitle: file.relativePath == file.baseName ? nil : file.relativePath,
                execution: .openLocation(
                    TerminalCommandPaletteLocation(
                        path: file.absolutePath,
                        relativePath: file.relativePath,
                        line: nil,
                        column: nil,
                        severity: nil,
                        code: nil,
                        diagnosticSource: nil
                    )
                )
            )
        }
    }

}
