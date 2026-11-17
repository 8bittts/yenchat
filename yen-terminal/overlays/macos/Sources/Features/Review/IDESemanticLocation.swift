#if os(macOS)
import AppKit
import Foundation

struct IDESemanticLocation: Sendable, Hashable {
    let path: String
    let relativePath: String?
    let line: Int?
    let column: Int?
    let severity: String?
    let code: String?
    let diagnosticSource: String?

    init(
        path: String,
        relativePath: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        severity: String? = nil,
        code: String? = nil,
        diagnosticSource: String? = nil
    ) {
        self.path = path
        self.relativePath = relativePath
        self.line = line
        self.column = column
        self.severity = severity
        self.code = code
        self.diagnosticSource = diagnosticSource
    }

    var displayPath: String {
        relativePath ?? path
    }

    var target: String {
        guard let line else { return displayPath }
        if let column {
            return "\(displayPath):\(line):\(column)"
        }
        return "\(displayPath):\(line)"
    }

    var editorColumn: Int? {
        guard line != nil else { return nil }
        return column ?? 1
    }

    static func repositoryLocation(
        repoRoot: String,
        relativePath: String,
        line: Int? = nil,
        column: Int? = nil,
        severity: String? = nil,
        code: String? = nil,
        diagnosticSource: String? = nil
    ) -> IDESemanticLocation {
        let absolutePath = URL(fileURLWithPath: repoRoot)
            .appendingPathComponent(relativePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        return IDESemanticLocation(
            path: absolutePath,
            relativePath: relativePath,
            line: line,
            column: column,
            severity: severity,
            code: code,
            diagnosticSource: diagnosticSource
        )
    }
}

typealias TerminalCommandPaletteLocation = IDESemanticLocation

struct IDEEditorLaunchPlan: Equatable {
}

struct IDEEditorCommandResult: Equatable {
    let terminationStatus: Int32
    let stdout: String
    let stderr: String
}

/// Failure surfaced by the editor-handoff spawn. `commandFailed` is unused on the
/// live path (the runner is invoked with `allowAnyExitCode`, so a non-zero editor
/// CLI exit is returned as a result rather than thrown); `toolUnavailable` covers
/// the CLI failing to launch at all.
private enum IDEEditorBridgeError: Error, LocalizedError {
    case toolUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolUnavailable:
            return "the editor handoff tool could not be launched"
        case .commandFailed(let detail):
            return detail
        }
    }
}

struct IDEEditorNavigatorEnvironment {
    var defaultEditorResolver: (URL) async -> URL?
    var bundledCLIResolver: () -> URL?
    var processRunner: (URL, [String]) async throws -> IDEEditorCommandResult
    var workspaceOpen: (URL, URL?) -> Void

    static var live: IDEEditorNavigatorEnvironment {
        IDEEditorNavigatorEnvironment(
            defaultEditorResolver: { fileURL in
                await Task.detached(priority: .userInitiated) {
                    NSWorkspace.shared.defaultApplicationURL(forExtension: fileURL.pathExtension) ??
                        NSWorkspace.shared.defaultTextEditor
                }.value
            },
            bundledCLIResolver: {
                guard let resourcePath = Bundle.main.resourcePath else { return nil }
                let candidate = URL(fileURLWithPath: resourcePath).appendingPathComponent("bin/yen")
                guard FileManager.default.isExecutableFile(atPath: candidate.path) else { return nil }
                return candidate
            },
            processRunner: { executableURL, arguments in
                // Route through the shared IDEBlockingProcessRunner, which drains
                // stdout/stderr concurrently before waiting on exit (so a chatty
                // child can't fill the ~64KB pipe buffer and deadlock) and spawns
                // off the main actor (a cold editor launch — LaunchServices
                // registration — can take hundreds of ms). `allowAnyExitCode`
                // returns non-zero statuses instead of throwing, since the caller
                // builds its own failure message from the status + output.
                let output = try await IDEBlockingProcessRunner.run(
                    executableURL: executableURL,
                    arguments: arguments,
                    currentDirectory: FileManager.default.currentDirectoryPath,
                    allowAnyExitCode: true,
                    toolUnavailable: IDEEditorBridgeError.toolUnavailable,
                    commandFailed: { IDEEditorBridgeError.commandFailed($0) }
                )
                return IDEEditorCommandResult(
                    terminationStatus: output.terminationStatus,
                    stdout: output.stdout,
                    stderr: output.stderr
                )
            },
            workspaceOpen: { fileURL, editorURL in
                if let editorURL {
                    NSWorkspace.shared.open(
                        [fileURL],
                        withApplicationAt: editorURL,
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                } else {
                    NSWorkspace.shared.open(fileURL)
                }
            }
        )
    }
}

@MainActor
enum IDEEditorNavigator {
    nonisolated private static func editorFamily(
        applicationName: String,
        bundleIdentifier: String?
    ) -> String? {
        let appName = applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerAppName = appName.lowercased()
        let knownBundleIdentifier = bundleIdentifier?.lowercased() ?? ""

        let isCodeFamily =
            knownBundleIdentifier.hasPrefix("com.microsoft.vscode") ||
            knownBundleIdentifier.contains("cursor") ||
            knownBundleIdentifier.contains("windsurf") ||
            knownBundleIdentifier.contains("vscodium") ||
            lowerAppName.contains("visual studio code") ||
            lowerAppName.contains("cursor") ||
            lowerAppName.contains("windsurf") ||
            lowerAppName.contains("codium")
        if isCodeFamily {
            return "code-family"
        }

        let isZed =
            knownBundleIdentifier.contains("zed") ||
            lowerAppName == "zed" ||
            lowerAppName.hasPrefix("zed ")
        if isZed {
            return "zed"
        }

        let isXcode =
            knownBundleIdentifier == "com.apple.dt.xcode" ||
            lowerAppName == "xcode" ||
            lowerAppName.hasPrefix("xcode ")
        if isXcode {
            return "xcode"
        }

        return nil
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    nonisolated private static func bridgeCommand(for editorURL: URL) -> String? {
        let applicationName = editorURL.deletingPathExtension().lastPathComponent
        let bundleIdentifier = Bundle(url: editorURL)?.bundleIdentifier
        guard editorFamily(applicationName: applicationName, bundleIdentifier: bundleIdentifier) != nil else {
            return nil
        }
        return "/usr/bin/open -a \(shellQuote(applicationName))"
    }

    private static func bridgeTarget(for location: IDESemanticLocation) -> String {
        guard let line = location.line else { return location.path }
        let column = location.editorColumn ?? 1
        return "\(location.path):\(line):\(column)"
    }

    private static func failureMessage(from result: IDEEditorCommandResult, fallback: String) -> String {
        let candidates = [result.stderr, result.stdout]
        for candidate in candidates {
            let lines = candidate
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let line = lines.last {
                return line
            }
        }
        return fallback
    }

    static func lineAwareEditorLaunchPlan(
        applicationName: String,
        bundleIdentifier: String?,
        path: String,
        line: Int,
        column: Int?
    ) -> IDEEditorLaunchPlan? {
        let appName = applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch editorFamily(applicationName: appName, bundleIdentifier: bundleIdentifier) {
        case "code-family", "zed", "xcode":
            return IDEEditorLaunchPlan()
        default:
            return nil
        }
    }

    @discardableResult
    static func open(
        _ location: IDESemanticLocation,
        environment: IDEEditorNavigatorEnvironment = .live
    ) async -> String? {
        let targetURL = URL(fileURLWithPath: location.path)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return "Editor target no longer exists: \(location.target)"
        }

        let editorURL = await environment.defaultEditorResolver(targetURL)
        if let editorURL {
            let editorMetadata = await Task.detached(priority: .userInitiated) {
                (
                    editorURL.deletingPathExtension().lastPathComponent,
                    bridgeCommand(for: editorURL)
                )
            }.value
            let editorName = editorMetadata.0
            guard FileManager.default.fileExists(atPath: editorURL.path) else {
                return "Default editor launcher is unavailable: \(editorName)."
            }

            if let bridgeCommand = editorMetadata.1 {
                guard let yenCLI = environment.bundledCLIResolver() else {
                    return "Bundled editor handoff bridge is unavailable. Rebuild YEN so Resources/bin/yen is present."
                }
                do {
                    let result = try await environment.processRunner(
                        yenCLI,
                        ["ide", "open", bridgeTarget(for: location), "--editor", bridgeCommand]
                    )
                    guard result.terminationStatus == 0 else {
                        return failureMessage(
                            from: result,
                            fallback: "Unable to open \(location.target) in \(editorName)."
                        )
                    }
                    return nil
                } catch {
                    return "Bundled editor handoff bridge failed: \(error.localizedDescription)"
                }
            }

            environment.workspaceOpen(targetURL, editorURL)
            return nil
        }

        environment.workspaceOpen(targetURL, nil)
        return nil
    }
}
#endif
