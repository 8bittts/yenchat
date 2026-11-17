import Foundation

enum TerminalCommandPaletteSymbolResults {
    static func symbolResults(
        query: String,
        symbols: [TerminalCommandPaletteIndexedSymbol]
    ) -> [TerminalCommandPaletteSearchResult] {
        symbols.compactMap { symbol in
            let score = max(
                TerminalCommandPaletteSearchEngine.matchScore(query: query, normalizedText: symbol.lowercasedSymbolName),
                TerminalCommandPaletteSearchEngine.matchScore(query: query, normalizedText: symbol.lowercasedKind),
                TerminalCommandPaletteSearchEngine.matchScore(query: query, normalizedText: symbol.lowercasedRelativePath)
            )
            guard score > 0 else { return nil }

            let subtitle = "\(symbol.kind) • \(symbol.location)"
            return TerminalCommandPaletteSearchResult(
                source: .symbol,
                score: TerminalCommandPaletteResultSource.symbol.weight + score,
                targetKey: symbol.location,
                previewKey: subtitle,
                title: "\(symbol.symbolName) [\(symbol.kind)]",
                subtitle: subtitle,
                execution: .openLocation(
                    TerminalCommandPaletteLocation(
                        path: symbol.absolutePath,
                        relativePath: symbol.relativePath,
                        line: symbol.line,
                        column: symbol.column,
                        severity: nil,
                        code: nil,
                        diagnosticSource: nil
                    )
                )
            )
        }
    }

}
