import Foundation

enum TerminalCommandPaletteResultSource: String, Sendable {
    case action
    case symbol
    case file
    case content
    case diagnostic
    case history

    var rank: Int {
        switch self {
        case .action: 1
        case .symbol: 2
        case .file: 3
        case .content: 4
        case .diagnostic: 5
        case .history: 6
        }
    }

    var weight: Int {
        switch self {
        case .action: 80
        case .symbol: 75
        case .file: 70
        case .diagnostic: 65
        case .history: 60
        case .content: 50
        }
    }
}

struct TerminalCommandPaletteContext: Sendable {
    let projectRoot: String?
    let runtime: Set<String>
    let tooling: Set<String>
    let projectHash: String?

    init(projectRoot: String?, runtime: Set<String>, tooling: Set<String>) {
        self.projectRoot = projectRoot
        self.runtime = runtime
        self.tooling = tooling
        projectHash = projectRoot.map(TerminalCommandPaletteProjectContextResolver.projectHash(root:))
    }

    static let empty = TerminalCommandPaletteContext(projectRoot: nil, runtime: [], tooling: [])

    var contextTags: Set<String> {
        runtime.union(tooling)
    }
}

struct TerminalCommandPaletteActionSearchDescriptor: Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let description: String?
    let searchTags: [String]
    /// Breaks score ties in place of the title. Only the Hosts rows set it,
    /// to keep their shared order (`RemoteHostsPaletteRows.orderKey`).
    var orderKey: String? = nil
}

enum TerminalCommandPaletteExecutionTarget: Sendable {
    case action(id: String)
    case openLocation(TerminalCommandPaletteLocation)
    case insertHistoryCommand(command: String)
}

struct TerminalCommandPaletteSearchResult: Sendable {
    let source: TerminalCommandPaletteResultSource
    let score: Int
    let targetKey: String
    let previewKey: String
    let title: String
    let subtitle: String?
    let execution: TerminalCommandPaletteExecutionTarget
}

struct TerminalCommandPaletteSearchOutput: Sendable {
    let results: [TerminalCommandPaletteSearchResult]
    let cachedFiles: [TerminalCommandPaletteIndexedFile]?
    let cachedSymbols: [TerminalCommandPaletteIndexedSymbol]?
}

struct TerminalCommandPaletteIndexedFile: Equatable, Sendable {
    let absolutePath: String
    let relativePath: String
    let baseName: String
    let lowercasedRelativePath: String
    let lowercasedBaseName: String

    init(absolutePath: String, relativePath: String, baseName: String) {
        self.absolutePath = absolutePath
        self.relativePath = relativePath
        self.baseName = baseName
        lowercasedRelativePath = relativePath.lowercased()
        lowercasedBaseName = baseName.lowercased()
    }
}

struct TerminalCommandPaletteIndexedSymbol: Sendable {
    let absolutePath: String
    let relativePath: String
    let symbolName: String
    let kind: String
    let line: Int
    let column: Int
    let lowercasedSymbolName: String
    let lowercasedKind: String
    let lowercasedRelativePath: String
    let localizedSortName: String

    init(absolutePath: String, relativePath: String, symbolName: String, kind: String, line: Int, column: Int) {
        self.absolutePath = absolutePath
        self.relativePath = relativePath
        self.symbolName = symbolName
        self.kind = kind
        self.line = line
        self.column = column
        lowercasedSymbolName = symbolName.lowercased()
        lowercasedKind = kind.lowercased()
        lowercasedRelativePath = relativePath.lowercased()
        localizedSortName = symbolName.localizedLowercase
    }

    var location: String {
        "\(relativePath):\(line):\(column)"
    }
}

enum TerminalCommandPaletteSearchEngine {
    static let maxFileCount = 3000
    static let maxContentMatches = 1200
    static let maxHistoryEntries = 500
    static let maxTextFileBytes = 1_048_576
    static let minQueryLengthForFileSearch = 2
    static let minQueryLengthForContentSearch = 3
    typealias TextContentLoader = (String) -> String?

    static func search(
        query: String,
        context: TerminalCommandPaletteContext,
        actions: [TerminalCommandPaletteActionSearchDescriptor],
        cachedFiles: [TerminalCommandPaletteIndexedFile]?,
        cachedSymbols: [TerminalCommandPaletteIndexedSymbol]?,
        ideStateDirectoryOverride: String? = nil,
        cache: TerminalCommandPaletteSearchCache? = nil
    ) -> TerminalCommandPaletteSearchOutput {
        search(
            query: query,
            context: context,
            actions: actions,
            cachedFiles: cachedFiles,
            cachedSymbols: cachedSymbols,
            ideStateDirectoryOverride: ideStateDirectoryOverride,
            cache: cache ?? TerminalCommandPaletteSearchCache(),
            validateCachedSymbols: cache != nil,
            textContents: TerminalCommandPaletteSearchIndex.loadTextContents(at:)
        )
    }

    static func searchForTesting(
        query: String,
        context: TerminalCommandPaletteContext,
        actions: [TerminalCommandPaletteActionSearchDescriptor],
        cachedFiles: [TerminalCommandPaletteIndexedFile]?,
        cachedSymbols: [TerminalCommandPaletteIndexedSymbol]?,
        cache: TerminalCommandPaletteSearchCache? = nil,
        textContents: TextContentLoader
    ) -> TerminalCommandPaletteSearchOutput {
        search(
            query: query,
            context: context,
            actions: actions,
            cachedFiles: cachedFiles,
            cachedSymbols: cachedSymbols,
            ideStateDirectoryOverride: nil,
            cache: cache ?? TerminalCommandPaletteSearchCache(fingerprint: {
                TerminalCommandPaletteSearchCache.Fingerprint.read($0) ?? .synthetic
            }),
            validateCachedSymbols: cache != nil,
            textContents: textContents
        )
    }

    private static func search(
        query: String,
        context: TerminalCommandPaletteContext,
        actions: [TerminalCommandPaletteActionSearchDescriptor],
        cachedFiles: [TerminalCommandPaletteIndexedFile]?,
        cachedSymbols: [TerminalCommandPaletteIndexedSymbol]?,
        ideStateDirectoryOverride: String?,
        cache: TerminalCommandPaletteSearchCache,
        validateCachedSymbols: Bool,
        textContents: TextContentLoader
    ) -> TerminalCommandPaletteSearchOutput {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return TerminalCommandPaletteSearchOutput(
                results: [],
                cachedFiles: cachedFiles,
                cachedSymbols: cachedSymbols
            )
        }
        guard !Task.isCancelled else {
            return TerminalCommandPaletteSearchOutput(
                results: [],
                cachedFiles: cachedFiles,
                cachedSymbols: cachedSymbols
            )
        }

        let queryLowercased = trimmedQuery.lowercased()
        var indexedFiles = cachedFiles
        var indexedSymbols = cachedSymbols
        if indexedFiles == nil,
           let root = context.projectRoot,
           shouldSearchFiles(query: queryLowercased) ||
           shouldSearchContent(query: queryLowercased) ||
           shouldSearchSymbols(query: queryLowercased) {
            indexedFiles = TerminalCommandPaletteSearchIndex.indexFiles(root: root)
        }

        var results = TerminalCommandPaletteActionResults.actionResults(query: queryLowercased, context: context, actions: actions)

        guard let root = context.projectRoot else {
            return TerminalCommandPaletteSearchOutput(
                results: sortResults(results),
                cachedFiles: indexedFiles,
                cachedSymbols: indexedSymbols
            )
        }

        let files = indexedFiles ?? []
        let wantsSymbolSearch = shouldSearchSymbols(query: queryLowercased)
        let wantsContentSearch = shouldSearchContent(query: queryLowercased)
        let filePass = TerminalCommandPaletteFileSearch.run(query: queryLowercased, root: root, files: files,
            cachedSymbols: indexedSymbols, searchSymbols: wantsSymbolSearch, searchContent: wantsContentSearch,
            cache: cache, validateCachedSymbols: validateCachedSymbols, textContents: textContents)
        indexedSymbols = filePass.symbols
        if wantsSymbolSearch {
            results.append(contentsOf: TerminalCommandPaletteSymbolResults.symbolResults(
                query: queryLowercased, symbols: indexedSymbols ?? []))
        }
        if shouldSearchFiles(query: queryLowercased) {
            results.append(contentsOf: TerminalCommandPaletteFileResults.fileResults(query: queryLowercased, files: files))
            results.append(contentsOf: TerminalCommandPaletteDiagnosticsResults.diagnosticsResults(
                query: queryLowercased,
                projectRoot: root,
                projectHash: context.projectHash,
                ideStateDirectoryOverride: ideStateDirectoryOverride
            ))
            results.append(contentsOf: TerminalCommandPaletteHistoryResults.historyResults(
                query: queryLowercased,
                projectRoot: root,
                projectHash: context.projectHash,
                ideStateDirectoryOverride: ideStateDirectoryOverride
            ))
        }
        results.append(contentsOf: filePass.content)

        return TerminalCommandPaletteSearchOutput(
            results: sortResults(results),
            cachedFiles: indexedFiles,
            cachedSymbols: indexedSymbols
        )
    }

    static func immediateResults(
        query: String,
        context: TerminalCommandPaletteContext,
        actions: [TerminalCommandPaletteActionSearchDescriptor]
    ) -> [TerminalCommandPaletteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        return sortResults(
            TerminalCommandPaletteActionResults.actionResults(query: trimmedQuery.lowercased(), context: context, actions: actions)
        )
    }

    static func matchScore(query: String, text: String) -> Int {
        matchScore(query: query, normalizedText: text.lowercased())
    }

    static func matchScore(query: String, normalizedText normalized: String) -> Int {
        guard !normalized.isEmpty else { return 0 }
        if normalized == query {
            return 220
        }
        if normalized.hasPrefix(query) {
            return 170
        }
        if normalized.contains(query) {
            return 110
        }
        return 0
    }

    static func clipText(_ raw: String, maxLength: Int = 120) -> String {
        let sanitized = raw
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        guard sanitized.count > maxLength, maxLength > 3 else {
            return sanitized
        }
        return "\(sanitized.prefix(maxLength - 3))..."
    }

    private static func sortResults(_ results: [TerminalCommandPaletteSearchResult]) -> [TerminalCommandPaletteSearchResult] {
        results.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.source.rank != rhs.source.rank {
                return lhs.source.rank < rhs.source.rank
            }
            if lhs.targetKey != rhs.targetKey {
                return lhs.targetKey < rhs.targetKey
            }
            return lhs.previewKey < rhs.previewKey
        }
    }

    private static func shouldSearchFiles(query: String) -> Bool {
        query.count >= minQueryLengthForFileSearch
    }

    private static func shouldSearchSymbols(query: String) -> Bool {
        query.count >= minQueryLengthForFileSearch
    }

    private static func shouldSearchContent(query: String) -> Bool {
        query.count >= minQueryLengthForContentSearch
    }

}
