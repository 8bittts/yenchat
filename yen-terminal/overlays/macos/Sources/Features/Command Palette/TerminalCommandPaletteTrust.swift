// YEN Overlay: command palette jump-target snapshots and repository trust checks.

import AppKit
import SwiftUI
import YENKit

extension TerminalCommandPaletteView {
    static func loadJumpTargetSnapshots(
        controllers: [TerminalController] = TerminalController.all
    ) -> [TerminalCommandPaletteJumpTargetSnapshot] {
        controllers.flatMap { controller -> [TerminalCommandPaletteJumpTargetSnapshot] in
            guard let window = controller.window else { return [] }

            let tabColor = (window as? TerminalWindow)?.tabColor ?? .none

            return controller.surfaceTree.map { surface in
                let terminalTitle = surface.title.isEmpty ? window.title : surface.title
                let remote = surface.remotePaneIdentity
                let jumpTitle = jumpDisplayTitle(
                    terminalTitle: terminalTitle,
                    titleOverride: controller.titleOverride
                )
                // A remote pane leads with its host, like its tab title.
                let displayTitle = remote.map { RemotePanes.tabTitle(jumpTitle, host: $0.displayName) } ?? jumpTitle
                let pwd = surface.pwd?.abbreviatedPath
                // A remote pane's local directory belongs to the CLI, not the shell.
                let subtitle: String? = if remote != nil {
                    nil
                } else if let pwd, !displayTitle.contains(pwd) {
                    pwd
                } else {
                    nil
                }

                return TerminalCommandPaletteJumpTargetSnapshot(
                    objectID: ObjectIdentifier(surface),
                    surface: surface,
                    title: displayTitle,
                    subtitle: subtitle,
                    tabColor: tabColor
                )
            }
        }
    }

    static func normalizedWorkingDirectory(_ workingDirectory: String?) -> String? {
        LocalPathResolver.canonicalPath(workingDirectory)
    }

    static func repositoryWorkspaceTrustContext(
        for workingDirectory: String?,
        workflowTrustFilePath: String? = nil,
        fileManager: FileManager = .default
    ) -> RepositoryWorkspaceTrustContext? {
        guard let normalizedWorkingDirectory = normalizedWorkingDirectory(workingDirectory) else {
            return nil
        }
        return repositoryWorkspaceTrustContext(
            forNormalizedWorkingDirectory: normalizedWorkingDirectory,
            workflowTrustFilePath: workflowTrustFilePath,
            fileManager: fileManager
        )
    }

    static func canonicalActionID(for optionID: String) -> String {
        let searchActionPrefix = "search:action:"
        guard optionID.hasPrefix(searchActionPrefix) else {
            return optionID
        }
        return String(optionID.dropFirst(searchActionPrefix.count))
    }

    nonisolated static func repositoryWorkspaceEligibility(
        for normalizedWorkingDirectory: String,
        workflowTrustFilePath: String? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        repositoryWorkspaceTrustContext(
            forNormalizedWorkingDirectory: normalizedWorkingDirectory,
            workflowTrustFilePath: workflowTrustFilePath,
            fileManager: fileManager
        ) != nil
    }

    nonisolated private static func repositoryWorkspaceTrustContext(
        forNormalizedWorkingDirectory normalizedWorkingDirectory: String,
        workflowTrustFilePath: String?,
        fileManager: FileManager
    ) -> RepositoryWorkspaceTrustContext? {
        guard let repositoryRoot = repositoryWorkspaceRoot(
            for: normalizedWorkingDirectory,
            fileManager: fileManager
        ) else {
            return nil
        }

        guard isWorkflowTrustedRepositoryRoot(
            repositoryRoot,
            workflowTrustFilePath: workflowTrustFilePath,
            fileManager: fileManager
        ) else {
            return nil
        }

        return RepositoryWorkspaceTrustContext(
            workingDirectory: normalizedWorkingDirectory,
            repositoryRoot: repositoryRoot
        )
    }

    nonisolated private static func repositoryWorkspaceRoot(
        for normalizedWorkingDirectory: String,
        fileManager: FileManager
    ) -> String? {
        var isDir = ObjCBool(false)
        let dirExists = fileManager.fileExists(atPath: normalizedWorkingDirectory, isDirectory: &isDir)
            && isDir.boolValue
        var currentPath: String
        if dirExists {
            currentPath = normalizedWorkingDirectory
        } else {
            let parentPath = (normalizedWorkingDirectory as NSString).deletingLastPathComponent
            currentPath = parentPath.isEmpty ? normalizedWorkingDirectory : parentPath
        }

        while true {
            if Task.isCancelled {
                return nil
            }

            let gitPath = (currentPath as NSString).appendingPathComponent(".git")
            if fileManager.fileExists(atPath: gitPath) {
                return currentPath
            }

            let parentPath = (currentPath as NSString).deletingLastPathComponent
            if parentPath.isEmpty || parentPath == currentPath {
                return nil
            }
            currentPath = parentPath
        }
    }

    nonisolated private static func isWorkflowTrustedRepositoryRoot(
        _ repositoryRoot: String,
        workflowTrustFilePath: String?,
        fileManager: FileManager
    ) -> Bool {
        let trustFilePath = workflowTrustFilePath ?? repositoryWorkflowTrustFilePath()
        guard fileManager.fileExists(atPath: trustFilePath) else {
            return false
        }
        guard let contents = try? String(contentsOfFile: trustFilePath, encoding: .utf8) else {
            return false
        }

        return contents
            .split(whereSeparator: \.isNewline)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .contains(repositoryRoot)
    }

}
