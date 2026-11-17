import Foundation

@MainActor
final class TerminalCommandPaletteSearchModel: ObservableObject {
    typealias ImmediateSearch = @Sendable (
        String,
        TerminalCommandPaletteContext,
        [TerminalCommandPaletteActionSearchDescriptor]
    ) -> [TerminalCommandPaletteSearchResult]

    typealias BackgroundSearch = @Sendable (
        String,
        TerminalCommandPaletteContext,
        [TerminalCommandPaletteActionSearchDescriptor],
        [TerminalCommandPaletteIndexedFile]?,
        [TerminalCommandPaletteIndexedSymbol]?
    ) async -> TerminalCommandPaletteSearchOutput

    @Published var query = ""
    @Published private(set) var results: [TerminalCommandPaletteSearchResult] = []
    @Published private(set) var isSearching = false

    private let debounceNanoseconds: UInt64
    private let resolveContext: @Sendable (String?) -> TerminalCommandPaletteContext
    private let immediateSearch: ImmediateSearch
    private let contentCache: TerminalCommandPaletteSearchCache
    private let backgroundSearch: BackgroundSearch
    private var context: TerminalCommandPaletteContext = .empty
    private var actions: [TerminalCommandPaletteActionSearchDescriptor] = []
    private var resolvedProjectDirectory: String?
    private var cachedRoot: String?
    private var cachedFiles: [TerminalCommandPaletteIndexedFile]?
    private var cachedSymbols: [TerminalCommandPaletteIndexedSymbol]?
    private var searchTask: Task<Void, Never>?
    private var searchTaskGeneration = 0
    private var contextTask: Task<Void, Never>?
    private var contextTaskGeneration = 0

    init(
        debounceNanoseconds: UInt64 = 180_000_000,
        resolveContext: @escaping @Sendable (String?) -> TerminalCommandPaletteContext = {
            TerminalCommandPaletteProjectContextResolver.resolve(pwd: $0)
        },
        immediateSearch: @escaping ImmediateSearch = { query, context, actions in
            TerminalCommandPaletteSearchEngine.immediateResults(
                query: query,
                context: context,
                actions: actions
            )
        },
        // Call the engine directly (no nested Task.detached). The caller runs this
        // inside a cancellable Task.detached (see scheduleSearch), so the engine's
        // cooperative `Task.isCancelled` checks observe worker.cancel() and abort
        // superseded scans instead of running the whole repo to completion.
        backgroundSearch: BackgroundSearch? = nil
    ) {
        self.debounceNanoseconds = debounceNanoseconds
        self.resolveContext = resolveContext
        self.immediateSearch = immediateSearch
        let cache = TerminalCommandPaletteSearchCache()
        self.contentCache = cache
        self.backgroundSearch = backgroundSearch ?? { query, context, actions, files, symbols in
            TerminalCommandPaletteSearchEngine.search(query: query, context: context, actions: actions,
                cachedFiles: files, cachedSymbols: symbols, cache: cache)
        }
    }

    func refreshContext(projectDirectory: String?, actions: [TerminalCommandPaletteActionSearchDescriptor]) {
        self.actions = actions
        guard projectDirectory != resolvedProjectDirectory else {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                scheduleSearch()
            }
            return
        }

        resolvedProjectDirectory = projectDirectory
        cancelContextTask()
        cancelSearchTask()
        context = .empty
        results = []
        cachedRoot = nil
        cachedFiles = nil
        cachedSymbols = nil
        contentCache.clear()
        guard projectDirectory != nil else {
            scheduleSearch()
            return
        }

        let generation = contextTaskGeneration
        let resolveContext = self.resolveContext
        contextTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .utility) { resolveContext(projectDirectory) }
            let resolved = await withTaskCancellationHandler(operation: { await worker.value },
                onCancel: { worker.cancel() })
            guard !Task.isCancelled, let self, self.contextTaskGeneration == generation else { return }
            self.contextTask = nil
            self.context = resolved
            self.cachedRoot = resolved.projectRoot
            if !self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.scheduleSearch() }
        }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { scheduleSearch() }
    }

    func queryDidChange(to newValue: String) {
        if query != newValue {
            query = newValue
        }
        scheduleSearch()
    }

    func resetSession() {
        cancelContextTask()
        cancelSearchTask()
        context = .empty
        query = ""
        results = []
        isSearching = false
        cachedRoot = nil
        cachedFiles = nil
        cachedSymbols = nil
        contentCache.clear()
        resolvedProjectDirectory = nil
    }

    deinit {
        contextTask?.cancel()
        searchTask?.cancel()
    }

    private func scheduleSearch() {
        cancelSearchTask(resetSearching: false)

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            isSearching = false
            cachedFiles = nil
            cachedSymbols = nil
            contentCache.clear()
            return
        }

        let context = self.context
        let actions = self.actions
        let cachedRoot = self.cachedRoot
        let cachedFiles = cachedRoot == context.projectRoot ? self.cachedFiles : nil
        let cachedSymbols = cachedRoot == context.projectRoot ? self.cachedSymbols : nil
        let immediateResults = immediateSearch(trimmedQuery, context, actions)
        results = immediateResults

        // Keep command-style lookups local to the in-memory action catalog.
        // Falling through to repo search when we already have a usable action hit
        // makes short palette queries feel slow and noisy.
        let shouldRunBackgroundSearch = immediateResults.isEmpty &&
            context.projectRoot != nil &&
            trimmedQuery.count >= TerminalCommandPaletteSearchEngine.minQueryLengthForFileSearch
        isSearching = shouldRunBackgroundSearch || (contextTask != nil && immediateResults.isEmpty &&
            trimmedQuery.count >= TerminalCommandPaletteSearchEngine.minQueryLengthForFileSearch)
        guard shouldRunBackgroundSearch else {
            return
        }

        searchTaskGeneration += 1
        let taskGeneration = searchTaskGeneration
        let debounceNanoseconds = self.debounceNanoseconds
        let backgroundSearch = self.backgroundSearch
        searchTask = Task { [weak self] in
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }

            // Detached so the heavy scan runs off the MainActor AND so worker.cancel()
            // (via the cancellation handler below) propagates Task.isCancelled into the
            // search engine — the previous nested Task.detached severed that signal.
            let worker = Task.detached(priority: .utility) {
                await backgroundSearch(
                    trimmedQuery,
                    context,
                    actions,
                    cachedFiles,
                    cachedSymbols
                )
            }
            let output = await withTaskCancellationHandler(
                operation: {
                    await worker.value
                },
                onCancel: {
                    worker.cancel()
                }
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.searchTaskGeneration == taskGeneration else { return }

                self.results = output.results
                self.isSearching = false
                self.searchTask = nil
                if let root = context.projectRoot, let indexedFiles = output.cachedFiles {
                    self.cachedRoot = root
                    self.cachedFiles = indexedFiles
                    self.cachedSymbols = output.cachedSymbols
                }
            }
        }
    }

    private func cancelContextTask() {
        contextTaskGeneration += 1
        contextTask?.cancel()
        contextTask = nil
    }

    private func cancelSearchTask(resetSearching: Bool = true) {
        searchTaskGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        if resetSearching {
            isSearching = false
        }
    }
}
