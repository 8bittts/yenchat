#if os(macOS)
import Foundation

struct ThemeCatalogDirectoryState: Sendable, Equatable {
    struct Metadata: Sendable, Equatable {
        let exists: Bool
        let modificationDate: Date?
    }

    let userThemes: Metadata
    let bundledThemes: Metadata

    static let empty = ThemeCatalogDirectoryState(
        userThemes: .init(exists: false, modificationDate: nil),
        bundledThemes: .init(exists: false, modificationDate: nil)
    )
}

struct ThemeCatalogSnapshot: Sendable {
    let visibleThemes: [ThemeInfo]
    let resolvedEntriesByLookupKey: [String: ThemeCatalogEntry]
    let directoryState: ThemeCatalogDirectoryState

    static let empty = ThemeCatalogSnapshot(
        visibleThemes: [],
        resolvedEntriesByLookupKey: [:],
        directoryState: .empty
    )
}

struct ThemeCatalogEntry: Sendable, Equatable {
    let name: String
    /// The file name inside its theme directory, including any `.yen` suffix.
    /// This is the only reference the engine resolves for a named theme.
    let fileName: String
    let path: String
    let bundled: Bool
    let tags: Set<String>

    func makeThemeInfo() -> ThemeInfo {
        ThemeInfo(
            name: name,
            path: path,
            bundled: bundled,
            tags: tags,
            configReference: fileName
        )
    }
}

enum SettingsThemeCatalog {
    private static let pinnedThemeOrder: [String] = [
        "YEN",
        "Retro Terminal",
        "CutePretzel",
    ]

    private static let supportedThemeCategoryTags: Set<String> = [
        "dark",
        "light",
        "retro",
        "neon",
        "low-contrast",
        "high-contrast",
    ]

#if DEBUG
    private static let metricsLock = NSLock()
    private static var directoryScanCount = 0
#endif

    static func directoryState(
        userThemesDirectory: String,
        themesDirectory: String
    ) -> ThemeCatalogDirectoryState {
        ThemeCatalogDirectoryState(
            userThemes: metadata(for: userThemesDirectory),
            bundledThemes: metadata(for: themesDirectory)
        )
    }

    static func buildSnapshot(
        userThemesDirectory: String,
        themesDirectory: String,
        bundledThemeManifestPath: String,
        bundledThemeTagsPath: String
    ) -> ThemeCatalogSnapshot {
        buildSnapshot(
            userThemesDirectory: userThemesDirectory,
            themesDirectory: themesDirectory,
            bundledThemeManifestPath: bundledThemeManifestPath,
            bundledThemeTagsPath: bundledThemeTagsPath,
            directoryState: directoryState(
                userThemesDirectory: userThemesDirectory,
                themesDirectory: themesDirectory
            )
        )
    }

    static func buildSnapshot(
        userThemesDirectory: String,
        themesDirectory: String,
        bundledThemeManifestPath: String,
        bundledThemeTagsPath: String,
        directoryState: ThemeCatalogDirectoryState
    ) -> ThemeCatalogSnapshot {
        if Task.isCancelled {
            return .empty
        }

        let curatedBundledThemeList = loadCuratedBundledThemeList(from: bundledThemeManifestPath)
        let curatedBundledThemes = Set(curatedBundledThemeList)
        let curatedBundledThemeOrder = Dictionary(
            uniqueKeysWithValues: curatedBundledThemeList.enumerated().map { index, name in
                (name, index)
            }
        )
        let curatedThemeTags = loadCuratedThemeTags(from: bundledThemeTagsPath)

        var visibleEntries: [ThemeCatalogEntry] = []
        var visibleSeen: Set<String> = []
        var resolvedEntriesByLookupKey: [String: ThemeCatalogEntry] = [:]

        appendThemes(
            from: userThemesDirectory,
            bundled: false,
            allowedBundledThemes: nil,
            themeTags: curatedThemeTags,
            includeInVisibleThemes: true,
            visibleEntries: &visibleEntries,
            visibleSeen: &visibleSeen,
            resolvedEntriesByLookupKey: &resolvedEntriesByLookupKey
        )
        appendThemes(
            from: themesDirectory,
            bundled: true,
            allowedBundledThemes: curatedBundledThemes,
            themeTags: curatedThemeTags,
            includeInVisibleThemes: true,
            visibleEntries: &visibleEntries,
            visibleSeen: &visibleSeen,
            resolvedEntriesByLookupKey: &resolvedEntriesByLookupKey
        )
        let visibleThemes = sortedVisibleThemes(
            from: visibleEntries,
            curatedBundledThemeOrder: curatedBundledThemeOrder
        )
        return ThemeCatalogSnapshot(
            visibleThemes: visibleThemes,
            resolvedEntriesByLookupKey: resolvedEntriesByLookupKey,
            directoryState: directoryState
        )
    }

    static func isSnapshot(
        _ snapshot: ThemeCatalogSnapshot,
        validFor directoryState: ThemeCatalogDirectoryState
    ) -> Bool {
        snapshot.directoryState == directoryState
    }

    static func resolveThemeInfo(named themeName: String, in snapshot: ThemeCatalogSnapshot) -> ThemeInfo? {
        let lookupKey = normalizedThemeLookupKey(themeName)
        guard !lookupKey.isEmpty,
              let entry = snapshot.resolvedEntriesByLookupKey[lookupKey] else {
            return nil
        }
        return entry.makeThemeInfo()
    }

#if DEBUG
    static func _testResetMetrics() {
        metricsLock.lock()
        directoryScanCount = 0
        metricsLock.unlock()
    }

    static var _testDirectoryScanCount: Int {
        metricsLock.lock()
        defer { metricsLock.unlock() }
        return directoryScanCount
    }
#endif

    private static func metadata(for directory: String) -> ThemeCatalogDirectoryState.Metadata {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            return .init(exists: false, modificationDate: nil)
        }
        let attributes = (try? FileManager.default.attributesOfItem(atPath: directory)) ?? [:]
        return .init(
            exists: true,
            modificationDate: attributes[.modificationDate] as? Date
        )
    }

    @discardableResult
    private static func appendThemes(
        from directory: String,
        bundled: Bool,
        allowedBundledThemes: Set<String>?,
        themeTags: [String: Set<String>],
        includeInVisibleThemes: Bool,
        visibleEntries: inout [ThemeCatalogEntry],
        visibleSeen: inout Set<String>,
        resolvedEntriesByLookupKey: inout [String: ThemeCatalogEntry]
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: directory),
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return false }

#if DEBUG
        metricsLock.lock()
        directoryScanCount += 1
        metricsLock.unlock()
#endif

        var foundThemes = false
        for file in files {
            if Task.isCancelled { return foundThemes }
            guard !file.hasPrefix(".") else { continue }
            let name = file.hasSuffix(".yen") ? String(file.dropLast(4)) : file
            if bundled,
               let allowedBundledThemes,
               !allowedBundledThemes.contains(normalizedThemeLookupKey(name)) {
                continue
            }

            let lookupKey = normalizedThemeLookupKey(name)
            let entry = ThemeCatalogEntry(
                name: name,
                fileName: file,
                path: "\(directory)/\(file)",
                bundled: bundled,
                tags: themeTags[lookupKey] ?? []
            )
            guard !lookupKey.isEmpty else { continue }
            foundThemes = true

            if resolvedEntriesByLookupKey[lookupKey] == nil {
                resolvedEntriesByLookupKey[lookupKey] = entry
            }

            if includeInVisibleThemes, visibleSeen.insert(name).inserted {
                visibleEntries.append(entry)
            }
        }

        return foundThemes
    }

    private static func sortedVisibleThemes(
        from entries: [ThemeCatalogEntry],
        curatedBundledThemeOrder: [String: Int]
    ) -> [ThemeInfo] {
        // Decorate-sort-undecorate. The comparator used to recompute
        // `pinnedThemeOrder.firstIndex(of:)` and `normalizedThemeLookupKey` for BOTH
        // sides of every comparison — O(n log n) linear scans and key rebuilds for a
        // value that is fixed per entry. Ordering is unchanged.
        let decorated = entries.map { entry -> (entry: ThemeCatalogEntry, pinned: Int, manifest: Int) in
            (
                entry: entry,
                pinned: pinnedThemeOrder.firstIndex(of: entry.name) ?? Int.max,
                manifest: curatedBundledThemeOrder[normalizedThemeLookupKey(entry.name)] ?? Int.max
            )
        }

        return decorated
            .sorted { a, b in
                if a.pinned != b.pinned { return a.pinned < b.pinned }
                if a.manifest != b.manifest { return a.manifest < b.manifest }
                return a.entry.name.localizedCaseInsensitiveCompare(b.entry.name) == .orderedAscending
            }
            .map { $0.entry.makeThemeInfo() }
    }

    private static func loadCuratedBundledThemeList(from manifestPath: String) -> [String] {
        guard !manifestPath.isEmpty,
              let manifest = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
            return []
        }

        return manifest
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
                let lookupKey = normalizedThemeLookupKey(trimmed)
                guard !lookupKey.isEmpty else { return nil }
                return lookupKey
            }
    }

    private static func loadCuratedThemeTags(from themeTagsPath: String) -> [String: Set<String>] {
        guard !themeTagsPath.isEmpty,
              let contents = try? String(contentsOfFile: themeTagsPath, encoding: .utf8) else {
            return [:]
        }

        var tagsByTheme: [String: Set<String>] = [:]
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let themeName = normalizedThemeLookupKey(parts[0])
            guard !themeName.isEmpty else { continue }

            let tags = parts[1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { supportedThemeCategoryTags.contains($0) }

            if !tags.isEmpty {
                tagsByTheme[themeName] = Set(tags)
            }
        }

        return tagsByTheme
    }

    private static func normalizedThemeName(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
            || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func normalizedThemeLookupKey(_ rawValue: String) -> String {
        let normalizedName = normalizedThemeName(rawValue)
        guard !normalizedName.isEmpty else { return "" }

        var baseName = normalizedName
        let lowercasedName = normalizedName.lowercased()
        if lowercasedName.hasSuffix(".yentheme") {
            baseName = String(normalizedName.dropLast(9))
        } else if lowercasedName.hasSuffix(".yen") {
            baseName = String(normalizedName.dropLast(4))
        }

        let folded = baseName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        // `[\s\-_]+` is a pure character class, so a filter is exactly equivalent and
        // does not compile an NSRegularExpression on every call. This runs twice per
        // sort comparison.
        return folded
            .lowercased()
            .filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }
}
#endif
