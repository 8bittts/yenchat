import Foundation

enum TerminalCommandPaletteSearchIndex {
    private static let excludedDirectoryNames: Set<String> = [
        ".build",
        ".cache",
        ".git",
        ".next",
        ".nuxt",
        ".swiftpm",
        ".turbo",
        ".venv",
        ".vercel",
        ".zig-cache",
        ".zig-global-cache",
        "DerivedData",
        "Pods",
        "__pycache__",
        "coverage",
        "dist",
        "ghostty",
        "node_modules",
        "target",
        "vendor",
        "venv",
        "zig-cache",
        "zig-out",
    ]
    private struct SymbolPattern {
        let kind: String
        let regex: NSRegularExpression
    }

    private static let symbolPatternsByExtension: [String: [SymbolPattern]] = [
        ".py": [
            symbolPattern(kind: "class", pattern: #"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "function", pattern: #"^\s*(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)"#),
        ],
        ".ts": [
            symbolPattern(kind: "function", pattern: #"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "class", pattern: #"^\s*(?:export\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "interface", pattern: #"^\s*(?:export\s+)?interface\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "type", pattern: #"^\s*(?:export\s+)?type\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "enum", pattern: #"^\s*(?:export\s+)?enum\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "variable", pattern: #"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*="#),
        ],
        ".tsx": [
            symbolPattern(kind: "function", pattern: #"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "class", pattern: #"^\s*(?:export\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "interface", pattern: #"^\s*(?:export\s+)?interface\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "type", pattern: #"^\s*(?:export\s+)?type\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "enum", pattern: #"^\s*(?:export\s+)?enum\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "variable", pattern: #"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*="#),
        ],
        ".js": [
            symbolPattern(kind: "function", pattern: #"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "class", pattern: #"^\s*(?:export\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "variable", pattern: #"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*="#),
        ],
        ".jsx": [
            symbolPattern(kind: "function", pattern: #"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "class", pattern: #"^\s*(?:export\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "variable", pattern: #"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*="#),
        ],
        ".go": [
            symbolPattern(kind: "function", pattern: #"^\s*func(?:\s+\([^)]*\))?\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "type", pattern: #"^\s*type\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "variable", pattern: #"^\s*var\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "constant", pattern: #"^\s*const\s+([A-Za-z_][A-Za-z0-9_]*)"#),
        ],
        ".swift": [
            symbolPattern(kind: "class", pattern: #"^\s*(?:final\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "struct", pattern: #"^\s*struct\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "enum", pattern: #"^\s*enum\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "protocol", pattern: #"^\s*protocol\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "actor", pattern: #"^\s*actor\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "typealias", pattern: #"^\s*typealias\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "function", pattern: #"^\s*func\s+([A-Za-z_][A-Za-z0-9_]*)"#),
            symbolPattern(kind: "variable", pattern: #"^\s*(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)"#),
        ],
    ]

    static func indexFiles(root: String, resolvePath: (URL) -> URL = { $0.resolvingSymlinksInPath() }) -> [TerminalCommandPaletteIndexedFile] {
        let fileManager = FileManager.default
        let rootURL = resolvePath(URL(fileURLWithPath: root))
        let rootPath = rootURL.path
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var indexedFiles: [TerminalCommandPaletteIndexedFile] = []
        indexedFiles.reserveCapacity(TerminalCommandPaletteSearchEngine.maxFileCount)

        for case let fileURL as URL in enumerator {
            if Task.isCancelled {
                break
            }
            if indexedFiles.count >= TerminalCommandPaletteSearchEngine.maxFileCount {
                break
            }

            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
                continue
            }

            if resourceValues.isDirectory == true {
                if shouldSkipDirectory(named: fileURL.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard resourceValues.isRegularFile == true else { continue }
            let resolvedFileURL = resolvePath(fileURL)
            guard resolvedFileURL.path.hasPrefix("\(rootPath)/") else { continue }
            let relativePath = String(resolvedFileURL.path.dropFirst(rootPath.count + 1))

            indexedFiles.append(
                TerminalCommandPaletteIndexedFile(
                    absolutePath: resolvedFileURL.path,
                    relativePath: relativePath,
                    baseName: resolvedFileURL.lastPathComponent
                )
            )
        }

        return indexedFiles
    }

    static func indexSymbols(
        files: [TerminalCommandPaletteIndexedFile],
        textContents: (TerminalCommandPaletteIndexedFile) -> String?
    ) -> [TerminalCommandPaletteIndexedSymbol] {
        var indexedSymbols: [TerminalCommandPaletteIndexedSymbol] = []
        var seen: Set<String> = []
        indexedSymbols.reserveCapacity(files.count)

        for file in files {
            if Task.isCancelled {
                break
            }
            guard let patterns = symbolPatternsByExtension[fileExtension(for: file.relativePath)] else {
                continue
            }
            guard let contents = textContents(file) else {
                continue
            }

            for (offset, rawLine) in contents.split(whereSeparator: \.isNewline).enumerated() {
                let line = String(rawLine)
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                for pattern in patterns {
                    guard let match = pattern.regex.firstMatch(in: line, options: [], range: nsRange),
                          match.numberOfRanges > 1,
                          let range = Range(match.range(at: 1), in: line) else {
                        continue
                    }

                    let symbolName = String(line[range])
                    let column = line.distance(from: line.startIndex, to: range.lowerBound) + 1
                    let lineNumber = offset + 1
                    let location = "\(symbolName)|\(pattern.kind)|\(file.relativePath):\(lineNumber):\(column)"
                    guard !seen.contains(location) else {
                        break
                    }
                    seen.insert(location)
                    indexedSymbols.append(
                        TerminalCommandPaletteIndexedSymbol(
                            absolutePath: file.absolutePath,
                            relativePath: file.relativePath,
                            symbolName: symbolName,
                            kind: pattern.kind,
                            line: lineNumber,
                            column: column
                        )
                    )
                    break
                }
            }
        }

        return sortedSymbols(indexedSymbols)
    }

    static func supportsSymbols(_ file: TerminalCommandPaletteIndexedFile) -> Bool {
        symbolPatternsByExtension[fileExtension(for: file.relativePath)] != nil
    }

    static func sortedSymbols(_ symbols: [TerminalCommandPaletteIndexedSymbol]) -> [TerminalCommandPaletteIndexedSymbol] {
        symbols.sorted {
            let lhsName = $0.localizedSortName
            let rhsName = $1.localizedSortName
            if lhsName != rhsName {
                return lhsName < rhsName
            }
            if $0.relativePath != $1.relativePath {
                return $0.relativePath < $1.relativePath
            }
            if $0.line != $1.line {
                return $0.line < $1.line
            }
            return $0.column < $1.column
        }
    }

    private static func shouldSkipDirectory(named name: String) -> Bool {
        excludedDirectoryNames.contains(name)
    }

    private static func fileExtension(for path: String) -> String {
        URL(fileURLWithPath: path).pathExtension.isEmpty ? "" : ".\(URL(fileURLWithPath: path).pathExtension.lowercased())"
    }

    private static func symbolPattern(kind: String, pattern: String) -> SymbolPattern {
        SymbolPattern(kind: kind, regex: try! NSRegularExpression(pattern: pattern))
    }

    private static func boundedData(at url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let limit = TerminalCommandPaletteSearchEngine.maxTextFileBytes
        var data = Data()
        while !Task.isCancelled {
            do {
                guard let chunk = try handle.read(upToCount: min(65536, limit + 1 - data.count)),
                      !chunk.isEmpty else { return data }
                data.append(chunk)
            } catch { return nil }
            if data.count > limit { return nil }
        }
        return nil
    }

    static func loadTextContents(at path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue <= TerminalCommandPaletteSearchEngine.maxTextFileBytes,
              let data = boundedData(at: url),
              !data.isEmpty else {
            return nil
        }

        if data.contains(0) {
            return nil
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf16LE = String(data: data, encoding: .utf16LittleEndian) {
            return utf16LE
        }
        if let utf16BE = String(data: data, encoding: .utf16BigEndian) {
            return utf16BE
        }
        if let ascii = String(data: data, encoding: .ascii) {
            return ascii
        }
        return nil
    }

}
