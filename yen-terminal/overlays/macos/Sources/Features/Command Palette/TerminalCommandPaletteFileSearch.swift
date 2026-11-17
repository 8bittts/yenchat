import Foundation

enum TerminalCommandPaletteFileSearch {
    struct Output {
        let symbols: [TerminalCommandPaletteIndexedSymbol]?
        let content: [TerminalCommandPaletteSearchResult]
    }

    static func run(query: String, root: String, files: [TerminalCommandPaletteIndexedFile],
                    cachedSymbols: [TerminalCommandPaletteIndexedSymbol]?, searchSymbols: Bool,
                    searchContent: Bool, cache: TerminalCommandPaletteSearchCache,
                    validateCachedSymbols: Bool, textContents: (String) -> String?) -> Output {
        let ticket = cache.begin()
        var fingerprints: [String: TerminalCommandPaletteSearchCache.Fingerprint] = [:]
        for file in files {
            if Task.isCancelled { break }
            if fingerprints[file.absolutePath] == nil {
                fingerprints[file.absolutePath] = cache.fingerprint(for: file.absolutePath)
            }
        }
        let allFingerprints = fingerprints.count == Set(files.map(\.absolutePath)).count
        let reuseSymbols = cachedSymbols != nil && (!validateCachedSymbols ||
            (allFingerprints && ticket.symbols?.root == root && ticket.symbols?.files == files &&
             ticket.symbols?.fingerprints == fingerprints))
        let buildSymbols = searchSymbols && !reuseSymbols
        var symbols: [TerminalCommandPaletteIndexedSymbol] = []
        var seenSymbols: Set<String> = []
        var symbolScanComplete = allFingerprints
        var content: [TerminalCommandPaletteSearchResult] = []
        var scanned: [String: TerminalCommandPaletteSearchCache.Fingerprint] = [:]
        var matchingPaths: Set<String> = []
        let previous = ticket.content
        let extendsPrevious = previous?.root == root && previous.map { query.hasPrefix($0.query) } == true
        for file in files {
            if Task.isCancelled { break }
            let path = file.absolutePath
            let fingerprint = fingerprints[path]
            let unchangedNonmatch = extendsPrevious && fingerprint != nil &&
                previous?.fingerprints[path] == fingerprint && previous?.matchingPaths.contains(path) == false
            let needsContent = searchContent && content.count < TerminalCommandPaletteSearchEngine.maxContentMatches
            if needsContent && unchangedNonmatch { scanned[path] = fingerprint }
            let needsSymbols = buildSymbols && TerminalCommandPaletteSearchIndex.supportsSymbols(file)
            guard needsSymbols || (needsContent && !unchangedNonmatch) else { continue }
            guard let read = cache.read(path, fingerprint: fingerprint, ticket: ticket, loader: textContents) else {
                if needsSymbols { symbolScanComplete = false }
                continue
            }
            if needsSymbols {
                if read.fingerprint == nil { symbolScanComplete = false }
                let found = TerminalCommandPaletteSearchIndex.indexSymbols(files: [file], textContents: { _ in read.document.contents })
                for symbol in found {
                    let key = "\(symbol.symbolName)|\(symbol.kind)|\(symbol.relativePath):\(symbol.line):\(symbol.column)"
                    if seenSymbols.insert(key).inserted { symbols.append(symbol) }
                }
            }
            if needsContent && !unchangedNonmatch {
                let found = TerminalCommandPaletteContentResults.contentResults(query: query, files: [file],
                    maximumMatches: TerminalCommandPaletteSearchEngine.maxContentMatches - content.count,
                    textContents: { _ in read.document })
                content.append(contentsOf: found)
                if !found.isEmpty { matchingPaths.insert(path) }
                scanned[path] = read.fingerprint
            }
        }
        let complete = !Task.isCancelled && files.count <= TerminalCommandPaletteSearchEngine.maxFileCount
        let contentScan: TerminalCommandPaletteSearchCache.ContentScan? =
            complete && searchContent && content.count < TerminalCommandPaletteSearchEngine.maxContentMatches
            ? .init(root: root, query: query, fingerprints: scanned, matchingPaths: matchingPaths) : nil
        // Keep symbols and their fingerprint snapshot together even when a canceled
        // model request never adopted the completed worker's output.
        let outputSymbols = buildSymbols ? TerminalCommandPaletteSearchIndex.sortedSymbols(symbols)
            : (validateCachedSymbols && reuseSymbols ? ticket.symbols?.symbols : cachedSymbols)
        let symbolScan: TerminalCommandPaletteSearchCache.SymbolScan?
        if buildSymbols {
            symbolScan = complete && symbolScanComplete ? .init(root: root, files: files, symbols: outputSymbols ?? [], fingerprints: fingerprints) : nil
        } else {
            symbolScan = reuseSymbols ? ticket.symbols : nil
        }
        cache.record(content: contentScan, symbols: symbolScan, ticket: ticket)
        return Output(symbols: outputSymbols,
            content: content)
    }
}
