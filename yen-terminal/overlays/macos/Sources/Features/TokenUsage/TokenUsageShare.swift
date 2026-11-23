import Foundation

extension Notification.Name {
    /// Posted when today's per-folder token counts change, so the tab sidebar redraws its rows.
    static let yenTokenProjectUsageDidChange = Notification.Name("com.yenchat.yen.tokenProjectUsageDidChange")
}

/// Today's tokens per working folder, published by the token menu while it runs. The tab sidebar
/// reads it for each tab's folder; it is empty while the menu is off.
@MainActor
final class TokenProjectUsage {
    static let shared = TokenProjectUsage()
    private(set) var projects: [String: TokenUsageIndex.Counts] = [:]

    func update(_ projects: [String: TokenUsageIndex.Counts]) {
        guard projects != self.projects else { return }
        self.projects = projects
        NotificationCenter.default.post(name: .yenTokenProjectUsageDidChange, object: nil)
    }

    func clear() { update([:]) }

    /// Tokens an agent used today in `directory` or a folder inside it. When none ran there, the
    /// nearest folder above it with usage counts, since agents usually start at a repository's root.
    nonisolated static func tokens(forDirectory directory: String, in projects: [String: TokenUsageIndex.Counts]) -> Int? {
        let path = directory.count > 1 && directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        guard path.hasPrefix("/"), !projects.isEmpty else { return nil }
        let inside = projects.filter { $0.key == path || $0.key.hasPrefix(path == "/" ? "/" : path + "/") }
        if !inside.isEmpty { return inside.values.reduce(0) { $0 + $1.values.reduce(0, +) } }
        var parent = (path as NSString).deletingLastPathComponent
        while parent.count > 1 {
            if let counts = projects[parent] { return counts.values.reduce(0, +) }
            parent = (parent as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// "41.2M tokens today" for a tab's folder, or nil when no agent used tokens there today.
    func summary(forDirectory directory: String?) -> String? {
        guard let directory, let tokens = Self.tokens(forDirectory: directory, in: projects), tokens > 0 else { return nil }
        return tokens.formatted(.number.notation(.compactName).precision(.significantDigits(1...3))) + " tokens today"
    }
}

/// The file `yen usage` prints: today's counts, plan readings and folders, written after each
/// reading while the token menu runs and removed when it stops. It holds numbers, folder paths and
/// plan labels only, never record text.
enum TokenUsageReport {
    static func url(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".local/state/yen/token-usage.json")
    }

    struct Pool: Codable, Equatable {
        let label: String
        let percent: Double
        let resetsAt: Date?
    }

    struct Tool: Codable, Equatable {
        let name: String
        let tokens: Int?
        let limits: [Pool]
    }

    struct Folder: Codable, Equatable {
        let path: String
        let tokens: Int
        let tools: [String: Int]
    }

    struct Report: Codable, Equatable {
        var version = 1
        let updatedAt: Date
        let day: String
        let total: Int
        let sources: Int
        let tools: [Tool]
        let folders: [Folder]
    }

    static func make(counts: TokenUsageIndex.Counts, plans: [TokenTool: [TokenPlanMeter]],
                     projects: [String: TokenUsageIndex.Counts], now: Date) -> Report {
        let tools = TokenTool.allCases.map { tool in
            Tool(name: tool.rawValue, tokens: counts[tool],
                 limits: (plans[tool] ?? []).filter { $0.isCurrent(at: now) }
                    .map { Pool(label: $0.label, percent: $0.percent, resetsAt: $0.reset) })
        }
        let folders = projects.map { path, counts in
            Folder(path: path, tokens: counts.values.reduce(0, +),
                   tools: Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }))
        }.sorted { ($0.tokens, $1.path) > ($1.tokens, $0.path) }
        return Report(updatedAt: now, day: now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()),
                      total: counts.values.reduce(0, +), sources: counts.count, tools: tools, folders: folders)
    }

    static func write(_ report: Report, to url: URL = url()) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func remove(at url: URL = url()) { try? FileManager.default.removeItem(at: url) }
}
