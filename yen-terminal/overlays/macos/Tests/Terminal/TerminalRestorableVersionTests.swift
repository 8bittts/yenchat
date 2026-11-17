import AppKit
import Foundation
import Testing
@testable import YEN

private struct DummyTerminalRestorableState: TerminalRestorable, Equatable {
    static var version: Int { TerminalRestorableState.version }

    let value: Int

    init(value: Int) {
        self.value = value
    }

    init(copy other: DummyTerminalRestorableState) {
        self.value = other.value
    }
}

@MainActor
@Suite(.serialized)
struct TerminalRestorableVersionTests {
    // Live terminal controllers spawn login shells. Retain them for the
    // serialized suite instead of tearing windows down per test, which can
    // restart the Swift Testing host mid-run.
    private static var retainedControllers: [TerminalController] = []

    private var priorSupportedVersion: Int {
        max(1, DummyTerminalRestorableState.version - 1)
    }

    @Test func supportsCurrentAndOlderVersions() {
        #expect(DummyTerminalRestorableState.supportsCodedVersion(DummyTerminalRestorableState.version))
        #expect(DummyTerminalRestorableState.supportsCodedVersion(priorSupportedVersion))
        #expect(DummyTerminalRestorableState.supportsCodedVersion(1))
    }

    @Test func rejectsZeroAndFutureVersions() {
        #expect(!DummyTerminalRestorableState.supportsCodedVersion(0))
        #expect(!DummyTerminalRestorableState.supportsCodedVersion(DummyTerminalRestorableState.version + 1))
    }

    @Test func coderInitDecodesOlderVersionPayload() {
        let payload = DummyTerminalRestorableState(value: 42)
        let decoded = decode(payload, codedVersion: priorSupportedVersion)

        #expect(decoded == payload)
    }

    @Test func coderInitRejectsFutureVersionPayload() {
        let payload = DummyTerminalRestorableState(value: 99)
        let decoded = decode(payload, codedVersion: DummyTerminalRestorableState.version + 1)

        #expect(decoded == nil)
    }

    @Test func terminalRestorableStateVersionGateAcceptsCurrentAndPriorVersions() {
        #expect(TerminalRestorableState.supportsCodedVersion(TerminalRestorableState.version))
        #expect(TerminalRestorableState.supportsCodedVersion(max(1, TerminalRestorableState.version - 1)))
    }

    @Test func terminalRestorableStateVersionGateRejectsFutureVersion() {
        #expect(!TerminalRestorableState.supportsCodedVersion(TerminalRestorableState.version + 1))
    }

    @Test func quickTerminalRestorableStateVersionGateAcceptsCurrentAndPriorVersions() {
        #expect(QuickTerminalRestorableState.supportsCodedVersion(QuickTerminalRestorableState.version))
        #expect(QuickTerminalRestorableState.supportsCodedVersion(max(1, QuickTerminalRestorableState.version - 1)))
    }

    @Test func quickTerminalRestorableStateVersionGateRejectsFutureVersion() {
        #expect(!QuickTerminalRestorableState.supportsCodedVersion(QuickTerminalRestorableState.version + 1))
    }

    @Test func quickTerminalRestorableStateDecodesOlderPayloadAndKeepsEnvironmentMarker() {
        let payload = QuickTerminalRestorableState(
            focusedSurface: nil,
            surfaceTree: .init(),
            screenStateEntries: [:],
            splitPaneLabels: ["pane": "Scratch"]
        )
        let decoded = decode(payload, codedVersion: max(1, QuickTerminalRestorableState.version - 1))

        #expect(decoded?.splitPaneLabels?["pane"] == "Scratch")
        #expect(decoded?.baseConfig?.environmentVariables["YEN_QUICK_TERMINAL"] == "1")
    }

    @Test func quickTerminalRestorableStateDropsPreNativeGeometryCacheOnce() {
        let displayID = UUID()
        let legacyEntry = QuickTerminalScreenStateCache.DisplayEntry(
            frame: NSRect(x: 0, y: 800, width: 900, height: 400),
            screenSize: CGSize(width: 1800, height: 1200),
            scale: 2,
            lastSeen: Date()
        )
        let legacy = QuickTerminalRestorableState(
            focusedSurface: nil,
            surfaceTree: .init(),
            screenStateEntries: [displayID: legacyEntry],
            geometrySourceVersion: nil
        )

        let migrated = QuickTerminalRestorableState(copy: legacy)

        #expect(migrated.screenStateEntries.isEmpty)
        #expect(migrated.geometrySourceVersion == 1)
    }

    @Test func quickTerminalRestorableStateKeepsNativeGeometryCache() {
        let displayID = UUID()
        let nativeEntry = QuickTerminalScreenStateCache.DisplayEntry(
            frame: NSRect(x: 0, y: 800, width: 1800, height: 400),
            screenSize: CGSize(width: 1800, height: 1200),
            scale: 2,
            lastSeen: Date()
        )
        let native = QuickTerminalRestorableState(
            focusedSurface: nil,
            surfaceTree: .init(),
            screenStateEntries: [displayID: nativeEntry]
        )

        let restored = QuickTerminalRestorableState(copy: native)

        #expect(restored.screenStateEntries[displayID]?.frame == nativeEntry.frame)
    }

    @Test func terminalRestorableStateCapturesSplitPaneLabels() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            Issue.record("Expected AppDelegate-backed test host.")
            return
        }

        let controller = TerminalController(appDelegate.yen)
        Self.retainedControllers.append(controller)

        guard let surface = controller.surfaceTree.first else {
            Issue.record("Expected initial terminal surface.")
            return
        }

        surface.setSplitPaneLabel("Scratch")

        let payload = TerminalRestorableState(from: controller)
        let decoded = decode(payload, codedVersion: TerminalRestorableState.version)

        #expect(decoded?.splitPaneLabels?[surface.id.uuidString] == "Scratch")
    }

    @Test func terminalRestorableStateCapturesTitleOverride() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
            Issue.record("Expected AppDelegate-backed test host.")
            return
        }

        let controller = TerminalController(appDelegate.yen)
        Self.retainedControllers.append(controller)

        controller.titleOverride = "Build Logs"

        let payload = TerminalRestorableState(from: controller)
        let decoded = decode(payload, codedVersion: TerminalRestorableState.version)

        #expect(decoded?.titleOverride == "Build Logs")
    }

    private func decode<Restorable: TerminalRestorable>(
        _ payload: Restorable,
        codedVersion: Int
    ) -> Restorable? {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(codedVersion, forKey: Restorable.versionKey)
        archiver.encode(CodableBridge(payload), forKey: Restorable.selfKey)
        archiver.finishEncoding()

        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archiver.encodedData) else {
            return nil
        }
        defer { unarchiver.finishDecoding() }
        unarchiver.requiresSecureCoding = true
        return Restorable(coder: unarchiver)
    }
}
