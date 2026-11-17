import Foundation
import Testing
@testable import YEN

struct TerminalCommandPaletteSearchTests {
    @Test func successiveQueriesReuseUnchangedDecodedContent() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-content-cache-")
        defer { try? FileManager.default.removeItem(at: root) }
        try write("needle alphabet", to: root.appendingPathComponent("content.txt"))
        let context = TerminalCommandPaletteContext(projectRoot: root.resolvingSymlinksInPath().path, runtime: [], tooling: [])
        let cache = TerminalCommandPaletteSearchCache()
        var reads = 0
        let first = TerminalCommandPaletteSearchEngine.searchForTesting(query: "needle", context: context,
            actions: [], cachedFiles: nil, cachedSymbols: nil, cache: cache, textContents: { path in
                reads += 1
                return TerminalCommandPaletteSearchIndex.loadTextContents(at: path)
            })
        let second = TerminalCommandPaletteSearchEngine.searchForTesting(query: "needle alpha", context: context,
            actions: [], cachedFiles: first.cachedFiles, cachedSymbols: first.cachedSymbols, cache: cache, textContents: { path in
                reads += 1
                return TerminalCommandPaletteSearchIndex.loadTextContents(at: path)
            })
        #expect(second.results.contains { $0.source == .content && $0.targetKey.hasPrefix("content.txt:") })
        #expect(reads == 1)
    }

    @Test func contentCacheBoundsMemoryAndRejectsStaleSessionWrites() {
        let cache = TerminalCommandPaletteSearchCache(maximumBytes: 100, maximumEntries: 1,
            fingerprint: { _ in .synthetic })
        let ticket = cache.begin()
        _ = cache.read("a", fingerprint: .synthetic, ticket: ticket, loader: { _ in "small" })
        _ = cache.read("b", fingerprint: .synthetic, ticket: ticket, loader: { _ in "other" })
        #expect(cache.retainedEntries == 1)
        #expect(cache.retainedBytes <= 100)
        _ = cache.read("large", fingerprint: .synthetic, ticket: ticket, loader: { _ in String(repeating: "x", count: 101) })
        #expect(cache.retainedEntries == 1)
        _ = cache.read("late", fingerprint: .synthetic, ticket: ticket, loader: { _ in
            cache.clear()
            return "late content"
        })
        #expect(cache.retainedEntries == 0)
        #expect(cache.retainedBytes == 0)
        cache.record(content: .init(root: "/", query: "old", fingerprints: [:], matchingPaths: []), symbols: nil, ticket: ticket)
        #expect(cache.begin().content == nil)
        let old = cache.begin()
        let latest = cache.begin()
        cache.record(content: .init(root: "/", query: "latest", fingerprints: [:], matchingPaths: []), symbols: nil, ticket: latest)
        cache.record(content: .init(root: "/", query: "old", fingerprints: [:], matchingPaths: []), symbols: nil, ticket: old)
        #expect(cache.begin().content?.query == "latest")
        let byteBound = TerminalCommandPaletteSearchCache(maximumBytes: 50, maximumEntries: 10,
            fingerprint: { _ in .synthetic })
        let byteTicket = byteBound.begin()
        for path in ["a", "b", "c"] {
            _ = byteBound.read(path, fingerprint: .synthetic, ticket: byteTicket, loader: { _ in "small" })
        }
        #expect(byteBound.retainedEntries == 1)
        #expect(byteBound.retainedBytes <= 50)
    }

    @Test func extendingQuerySkipsUnchangedNonmatchesButRechecksChangedFiles() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-cache-narrow-")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a.txt")
        let second = root.appendingPathComponent("b.txt")
        try write("unrelated", to: first)
        try write("needle alphabet", to: second)
        let files = TerminalCommandPaletteSearchIndex.indexFiles(root: root.path).sorted { $0.relativePath < $1.relativePath }
        let cache = TerminalCommandPaletteSearchCache(maximumBytes: 0)
        var reads: [String] = []
        func search(_ query: String) -> TerminalCommandPaletteFileSearch.Output {
            TerminalCommandPaletteFileSearch.run(query: query, root: root.path, files: files,
                cachedSymbols: nil, searchSymbols: false, searchContent: true, cache: cache,
                validateCachedSymbols: true, textContents: { path in
                    reads.append(URL(fileURLWithPath: path).lastPathComponent)
                    return TerminalCommandPaletteSearchIndex.loadTextContents(at: path)
                })
        }
        #expect(search("needle").content.count == 1)
        reads = []
        #expect(search("needle a").content.count == 1)
        #expect(reads == ["b.txt"])
        try write("needle alphabet", to: first)
        reads = []
        #expect(search("needle al").content.count == 2)
        #expect(reads == ["a.txt", "b.txt"])
        reads = []
        _ = search("unrelated")
        #expect(reads == ["a.txt", "b.txt"])
    }

    @Test func truncatedContentScanDoesNotExcludeLaterMatches() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-cache-truncated-")
        defer { try? FileManager.default.removeItem(at: root) }
        try write(String(repeating: "needle\n", count: TerminalCommandPaletteSearchEngine.maxContentMatches),
            to: root.appendingPathComponent("a.txt"))
        try write("needle unique", to: root.appendingPathComponent("z.txt"))
        let files = TerminalCommandPaletteSearchIndex.indexFiles(root: root.path).sorted { $0.relativePath < $1.relativePath }
        let cache = TerminalCommandPaletteSearchCache()
        func search(_ query: String) -> TerminalCommandPaletteFileSearch.Output {
            TerminalCommandPaletteFileSearch.run(query: query, root: root.path, files: files,
                cachedSymbols: nil, searchSymbols: false, searchContent: true, cache: cache,
                validateCachedSymbols: true, textContents: TerminalCommandPaletteSearchIndex.loadTextContents(at:))
        }
        #expect(search("needle").content.count == TerminalCommandPaletteSearchEngine.maxContentMatches)
        #expect(cache.begin().content == nil)
        let next = search("needle unique")
        #expect(next.content.count == 1)
        #expect(next.content.first?.targetKey.hasPrefix("z.txt:") == true)
    }

    @Test func cachedSymbolsRefreshAfterAtomicSameSizeReplacement() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-cache-symbols-")
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("sample.swift")
        try write("func before() {}", to: path)
        let files = TerminalCommandPaletteSearchIndex.indexFiles(root: root.path).sorted { $0.relativePath < $1.relativePath }
        let cache = TerminalCommandPaletteSearchCache()
        func search(_ symbols: [TerminalCommandPaletteIndexedSymbol]?) -> TerminalCommandPaletteFileSearch.Output {
            TerminalCommandPaletteFileSearch.run(query: "func", root: root.path, files: files,
                cachedSymbols: symbols, searchSymbols: true, searchContent: true, cache: cache,
                validateCachedSymbols: true, textContents: TerminalCommandPaletteSearchIndex.loadTextContents(at:))
        }
        let first = search(nil)
        #expect(first.symbols?.map(\.symbolName) == ["before"])
        let modified = try #require(FileManager.default.attributesOfItem(atPath: path.path)[.modificationDate] as? Date)
        try "func afters() {}".write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path.path)
        let second = search(first.symbols)
        #expect(second.symbols?.map(\.symbolName) == ["afters"])
        #expect(second.content.first?.subtitle == "func afters() {}")
        // A completed worker can be canceled before the model adopts its output.
        // Its cache must not pair new fingerprints with the model's older symbols.
        let afterCanceledAdoption = search(first.symbols)
        #expect(afterCanceledAdoption.symbols?.map(\.symbolName) == ["afters"])
        try Data("func latest() {}".utf8).write(to: path)
        try FileManager.default.setAttributes([.modificationDate: modified.addingTimeInterval(5)], ofItemAtPath: path.path)
        #expect(search(second.symbols).symbols?.map(\.symbolName) == ["latest"])
    }

    @Test func failedReadsAndCanceledScansDoNotNarrowLaterQueries() async {
        let file = TerminalCommandPaletteIndexedFile(absolutePath: "/fixture.txt", relativePath: "fixture.txt", baseName: "fixture.txt")
        let cache = TerminalCommandPaletteSearchCache(fingerprint: { _ in .synthetic })
        let first = TerminalCommandPaletteFileSearch.run(query: "needle", root: "/", files: [file],
            cachedSymbols: nil, searchSymbols: false, searchContent: true, cache: cache,
            validateCachedSymbols: true, textContents: { _ in nil })
        #expect(first.content.isEmpty)
        let second = TerminalCommandPaletteFileSearch.run(query: "needle alphabet", root: "/", files: [file],
            cachedSymbols: nil, searchSymbols: false, searchContent: true, cache: cache,
            validateCachedSymbols: true, textContents: { _ in "needle alphabet" })
        #expect(second.content.count == 1)
        cache.clear()
        await Task.detached {
            _ = TerminalCommandPaletteFileSearch.run(query: "needle", root: "/", files: [file],
                cachedSymbols: nil, searchSymbols: false, searchContent: true, cache: cache,
                validateCachedSymbols: true, textContents: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return "needle"
                })
        }.value
        #expect(cache.begin().content == nil)
        #expect(cache.retainedEntries == 0)
    }

    @Test func textLoaderRejectsBinaryAndOversizedFiles() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-text-boundaries-")
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("data.txt")
        try Data([65, 0, 66]).write(to: path)
        #expect(TerminalCommandPaletteSearchIndex.loadTextContents(at: path.path) == nil)
        try Data(repeating: 65, count: TerminalCommandPaletteSearchEngine.maxTextFileBytes + 1).write(to: path)
        #expect(TerminalCommandPaletteSearchIndex.loadTextContents(at: path.path) == nil)
        try write("Needle café\r\nnext", to: path)
        #expect(TerminalCommandPaletteSearchIndex.loadTextContents(at: path.path) == "Needle café\r\nnext")
    }

    @Test func indexResolvesOnlyIncludedRegularFilesAndTheRoot() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-index-resolution-")
        defer { try? FileManager.default.removeItem(at: root) }
        try write("visible", to: root.appendingPathComponent("src/visible.txt"))
        try write("excluded", to: root.appendingPathComponent("node_modules/dependency/hidden.txt"))
        var resolutions: [String] = []
        let files = TerminalCommandPaletteSearchIndex.indexFiles(root: root.path, resolvePath: { url in
            resolutions.append(url.lastPathComponent)
            return url.resolvingSymlinksInPath()
        })
        #expect(files.map(\.relativePath) == ["src/visible.txt"])
        #expect(resolutions == [root.lastPathComponent, "visible.txt"])
    }

    @MainActor
    @Test func projectContextDiscoveryRunsOffMainWhileSearchFindsFiles() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-context-thread-")
        defer { try? FileManager.default.removeItem(at: root) }
        try write("{}", to: root.appendingPathComponent("package.json"))
        try write("needle", to: root.appendingPathComponent("needle.txt"))
        let probe = PaletteContextThreadProbe()
        let model = TerminalCommandPaletteSearchModel(debounceNanoseconds: 0, resolveContext: { path in
            probe.record()
            return TerminalCommandPaletteProjectContextResolver.resolve(pwd: path)
        })
        model.refreshContext(projectDirectory: root.path, actions: [])
        model.queryDidChange(to: "needle")
        await waitUntil(description: "file result after context discovery") {
            model.results.contains { $0.targetKey == "needle.txt" }
        }
        #expect(probe.calls == 1)
        #expect(!probe.ranOnMain)
    }

    @Test func contextDiscoveryReadsEachAncestorOnceAndPreservesMarkerSemantics() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-context-listings-")
        defer { try? FileManager.default.removeItem(at: root) }
        try write("{}", to: root.appendingPathComponent("package.json"))
        try write("", to: root.appendingPathComponent("bun.lock"))
        try write("{}", to: root.appendingPathComponent("tsconfig.json"))
        let nested = root.appendingPathComponent("src/deep")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        // A dangling marker must not turn the nested directory into a project root.
        try FileManager.default.createSymbolicLink(at: nested.appendingPathComponent(".git"),
            withDestinationURL: root.appendingPathComponent("missing"))
        var reads: [String] = []
        let context = TerminalCommandPaletteProjectContextResolver.resolve(pwd: nested.path, directoryEntries: { path in
            reads.append(path)
            return TerminalCommandPaletteProjectContextResolver.existingEntryNames(at: path)
        })
        #expect(reads == [nested, nested.deletingLastPathComponent(), root].map { $0.resolvingSymlinksInPath().path })
        #expect(context.runtime == ["node", "bun"])
        #expect(context.tooling == ["typescript", "bun"])
        try write("", to: root.appendingPathComponent("NEXT.CONFIG.JS"))
        let names = TerminalCommandPaletteProjectContextResolver.existingEntryNames(at: root.path)
        #expect(names.contains("next.config.js") == FileManager.default.fileExists(atPath: root.appendingPathComponent("next.config.js").path))
    }

    @Test func contextDiscoveryPreservesUnreadableParentAndFileInputFallbacks() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-context-unreadable-")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let file = root.appendingPathComponent("package.json")
        try write("{}", to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: root.path)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: root.path)) == nil)
        let context = TerminalCommandPaletteProjectContextResolver.resolve(pwd: file.path)
        #expect(context.projectRoot == root.resolvingSymlinksInPath().path)
        #expect(context.runtime == ["node"])
        #expect(context.tooling == ["minimal"])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        var reads: [String] = []
        let fallback = TerminalCommandPaletteProjectContextResolver.resolve(pwd: file.path, directoryEntries: { path in
            reads.append(path)
            return []
        })
        #expect(fallback.projectRoot == root.resolvingSymlinksInPath().path)
        #expect(fallback.runtime == ["unknown"])
        #expect(Set(reads).count == reads.count)
    }

    @MainActor
    @Test func sharedPathNormalizationPreservesCallerInputRules() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-path-policy-")
        defer { try? FileManager.default.removeItem(at: root) }
        let spaced = root.appendingPathComponent("with space ")
        try FileManager.default.createDirectory(at: spaced, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: spaced)
        #expect(LocalPathResolver.canonicalPath(link.path) == spaced.resolvingSymlinksInPath().path)
        #expect(TerminalCommandPaletteView.normalizedWorkingDirectory(spaced.path) != nil)
        #expect(TabSidebarController.trustedWorkingDirectory(from: spaced.path) == nil)
        #expect(TerminalCommandPaletteView.normalizedWorkingDirectory(".") != nil)
        #expect(TabSidebarController.trustedWorkingDirectory(from: ".") == nil)
        #expect(TabSidebarController.trustedWorkingDirectory(from: "  " + root.path + "  ") == root.resolvingSymlinksInPath().path)
        #expect(LocalPathResolver.canonicalPath(nil) == nil)
        #expect(LocalPathResolver.canonicalPath("") == nil)
        #expect(LocalPathResolver.canonicalPath(root.appendingPathComponent("missing").path) == nil)
    }

    @MainActor
    @Test func supersededContextCannotReplaceNewProjectResults() async throws {
        let rootA = try makeTemporaryDirectory(prefix: "yen-context-old-")
        let rootB = try makeTemporaryDirectory(prefix: "yen-context-new-")
        defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB) }
        try write("{}", to: rootA.appendingPathComponent("package.json"))
        try write("{}", to: rootB.appendingPathComponent("package.json"))
        try write("needle", to: rootB.appendingPathComponent("needle.txt"))
        let probe = PaletteContextThreadProbe()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let model = TerminalCommandPaletteSearchModel(debounceNanoseconds: 0, resolveContext: { path in
            probe.record()
            if path == rootA.path { _ = release.wait(timeout: .now() + 3) }
            defer { probe.finish() }
            return TerminalCommandPaletteProjectContextResolver.resolve(pwd: path)
        })
        model.refreshContext(projectDirectory: rootA.path, actions: [])
        await waitUntil(description: "old context worker started") { probe.calls == 1 }
        model.refreshContext(projectDirectory: rootB.path, actions: [])
        model.queryDidChange(to: "needle")
        await waitUntil(description: "new context result") { model.results.contains { $0.targetKey == "needle.txt" } }
        release.signal()
        await waitUntil(description: "both context workers finished") { probe.completed == 2 }
        await advanceMainQueueTurn()
        #expect(model.results.contains { $0.targetKey == "needle.txt" })
        #expect(!model.isSearching)
    }

    @MainActor
    @Test func resettingDuringContextDiscoveryCannotRestoreTheOldRoot() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-context-reset-")
        defer { try? FileManager.default.removeItem(at: root) }
        try write("{}", to: root.appendingPathComponent("package.json"))
        try write("needle", to: root.appendingPathComponent("needle.txt"))
        let probe = PaletteContextThreadProbe()
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let model = TerminalCommandPaletteSearchModel(debounceNanoseconds: 0, resolveContext: { path in
            probe.record()
            _ = release.wait(timeout: .now() + 3)
            defer { probe.finish() }
            return TerminalCommandPaletteProjectContextResolver.resolve(pwd: path)
        })
        model.refreshContext(projectDirectory: root.path, actions: [])
        await waitUntil(description: "context worker started") { probe.calls == 1 }
        model.resetSession()
        release.signal()
        await waitUntil(description: "context worker finished after reset") { probe.completed == 1 }
        await advanceMainQueueTurn()
        model.queryDidChange(to: "needle")
        #expect(model.results.isEmpty)
        #expect(!model.isSearching)
    }

    @Test func projectContextResolverFindsRootAndTags() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-context-")
        defer { try? FileManager.default.removeItem(at: root) }
        let resolvedRoot = root.resolvingSymlinksInPath()

        try write("{}", to: root.appendingPathComponent("package.json"))
        try write("{}", to: root.appendingPathComponent("tsconfig.json"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        let nested = root.appendingPathComponent("src/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let context = TerminalCommandPaletteProjectContextResolver.resolve(pwd: nested.path)

        #expect(context.projectRoot == resolvedRoot.path)
        #expect(context.runtime.contains("node"))
        #expect(context.tooling.contains("typescript"))
        #expect(context.tooling.contains("git"))
    }

    @Test func projectContextResolverTreatsGitFilesAsRootMarkers() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-context-gitfile-")
        defer { try? FileManager.default.removeItem(at: root) }
        let resolvedRoot = root.resolvingSymlinksInPath()

        try write("{}", to: root.appendingPathComponent("package.json"))
        try write("gitdir: /tmp/fake-worktree\n", to: root.appendingPathComponent(".git"))
        let nested = root.appendingPathComponent("src/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let context = TerminalCommandPaletteProjectContextResolver.resolve(pwd: nested.path)

        #expect(context.projectRoot == resolvedRoot.path)
        #expect(context.tooling.contains("git"))
    }

    @Test func searchSpansFilesSymbolsContentDiagnosticsHistoryAndActions() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-search-")
        let stateDir = try makeTemporaryDirectory(prefix: "yen-palette-state-")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: stateDir)
        }
        let resolvedRoot = root.resolvingSymlinksInPath()

        try write("{}", to: root.appendingPathComponent("package.json"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src"),
            withIntermediateDirectories: true
        )
        try write("verify runbook\n", to: root.appendingPathComponent("verify-guide.md"))
        try write("first line\nverify keyword here\n", to: root.appendingPathComponent("src/notes.txt"))
        try write(
            "export function verifyProjectSymbol() {}\n",
            to: root.appendingPathComponent("src/verify-symbol.ts")
        )

        let historyDirectory = stateDir.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        let historyHash = TerminalCommandPaletteProjectContextResolver.projectHash(root: resolvedRoot.path)
        let historyFile = historyDirectory.appendingPathComponent("\(historyHash).log")
        try write("2026-03-07T12:00:00Z\t\(resolvedRoot.path)\tyen ide verify --quick\n", to: historyFile)
        let diagnosticsDirectory = stateDir
            .appendingPathComponent("lsp", isDirectory: true)
            .appendingPathComponent(historyHash, isDirectory: true)
        try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        let diagnosticsFile = diagnosticsDirectory.appendingPathComponent("diagnostics.json")
        try write(
            """
            {
              "updated_at": "2026-03-10T18:00:00Z",
              "items": [
                {
                  "file": "\(resolvedRoot.appendingPathComponent("src/notes.txt").path)",
                  "line": 2,
                  "col": 3,
                  "severity": "error",
                  "code": "VERIFY100",
                  "source": "fake-lsp",
                  "message": "verify diagnostic"
                }
              ]
            }
            """,
            to: diagnosticsFile
        )

        let actions = [
            TerminalCommandPaletteActionSearchDescriptor(
                id: "action:verify",
                title: "Verify Project",
                subtitle: "Run the quick verification bundle",
                description: "Verify the current project",
                searchTags: ["verify", "node"]
            ),
        ]
        let context = TerminalCommandPaletteProjectContextResolver.resolve(pwd: root.path)

        let first = TerminalCommandPaletteSearchEngine.search(
            query: "verify",
            context: context,
            actions: actions,
            cachedFiles: nil,
            cachedSymbols: nil,
            ideStateDirectoryOverride: stateDir.path
        )
        let second = TerminalCommandPaletteSearchEngine.search(
            query: "verify",
            context: context,
            actions: actions,
            cachedFiles: nil,
            cachedSymbols: nil,
            ideStateDirectoryOverride: stateDir.path
        )

        let firstTargets = first.results.map { $0.targetKey }
        let secondTargets = second.results.map { $0.targetKey }
        let symbolResult = first.results.first { result in
            result.source == TerminalCommandPaletteResultSource.symbol &&
                result.targetKey == "src/verify-symbol.ts:1:17" &&
                result.title == "verifyProjectSymbol [function]"
        }
        let fileResult = first.results.first { result in
            result.source == TerminalCommandPaletteResultSource.file &&
                result.targetKey == "verify-guide.md"
        }
        let contentResult = first.results.first { result in
            result.source == TerminalCommandPaletteResultSource.content &&
                result.targetKey == "src/notes.txt:2:1"
        }
        let diagnosticResult = first.results.first { result in
            result.source == TerminalCommandPaletteResultSource.diagnostic &&
                result.targetKey == "src/notes.txt:2:3"
        }
        let historyResult = first.results.first { result in
            result.source == TerminalCommandPaletteResultSource.history &&
                result.title == "yen ide verify --quick"
        }
        let actionResult = first.results.first { result in
            result.source == TerminalCommandPaletteResultSource.action &&
                result.title == "Verify Project"
        }

        #expect(firstTargets == secondTargets)
        #expect(symbolResult != nil)
        #expect(fileResult != nil)
        #expect(contentResult != nil)
        #expect(diagnosticResult != nil)
        #expect(historyResult != nil)
        #expect(actionResult != nil)

        let contentLocation = contentResult?.execution
        if case let .openLocation(location)? = contentLocation {
            #expect(location.line == 2)
            #expect(location.column == 1)
        } else {
            Issue.record("Expected content result to carry a semantic location")
        }

        let diagnosticLocation = diagnosticResult?.execution
        if case let .openLocation(location)? = diagnosticLocation {
            #expect(location.line == 2)
            #expect(location.column == 3)
            #expect(location.severity == "error")
            #expect(location.code == "VERIFY100")
            #expect(location.diagnosticSource == "fake-lsp")
        } else {
            Issue.record("Expected diagnostic result to carry a semantic location")
        }

        let symbolLocation = symbolResult?.execution
        if case let .openLocation(location)? = symbolLocation {
            #expect(location.relativePath == "src/verify-symbol.ts")
            #expect(location.line == 1)
            #expect(location.column == 17)
        } else {
            Issue.record("Expected symbol result to carry a semantic location")
        }
    }

    @Test func symbolIndexAndContentSearchShareDecodedTextPerPath() {
        let file = TerminalCommandPaletteIndexedFile(
            absolutePath: "/tmp/yen-palette-shared/src/SharedNeedle.swift",
            relativePath: "src/SharedNeedle.swift",
            baseName: "SharedNeedle.swift"
        )
        let duplicateFile = TerminalCommandPaletteIndexedFile(
            absolutePath: file.absolutePath,
            relativePath: file.relativePath,
            baseName: file.baseName
        )
        var loadCounts: [String: Int] = [:]

        let output = TerminalCommandPaletteSearchEngine.searchForTesting(
            query: "SharedNeedle",
            context: TerminalCommandPaletteContext(
                projectRoot: "/tmp/yen-palette-shared",
                runtime: [],
                tooling: []
            ),
            actions: [],
            cachedFiles: [file, duplicateFile],
            cachedSymbols: nil,
            textContents: { path in
                loadCounts[path, default: 0] += 1
                return "struct SharedNeedle {}\n"
            }
        )

        let hasSymbolResult = output.results.contains { result in
            result.source == .symbol &&
                result.targetKey == "src/SharedNeedle.swift:1:8" &&
                result.title == "SharedNeedle [struct]"
        }
        let hasContentResult = output.results.contains { result in
            result.source == .content &&
                result.targetKey == "src/SharedNeedle.swift:1:8"
        }

        #expect(loadCounts[file.absolutePath] == 1)
        #expect(hasSymbolResult)
        #expect(hasContentResult)
        #expect(output.cachedSymbols?.map(\.symbolName) == ["SharedNeedle"])
    }

    @Test func historyResultsUseUniqueTargetsWhenTimestampsCollide() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-history-collision-")
        let stateDir = try makeTemporaryDirectory(prefix: "yen-palette-history-state-")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: stateDir)
        }
        let resolvedRoot = root.resolvingSymlinksInPath()

        try write("{}", to: root.appendingPathComponent("package.json"))

        let historyDirectory = stateDir.appendingPathComponent("history", isDirectory: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        let historyHash = TerminalCommandPaletteProjectContextResolver.projectHash(root: resolvedRoot.path)
        let historyFile = historyDirectory.appendingPathComponent("\(historyHash).log")
        try write(
            [
                "2026-03-07T12:00:00Z\t\(resolvedRoot.path)\tyen ide verify --quick",
                "2026-03-07T12:00:00Z\t\(resolvedRoot.path)\tyen ide verify --strict",
            ].joined(separator: "\n") + "\n",
            to: historyFile
        )

        let context = TerminalCommandPaletteProjectContextResolver.resolve(pwd: root.path)
        let results = TerminalCommandPaletteSearchEngine.search(
            query: "verify",
            context: context,
            actions: [],
            cachedFiles: nil,
            cachedSymbols: nil,
            ideStateDirectoryOverride: stateDir.path
        )

        let historyTargets = results.results.compactMap { result -> String? in
            result.source == TerminalCommandPaletteResultSource.history ? result.targetKey : nil
        }
        #expect(historyTargets.count == 2)
        #expect(Set(historyTargets).count == 2)
    }

    @Test func searchTieOrderingIsDeterministicByTarget() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-order-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))
        try write("alpha\n", to: root.appendingPathComponent("a-verify.txt"))
        try write("beta\n", to: root.appendingPathComponent("b-verify.txt"))

        let context = TerminalCommandPaletteProjectContextResolver.resolve(pwd: root.path)
        let results = TerminalCommandPaletteSearchEngine.search(
            query: "verify",
            context: context,
            actions: [],
            cachedFiles: nil,
            cachedSymbols: nil
        )

        let fileTargets = results.results.compactMap { result -> String? in
            result.source == TerminalCommandPaletteResultSource.file ? result.targetKey : nil
        }
        #expect(fileTargets.starts(with: ["a-verify.txt", "b-verify.txt"]))
    }

    @Test func ideQuickActionsRemainSearchableWhenFlagsAndDigitsMatter() {
        let actions = TerminalCommandPaletteView.ideQuickActionBlueprints.map { blueprint in
            TerminalCommandPaletteActionSearchDescriptor(
                id: blueprint.id,
                title: blueprint.title,
                subtitle: nil,
                description: blueprint.description,
                searchTags: blueprint.searchTags
            )
        }

        let expectations = [
            ("workspace doctor", "ide:doctor"),
            ("format status", "ide:format-status"),
            ("lint status", "ide:lint-status"),
            ("fix status", "ide:fix-status"),
            ("debug status", "ide:debug-status"),
            ("debug tui", "ide:debug-tui"),
            ("lsp status", "ide:lsp-status"),
            ("diagnostics", "ide:lsp-diagnostics"),
            ("share status", "ide:share-status"),
            ("install matrix", "ide:lsp-install-status"),
            ("read only", "ide:share-host-read-only"),
            ("share revoke", "ide:share-revoke"),
            ("devcontainer status", "ide:devcontainer-status"),
            ("vscode inventory", "ide:vscode-inventory"),
            ("dry run", "ide:vscode-import-dry-run"),
            ("ast status", "ide:ast-status"),
        ]

        for (query, expectedID) in expectations {
            let results = TerminalCommandPaletteSearchEngine.search(
                query: query,
                context: .empty,
                actions: actions,
                cachedFiles: nil,
                cachedSymbols: nil
            )

            let actionIDs = results.results.compactMap { result -> String? in
                guard case let .action(id) = result.execution else { return nil }
                return id
            }

            #expect(actionIDs.first == expectedID)
        }
    }

    @Test func filenameMatchesDoNotExplodeIntoPerLineContentResults() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-filename-only-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))
        try write(
            Array(repeating: "plain text", count: 20).joined(separator: "\n"),
            to: root.appendingPathComponent("docs/verify-guide.txt")
        )

        let context = TerminalCommandPaletteProjectContextResolver.resolve(pwd: root.path)
        let results = TerminalCommandPaletteSearchEngine.search(
            query: "verify",
            context: context,
            actions: [],
            cachedFiles: nil,
            cachedSymbols: nil
        )

        let fileOnlyMatch = results.results.first { result in
            result.source == TerminalCommandPaletteResultSource.file &&
                result.targetKey == "docs/verify-guide.txt"
        }
        let contentMatches = results.results.filter { result in
            result.source == TerminalCommandPaletteResultSource.content
        }
        #expect(fileOnlyMatch != nil)
        #expect(contentMatches.isEmpty)
    }

    @Test func searchSkipsVendoredAndGeneratedDirectories() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-ignore-dirs-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))
        try write("verify workspace\n", to: root.appendingPathComponent("src/verify-workspace.txt"))
        try write("verify dependency\n", to: root.appendingPathComponent("node_modules/verify-dependency.txt"))
        try write("verify engine\n", to: root.appendingPathComponent("ghostty/verify-engine.txt"))
        try write("verify cache\n", to: root.appendingPathComponent(".next/verify-cache.txt"))

        let context = TerminalCommandPaletteProjectContextResolver.resolve(pwd: root.path)
        let results = TerminalCommandPaletteSearchEngine.search(
            query: "verify",
            context: context,
            actions: [],
            cachedFiles: nil,
            cachedSymbols: nil
        )

        let workspaceMatch = results.results.first { result in
            result.source == TerminalCommandPaletteResultSource.file &&
                result.targetKey == "src/verify-workspace.txt"
        }
        let blockedTargets = results.results.map { $0.targetKey }
        #expect(workspaceMatch != nil)
        #expect(blockedTargets.contains(where: { $0.hasPrefix("node_modules/") }) == false)
        #expect(blockedTargets.contains(where: { $0.hasPrefix("ghostty/") }) == false)
        #expect(blockedTargets.contains(where: { $0.hasPrefix(".next/") }) == false)
    }

    @MainActor
    @Test func searchModelKeepsActionMatchesOutOfProjectSearch() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-immediate-actions-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))
        for index in 0..<400 {
            try write("verify \(index)\n", to: root.appendingPathComponent("src/file-\(index).txt"))
        }

        let model = TerminalCommandPaletteSearchModel()
        model.refreshContext(
            projectDirectory: root.path,
            actions: [
                TerminalCommandPaletteActionSearchDescriptor(
                    id: "workspace:rename-split-label",
                    title: "Rename Split Label",
                    subtitle: "Change the bottom label for the focused split pane",
                    description: nil,
                    searchTags: ["split", "label", "rename"]
                ),
            ]
        )

        model.queryDidChange(to: "split")

        let renameSplitLabel = model.results.first { result in
            result.source == TerminalCommandPaletteResultSource.action &&
                result.title == "Rename Split Label"
        }
        #expect(renameSplitLabel != nil)
        #expect(model.isSearching == false)

        try await Task.sleep(nanoseconds: 400_000_000)

        let modelSources = model.results.map { $0.source }
        #expect(modelSources == [TerminalCommandPaletteResultSource.action])
        #expect(model.isSearching == false)
    }

    @MainActor
    @Test func searchModelFindsTitleRenameActionsImmediately() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-title-actions-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))

        let model = TerminalCommandPaletteSearchModel()
        model.refreshContext(
            projectDirectory: root.path,
            actions: [
                TerminalCommandPaletteActionSearchDescriptor(
                    id: "terminal:rename-terminal-title",
                    title: "Rename Terminal Title",
                    subtitle: "Change the active terminal title override",
                    description: nil,
                    searchTags: ["terminal", "title", "rename"]
                ),
                TerminalCommandPaletteActionSearchDescriptor(
                    id: "terminal:rename-tab-title",
                    title: "Rename Tab Title",
                    subtitle: "Change the selected tab title override",
                    description: nil,
                    searchTags: ["tab", "title", "rename"]
                ),
            ]
        )

        model.queryDidChange(to: "tab title")

        let renameTabTitle = model.results.first { result in
            result.source == TerminalCommandPaletteResultSource.action &&
                result.title == "Rename Tab Title"
        }
        #expect(renameTabTitle != nil)
        #expect(model.isSearching == false)
    }

    @MainActor
    @Test func searchModelRoutesWindowTitleQueriesToTabRenameAction() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-window-title-actions-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))

        let model = TerminalCommandPaletteSearchModel()
        model.refreshContext(
            projectDirectory: root.path,
            actions: [
                TerminalCommandPaletteActionSearchDescriptor(
                    id: "terminal:rename-terminal-title",
                    title: "Rename Terminal Title",
                    subtitle: "Change the active terminal title override",
                    description: nil,
                    searchTags: ["terminal", "title", "rename", "name"]
                ),
                TerminalCommandPaletteActionSearchDescriptor(
                    id: "terminal:rename-tab-title",
                    title: "Rename Tab Title",
                    subtitle: "Change the selected tab title override",
                    description: nil,
                    searchTags: ["tab", "title", "rename", "window title", "name"]
                ),
            ]
        )

        model.queryDidChange(to: "window title")

        #expect(model.results.first?.title == "Rename Tab Title")
        let renameTerminalTitle = model.results.first { result in
            result.source == TerminalCommandPaletteResultSource.action &&
                result.title == "Rename Terminal Title"
        }
        #expect(renameTerminalTitle == nil)
        #expect(model.isSearching == false)
    }

    @MainActor
    @Test func searchModelFallsBackToProjectSearchWhenActionsMiss() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-project-search-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))
        try write("verify notes\n", to: root.appendingPathComponent("src/verify-guide.txt"))

        let model = TerminalCommandPaletteSearchModel()
        model.refreshContext(
            projectDirectory: root.path,
            actions: [
                TerminalCommandPaletteActionSearchDescriptor(
                    id: "settings:open",
                    title: "Settings",
                    subtitle: "Open Settings",
                    description: nil,
                    searchTags: ["settings", "preferences"]
                ),
            ]
        )

        model.queryDidChange(to: "verify")

        #expect(model.isSearching)

        await waitUntil(description: "background project search completion") {
            model.isSearching == false &&
                model.results.contains(where: { result in
                    result.source == TerminalCommandPaletteResultSource.file &&
                        result.targetKey == "src/verify-guide.txt"
                })
        }
    }

    @MainActor
    @Test func searchModelIgnoresLateBackgroundResultsFromEarlierQueries() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-stale-query-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))

        let model = TerminalCommandPaletteSearchModel(
            debounceNanoseconds: 0,
            immediateSearch: { _, _, _ in [] },
            backgroundSearch: { query, context, _, _, _ in
                let delay = query == "verify" ? 0.15 : 0.02
                return await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        let target = query == "verify" ? "verify-guide.md" : "alpha-guide.md"
                        continuation.resume(
                            returning: TerminalCommandPaletteSearchOutput(
                                results: [
                                    TerminalCommandPaletteSearchResult(
                                        source: .file,
                                        score: 70,
                                        targetKey: target,
                                        previewKey: target,
                                        title: target,
                                        subtitle: context.projectRoot,
                                        execution: .openLocation(
                                            TerminalCommandPaletteLocation(
                                                path: "\(context.projectRoot ?? "")/\(target)",
                                                relativePath: target,
                                                line: nil,
                                                column: nil
                                            )
                                        )
                                    ),
                                ],
                                cachedFiles: nil,
                                cachedSymbols: nil
                            )
                        )
                    }
                }
            }
        )
        model.refreshContext(projectDirectory: root.path, actions: [])

        model.queryDidChange(to: "verify")
        try? await Task.sleep(nanoseconds: 10_000_000)
        model.queryDidChange(to: "alpha")

        await waitUntil(description: "latest query results") {
            model.isSearching == false &&
                model.results.map(\.targetKey) == ["alpha-guide.md"]
        }

        try? await Task.sleep(nanoseconds: 250_000_000)

        #expect(model.results.map(\.targetKey) == ["alpha-guide.md"])
        #expect(model.isSearching == false)
    }

    @MainActor
    @Test func singleCharacterActionQueryDoesNotStartBackgroundProjectSearch() throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-single-char-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))
        try write("settings docs\n", to: root.appendingPathComponent("src/settings-guide.txt"))

        let model = TerminalCommandPaletteSearchModel()
        model.refreshContext(
            projectDirectory: root.path,
            actions: [
                TerminalCommandPaletteActionSearchDescriptor(
                    id: "settings:open",
                    title: "Settings",
                    subtitle: "Open Settings",
                    description: nil,
                    searchTags: ["settings", "preferences"]
                ),
            ]
        )

        model.queryDidChange(to: "s")

        let settingsResult = model.results.first { result in
            result.source == TerminalCommandPaletteResultSource.action &&
                result.title == "Settings"
        }
        #expect(settingsResult != nil)
        #expect(model.isSearching == false)
    }

    @MainActor
    @Test func searchModelClearsResultsForEmptyQuery() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-model-empty-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))
        try write("verify\n", to: root.appendingPathComponent("verify-guide.md"))

        let model = TerminalCommandPaletteSearchModel()
        model.refreshContext(
            projectDirectory: root.path,
            actions: [
                TerminalCommandPaletteActionSearchDescriptor(
                    id: "action:verify",
                    title: "Verify Project",
                    subtitle: nil,
                    description: nil,
                    searchTags: ["verify"]
                ),
            ]
        )

        model.queryDidChange(to: "verify")
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(!model.results.isEmpty)

        model.queryDidChange(to: "")

        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
    }

    @MainActor
    @Test func searchModelResetSessionCancelsPendingWork() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-model-reset-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))
        for index in 0..<200 {
            try write("verify \(index)\n", to: root.appendingPathComponent("src/file-\(index).txt"))
        }

        let model = TerminalCommandPaletteSearchModel()
        model.refreshContext(projectDirectory: root.path, actions: [])
        model.queryDidChange(to: "verify")
        model.resetSession()

        try await Task.sleep(nanoseconds: 400_000_000)

        #expect(model.query.isEmpty)
        #expect(model.results.isEmpty)
        #expect(model.isSearching == false)
    }

    @MainActor
    @Test func searchModelRefreshContextDropsStaleProjectResults() async throws {
        let rootA = try makeTemporaryDirectory(prefix: "yen-palette-model-root-a-")
        let rootB = try makeTemporaryDirectory(prefix: "yen-palette-model-root-b-")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        try write("{}", to: rootA.appendingPathComponent("package.json"))
        try write("{}", to: rootB.appendingPathComponent("package.json"))
        try write("verify alpha\n", to: rootA.appendingPathComponent("verify-alpha.md"))
        try write("verify beta\n", to: rootB.appendingPathComponent("verify-beta.md"))

        let model = TerminalCommandPaletteSearchModel()
        model.refreshContext(projectDirectory: rootA.path, actions: [])
        model.queryDidChange(to: "verify")
        await waitUntil(description: "search results for initial context") {
            model.isSearching == false &&
                model.results.contains(where: { result in
                    result.targetKey == "verify-alpha.md"
                })
        }
        model.refreshContext(projectDirectory: rootB.path, actions: [])

        #expect(model.results.isEmpty)

        await waitUntil(description: "search results for refreshed context") {
            model.isSearching == false &&
                model.results.contains(where: { result in
                    result.targetKey == "verify-beta.md"
                }) &&
                !model.results.contains(where: { result in
                    result.targetKey == "verify-alpha.md"
                })
        }
    }

    @MainActor
    @Test func emptyQueryReleasesCachedFileIndexForNextSearch() async throws {
        let root = try makeTemporaryDirectory(prefix: "yen-palette-model-cache-reset-")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("{}", to: root.appendingPathComponent("package.json"))
        try write("verify original\n", to: root.appendingPathComponent("verify-original.md"))

        let model = TerminalCommandPaletteSearchModel()
        model.refreshContext(projectDirectory: root.path, actions: [])
        model.queryDidChange(to: "verify")

        await waitUntil(description: "search results for initial cache fill") {
            model.isSearching == false &&
                model.results.contains(where: { result in
                    result.targetKey == "verify-original.md"
                })
        }

        model.queryDidChange(to: "")
        try write("verify new\n", to: root.appendingPathComponent("verify-new.md"))
        model.queryDidChange(to: "verify")

        await waitUntil(description: "search results after cache release") {
            model.isSearching == false &&
                model.results.contains(where: { result in
                    result.targetKey == "verify-new.md"
                })
        }
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(prefix)\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1.5,
        description: String,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            await advanceMainQueueTurn()
        }

        Issue.record("Timed out waiting for \(description)")
    }

    private func advanceMainQueueTurn() async {
        try? await Task.sleep(nanoseconds: 10_000_000)
        await Task.yield()
    }

    private func write(_ value: String, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try value.write(to: url, atomically: true, encoding: .utf8)
    }
}

private final class PaletteContextThreadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var main = false
    private var finished = 0
    var completed: Int { lock.lock(); defer { lock.unlock() }; return finished }
    func finish() { lock.lock(); defer { lock.unlock() }; finished += 1 }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    var ranOnMain: Bool { lock.lock(); defer { lock.unlock() }; return main }
    func record() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        main = main || Thread.isMainThread
    }
}
