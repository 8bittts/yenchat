#if os(macOS)
import Foundation

enum GitBranchResolver {
    static func resolve<Runner: GitDrawerCommandRunning>(
        in workingDirectory: String,
        runner: Runner
    ) async -> String? {
        if let symbolic = await optionalLine(
            ["symbolic-ref", "--quiet", "--short", "HEAD"],
            in: workingDirectory,
            runner: runner
        ) {
            return symbolic
        }
        return await detached(in: workingDirectory, runner: runner)
    }

    static func detached<Runner: GitDrawerCommandRunning>(
        in workingDirectory: String, runner: Runner
    ) async -> String? {
        if let shortHead = await optionalLine(
            ["rev-parse", "--short", "HEAD"],
            in: workingDirectory,
            runner: runner
        ) {
            return "detached@\(shortHead)"
        }
        return nil
    }

    private static func optionalLine<Runner: GitDrawerCommandRunning>(
        _ arguments: [String],
        in workingDirectory: String,
        runner: Runner
    ) async -> String? {
        do {
            let output = try await runner.run(
                GitDrawerGitCommand(arguments: arguments),
                currentDirectory: workingDirectory,
                timeout: GitDrawerShellClient.defaultTimeout,
                stdoutLimit: 8 * 1024,
                stderrLimit: 4 * 1024
            )
            let trimmed = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}

/// One NUL-delimited status response supplies branch metadata and changed-file state.
struct GitStatusPorcelainV2: Sendable {
    struct Entry: Sendable {
        let code: String
        let path: String
        let oldPath: String?
        let isSubmodule: Bool
    }
    static let arguments = ["status", "--porcelain=v2", "-z", "--branch"]
    let head: String
    let oid: String
    let upstream: String?
    let ahead: Int
    let behind: Int
    let entries: [Entry]
    var hasCommits: Bool { oid != "(initial)" }
    var isDetached: Bool { head == "(detached)" }
    var dirty: Bool { !entries.isEmpty }

    init?(_ output: String) {
        guard output.hasSuffix("\0") else { return nil }
        let tokens = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var headers: [String: String] = [:]
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            index += token.hasPrefix("2 ") ? 2 : 1
            guard token.hasPrefix("# ") else { continue }
            let parts = token.dropFirst(2).split(separator: " ", maxSplits: 1)
            if parts.count == 2 { headers[String(parts[0])] = String(parts[1]) }
        }
        guard let head = headers["branch.head"], !head.isEmpty,
              let oid = headers["branch.oid"], !oid.isEmpty,
              let entries = Self.parseEntries(output) else { return nil }
        self.head = head
        self.oid = oid
        self.upstream = headers["branch.upstream"]
        if let countHeader = headers["branch.ab"] {
            let counts = countHeader.split(separator: " ")
            guard counts.count == 2, counts[0].hasPrefix("+"), counts[1].hasPrefix("-"),
                  let ahead = Int(counts[0].dropFirst()), ahead >= 0,
                  let behind = Int(counts[1].dropFirst()), behind >= 0 else { return nil }
            self.ahead = ahead
            self.behind = behind
        } else {
            ahead = 0
            behind = 0
        }
        self.entries = entries
    }

    static func parseEntries(_ output: String) -> [Entry]? {
        let tokens = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var entries: [Entry] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            if token.hasPrefix("# ") || token.hasPrefix("! ") { continue }
            if token.hasPrefix("? ") {
                entries.append(Entry(code: "??", path: String(token.dropFirst(2)), oldPath: nil, isSubmodule: false))
                continue
            }
            let fieldsCount: Int
            switch token.first {
            case "1": fieldsCount = 9
            case "2": fieldsCount = 10
            case "u": fieldsCount = 11
            default: return nil
            }
            let fields = token.split(separator: " ", maxSplits: fieldsCount - 1, omittingEmptySubsequences: false)
            guard fields.count == fieldsCount, fields[1].count == 2, !fields[fieldsCount - 1].isEmpty else { return nil }
            var oldPath: String?
            if token.first == "2" {
                guard index < tokens.count else { return nil }
                oldPath = tokens[index]
                index += 1
            }
            entries.append(Entry(code: String(fields[1]), path: String(fields[fieldsCount - 1]), oldPath: oldPath,
                isSubmodule: fields[2].hasPrefix("S") || fields[3..<(token.first == "u" ? 7 : 6)].contains("160000")))
        }
        return entries
    }
}

#endif
