import AppKit
import Foundation
import Testing
@testable import YEN

@MainActor
@Suite(.serialized)
struct SettingsBackgroundImageControlsTests {
    @Test func replacingBackgroundImageRemovesPreviousManagedFileAfterSuccessfulPersist() throws {
        try withIsolatedBackgroundImageControlsContext { controller, _, configURL, appSupportRoot in
            let sourceOne = try makeTestImage(named: "background-one.png", in: appSupportRoot.deletingLastPathComponent())
            let sourceTwo = try makeTestImage(named: "background-two.png", in: appSupportRoot.deletingLastPathComponent())

            #expect(
                controller._testImportBackgroundImage(
                    from: sourceOne,
                    appSupportRootOverride: appSupportRoot
                )
            )
            let firstManagedPath = controller.backgroundImagePath

            #expect(
                controller._testImportBackgroundImage(
                    from: sourceTwo,
                    appSupportRootOverride: appSupportRoot
                )
            )
            let secondManagedPath = controller.backgroundImagePath
            let configContents = try String(contentsOf: configURL, encoding: .utf8)

            #expect(firstManagedPath != secondManagedPath)
            #expect(!firstManagedPath.isEmpty)
            #expect(FileManager.default.fileExists(atPath: secondManagedPath))
            #expect(!FileManager.default.fileExists(atPath: firstManagedPath))
            #expect(configContents.contains(TerminalBackgroundImageStore.quotedConfigPath(secondManagedPath)))
            #expect(!configContents.contains(TerminalBackgroundImageStore.quotedConfigPath(firstManagedPath)))
            #expect(controller.backgroundImagePreview != nil)
            #expect(controller.backgroundImageIssueDescription.isEmpty)
        }
    }

    @Test func failedReplaceFromManagedSourceRollsBackSelectionAndCleansOrphanedManagedFile() throws {
        try withIsolatedBackgroundImageControlsContext { controller, tempRoot, configURL, appSupportRoot in
            let sourceOne = try makeTestImage(named: "background-one.png", in: tempRoot)
            let sourceTwo = try makeTestImage(named: "background-two.png", in: tempRoot)

            #expect(
                controller._testImportBackgroundImage(
                    from: sourceOne,
                    appSupportRootOverride: appSupportRoot
                )
            )
            let originalManagedPath = controller.backgroundImagePath
            let orphanManagedURL = try TerminalBackgroundImageStore.importImage(
                from: sourceTwo,
                appSupportRootOverride: appSupportRoot
            )

            SettingsController._testSetConfigPathOverride(tempRoot.path)
            controller._testResetStatusState()
            let importSucceeded = controller._testImportBackgroundImage(
                from: orphanManagedURL,
                appSupportRootOverride: appSupportRoot
            )
            SettingsController._testSetConfigPathOverride(configURL.path)

            let configContents = try String(contentsOf: configURL, encoding: .utf8)
            let managedPaths = try managedBackgroundFilePaths(appSupportRoot: appSupportRoot)
            let normalizedOriginalManagedPath = URL(
                fileURLWithPath: originalManagedPath
            ).resolvingSymlinksInPath().path

            #expect(!importSucceeded)
            #expect(controller.backgroundImagePath == originalManagedPath)
            #expect(FileManager.default.fileExists(atPath: originalManagedPath))
            #expect(!FileManager.default.fileExists(atPath: orphanManagedURL.path))
            #expect(managedPaths == [normalizedOriginalManagedPath])
            #expect(controller.backgroundImagePreview != nil)
            #expect(controller.backgroundImageIssueDescription.isEmpty)
            #expect(controller.statusMessage.hasPrefix("Import failed:"))
            #expect(controller.statusSeverity == .error)
            #expect(configContents.contains(TerminalBackgroundImageStore.quotedConfigPath(originalManagedPath)))
            #expect(!configContents.contains(TerminalBackgroundImageStore.quotedConfigPath(orphanManagedURL.path)))
        }
    }

    @Test func removingBackgroundImageDeletesManagedFileAfterSuccessfulPersist() throws {
        try withIsolatedBackgroundImageControlsContext { controller, tempRoot, configURL, appSupportRoot in
            let source = try makeTestImage(named: "background-remove.png", in: tempRoot)

            #expect(
                controller._testImportBackgroundImage(
                    from: source,
                    appSupportRootOverride: appSupportRoot
                )
            )
            let managedPath = controller.backgroundImagePath

            #expect(controller._testRemoveBackgroundImage(appSupportRootOverride: appSupportRoot))

            let configContents = try String(contentsOf: configURL, encoding: .utf8)

            #expect(controller.backgroundImagePath.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: managedPath))
            #expect(controller.backgroundImagePreview == nil)
            #expect(controller.backgroundImageIssueDescription.isEmpty)
            #expect(!configContents.contains("background-image ="))
            #expect(!configContents.contains("background-image-fit ="))
            #expect(!configContents.contains("background-image-opacity ="))
            #expect(!configContents.contains("background-image-position ="))
            #expect(!configContents.contains("background-image-repeat ="))
            #expect(controller.statusMessage == "Removed background image")
            #expect(controller.statusSeverity == .success)
        }
    }

    @Test func failedRemoveRestoresManagedBackgroundAndPreviewState() throws {
        try withIsolatedBackgroundImageControlsContext { controller, tempRoot, configURL, appSupportRoot in
            let source = try makeTestImage(named: "background-remove-failure.png", in: tempRoot)

            #expect(
                controller._testImportBackgroundImage(
                    from: source,
                    appSupportRootOverride: appSupportRoot
                )
            )
            let managedPath = controller.backgroundImagePath

            SettingsController._testSetConfigPathOverride(tempRoot.path)
            controller._testResetStatusState()
            let removalSucceeded = controller._testRemoveBackgroundImage(
                appSupportRootOverride: appSupportRoot
            )
            SettingsController._testSetConfigPathOverride(configURL.path)

            let configContents = try String(contentsOf: configURL, encoding: .utf8)

            #expect(!removalSucceeded)
            #expect(controller.backgroundImagePath == managedPath)
            #expect(FileManager.default.fileExists(atPath: managedPath))
            #expect(controller.backgroundImagePreview != nil)
            #expect(controller.backgroundImageIssueDescription.isEmpty)
            #expect(controller.statusMessage.hasPrefix("Remove failed:"))
            #expect(controller.statusSeverity == .error)
            #expect(configContents.contains(TerminalBackgroundImageStore.quotedConfigPath(managedPath)))
        }
    }

    private func withIsolatedBackgroundImageControlsContext(
        _ operation: (SettingsController, URL, URL, URL) throws -> Void
    ) throws {
        try TestExclusiveLock.withLock(named: "settings-background-image-controls") {
            let controller = SettingsController.shared
            let baselineState = controller.captureSettingsStateForTesting()
            let originalBackgroundImagePath = controller.backgroundImagePath
            let originalBackgroundImageScope = controller.backgroundImageScope
            let originalStatusMessage = controller.statusMessage
            let originalStatusSeverity = controller.statusSeverity
            let tempRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "yen-settings-background-image-\(UUID().uuidString)",
                    isDirectory: true
                )
            let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)
            let appSupportRoot = tempRoot.appendingPathComponent("app-support", isDirectory: true)

            try FileManager.default.createDirectory(
                at: tempRoot,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try "font-size = 14\n".write(to: configURL, atomically: true, encoding: .utf8)

            SettingsController._testSetConfigPathOverride(configURL.path)
            controller.hide()
            controller._testResetWindowState()
            controller._testResetStatusState()
            controller.applyConfigContentsForTesting("font-size = 14\n")

            defer {
                SettingsController._testSetConfigPathOverride(configURL.path)
                controller.hide()
                controller._testResetWindowState()
                // Restores into the temporary config, never the real one.
                controller.restoreSettingsStateForTesting(baselineState)
                controller.backgroundImagePath = originalBackgroundImagePath
                controller.backgroundImageScope = originalBackgroundImageScope
                controller._testResetStatusState()
                controller.statusMessage = originalStatusMessage
                controller.statusSeverity = originalStatusSeverity
                SettingsController._testSetConfigPathOverride(nil)
                try? FileManager.default.removeItem(at: tempRoot)
            }

            try operation(controller, tempRoot, configURL, appSupportRoot)
        }
    }

    private func makeTestImage(named name: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: false)
        let image = NSImage(size: NSSize(width: 12, height: 12))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 12, height: 12)).fill()
        image.unlockFocus()

        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        let imageData = try #require(bitmap.representation(using: .png, properties: [:]))
        try imageData.write(to: url, options: .atomic)
        return url
    }

    private func managedBackgroundFilePaths(appSupportRoot: URL) throws -> Set<String> {
        let directoryURL = TerminalBackgroundImageStore.backgroundsDirectoryURL(
            appSupportRootOverride: appSupportRoot
        )
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }

        return Set(
            try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).map { $0.resolvingSymlinksInPath().path }
        )
    }
}
