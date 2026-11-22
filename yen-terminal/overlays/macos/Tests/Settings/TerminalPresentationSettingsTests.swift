import Combine
import Foundation
import Testing
@testable import YEN

@Suite(.serialized)
@MainActor
struct TerminalPresentationSettingsTests {
    @Test func runtimeConfigIsWrittenAndParsedOnceAcrossWindows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yen-runtime-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("runtime.yen")
        let cache = TerminalBackgroundRuntimeConfigCache()
        let generation = YEN.Config(config: nil)
        let snapshot = TerminalPresentationSettings.Snapshot.capture(from: .shared)
        var loads = 0
        func loadForWindow() throws -> YEN.Config {
            try cache.resolve(sourceConfig: generation, snapshot: snapshot, runtimePath: path.path,
                useWholeWindowOverride: true) {
                loads += 1
                try "background-opacity = 0.0\n".write(to: path, atomically: true, encoding: .utf8)
                return YEN.Config(at: path.path)
            }
        }
        let first = try loadForWindow()
        let second = try loadForWindow()
        #expect(first.loaded)
        #expect(first === second)
        #expect(loads == 1)
    }

    @Test func runtimeCacheInvalidatesGenerationSettingsPathAndMode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yen-runtime-keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = TerminalBackgroundRuntimeConfigCache()
        let firstGeneration = YEN.Config(config: nil)
        let secondGeneration = YEN.Config(config: nil)
        let baseline = TerminalPresentationSettings.Snapshot.capture(from: .shared)
        let changed = TerminalPresentationSettings.Snapshot(
            backgroundImagePath: baseline.backgroundImagePath, backgroundImageScope: baseline.backgroundImageScope,
            backgroundOpacity: baseline.backgroundOpacity == 0.5 ? 0.7 : 0.5,
            wholeWindowBackgroundImageEnabled: baseline.wholeWindowBackgroundImageEnabled,
            windowBorderEnabled: baseline.windowBorderEnabled, windowBorderScope: baseline.windowBorderScope,
            windowBorderWidth: baseline.windowBorderWidth, windowBorderRadius: baseline.windowBorderRadius,
            windowBorderFocusedGradient: baseline.windowBorderFocusedGradient,
            windowBorderUnfocusedGradient: baseline.windowBorderUnfocusedGradient)
        var loads = 0
        func resolve(_ generation: YEN.Config, _ snapshot: TerminalPresentationSettings.Snapshot,
                     _ name: String, _ whole: Bool) throws -> YEN.Config {
            let path = root.appendingPathComponent(name)
            return try cache.resolve(sourceConfig: generation, snapshot: snapshot, runtimePath: path.path,
                useWholeWindowOverride: whole) {
                loads += 1
                try "background-opacity = \(whole ? 0 : snapshot.backgroundOpacity)\n"
                    .write(to: path, atomically: true, encoding: .utf8)
                return YEN.Config(at: path.path)
            }
        }
        let first = try resolve(firstGeneration, baseline, "a.yen", true)
        #expect(first === (try resolve(firstGeneration, baseline, "a.yen", true)))
        #expect(loads == 1)
        _ = try resolve(secondGeneration, baseline, "a.yen", true)
        #expect(loads == 2)
        _ = try resolve(secondGeneration, changed, "a.yen", true)
        #expect(loads == 3)
        _ = try resolve(secondGeneration, changed, "b.yen", true)
        #expect(loads == 4)
        let restored = try resolve(secondGeneration, changed, "b.yen", false)
        #expect(restored.loaded)
        #expect(loads == 5)
        // The restoring window removes the transient file after applying it.
        try FileManager.default.removeItem(at: root.appendingPathComponent("b.yen"))
        #expect(restored === (try resolve(secondGeneration, changed, "b.yen", false)))
        #expect(loads == 5)
    }

    @Test func runtimeCacheRetriesFailedLoadsAndReleasesOldGenerations() throws {
        enum Failure: Error { case write }
        let cache = TerminalBackgroundRuntimeConfigCache()
        let snapshot = TerminalPresentationSettings.Snapshot.capture(from: .shared)
        var generation: YEN.Config? = YEN.Config(config: nil)
        weak let previousGeneration = generation
        var loads = 0
        for _ in 0..<2 {
            let failed = cache.resolve(sourceConfig: generation!, snapshot: snapshot, runtimePath: "/fixture",
                useWholeWindowOverride: true) {
                loads += 1
                return YEN.Config(config: nil)
            }
            #expect(!failed.loaded)
        }
        #expect(loads == 2)
        #expect(throws: Failure.self) {
            try cache.resolve(sourceConfig: generation!, snapshot: snapshot, runtimePath: "/fixture",
                useWholeWindowOverride: true) { throw Failure.write }
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("yen-runtime-retry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: path) }
        try "background-opacity = 0.0\n".write(to: path, atomically: true, encoding: .utf8)
        let loaded = cache.resolve(sourceConfig: generation!, snapshot: snapshot, runtimePath: "/fixture",
            useWholeWindowOverride: true) {
            loads += 1
            return YEN.Config(at: path.path)
        }
        #expect(loaded.loaded)
        #expect(loads == 3)
        generation = nil
        #expect(previousGeneration != nil)
        _ = cache.resolve(sourceConfig: YEN.Config(config: nil), snapshot: snapshot, runtimePath: "/fixture",
            useWholeWindowOverride: true) { loaded }
        #expect(previousGeneration == nil)
    }

    @Test func ignoresIrrelevantSettingsChanges() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        let observer = TerminalPresentationSettings(settingsController: controller)
        let baseline = observer.snapshot
        var emissionCount = 0
        let cancellable = observer.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        controller.selectedSettingsPane = .shortcuts
        drainMainRunLoop()

        #expect(observer.snapshot == baseline)
        #expect(emissionCount == 0)
    }

    @Test func republishesWhenTerminalSettingsChange() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.windowBorderEnabled = false
        let observer = TerminalPresentationSettings(settingsController: controller)
        let baseline = observer.snapshot
        var emissionCount = 0
        let cancellable = observer.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        controller.windowBorderEnabled = true
        drainMainRunLoop()

        #expect(observer.snapshot.windowBorderEnabled != baseline.windowBorderEnabled)
        #expect(emissionCount == 1)
    }

    @Test func republishesWhenDerivedBorderGradientChanges() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.windowBorderColorMode = .manual
        controller.windowBorderFocusedPalette = .sunrise
        let observer = TerminalPresentationSettings(settingsController: controller)
        let baseline = observer.snapshot
        var emissionCount = 0
        let cancellable = observer.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        controller.windowBorderFocusedPalette = .ocean
        drainMainRunLoop()

        #expect(observer.snapshot.windowBorderFocusedGradient != baseline.windowBorderFocusedGradient)
        #expect(emissionCount == 1)
    }

    @Test func republishesWhenABorderEffectChanges() {
        let controller = SettingsController.shared
        reset(controller)
        let originalEffects = controller.windowBorderEffects
        defer {
            controller.windowBorderSparkEnabled = originalEffects.sparkEnabled
            controller.windowBorderAuraEnabled = originalEffects.auraEnabled
            controller.windowBorderAuraColorHex = originalEffects.auraColorHex
            reset(controller)
        }

        controller.windowBorderSparkEnabled = false
        controller.windowBorderAuraEnabled = false
        controller.windowBorderAuraColorHex = "#FF5100"
        let observer = TerminalPresentationSettings(settingsController: controller)
        var emissionCount = 0
        let cancellable = observer.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        controller.windowBorderSparkEnabled = true
        controller.windowBorderAuraEnabled = true
        controller.windowBorderAuraColorHex = "#22C55E"
        drainMainRunLoop()

        #expect(observer.snapshot.windowBorderEffects == WindowBorderEffects(
            sparkEnabled: true,
            auraEnabled: true,
            auraColorHex: "#22C55E"
        ))
        #expect(emissionCount >= 1)
    }

    @Test func splitPaneLabelObserverIgnoresIrrelevantSettingsChanges() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        let observer = SplitPaneLabelSettings(settingsController: controller)
        let baseline = observer.isEnabled
        var emissionCount = 0
        let cancellable = observer.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        controller.selectedSettingsPane = .shortcuts
        drainMainRunLoop()

        #expect(observer.isEnabled == baseline)
        #expect(emissionCount == 0)
    }

    @Test func splitPaneLabelObserverRepublishesOnWorkspaceSettingChanges() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.splitPaneLabelsEnabled = false
        let observer = SplitPaneLabelSettings(settingsController: controller)
        let baseline = observer.isEnabled
        var emissionCount = 0
        let cancellable = observer.objectWillChange.sink {
            emissionCount += 1
        }
        defer { cancellable.cancel() }

        controller.splitPaneLabelsEnabled = true
        drainMainRunLoop()

        #expect(observer.isEnabled != baseline)
        #expect(emissionCount == 1)
    }

    @Test func worktreeNamingStaysOffWhileSplitLabelsAreOff() {
        let controller = SettingsController.shared
        reset(controller)
        defer { reset(controller) }

        controller.splitPaneLabelsEnabled = false
        controller.splitPaneWorktreeNamingEnabled = true
        let observer = SplitPaneLabelSettings(settingsController: controller)

        // The stored preference is on, but the parent toggle gates it.
        #expect(controller.splitPaneWorktreeNamingEnabled)
        #expect(observer.isWorktreeNamingEnabled == false)

        controller.splitPaneLabelsEnabled = true
        drainMainRunLoop()

        #expect(observer.isWorktreeNamingEnabled)
    }

    private func reset(_ controller: SettingsController) {
        SettingsController._testSetWindowCloseMemoryModeOverride(nil)
        controller.splitPaneLabelsEnabled = SplitPaneLabelsPreferences.defaultEnabled
        controller.splitPaneWorktreeNamingEnabled = SplitPaneLabelsPreferences.defaultWorktreeNamingEnabled
        controller.hide()
        drainMainRunLoop()
        controller._testResetWindowState()
        controller.selectedSettingsPane = .general
        controller.resetKeybindReloadStateForTesting()
    }

    private func drainMainRunLoop(for duration: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
}
