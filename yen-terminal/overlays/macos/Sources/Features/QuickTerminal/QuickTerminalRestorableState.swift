import Cocoa

struct QuickTerminalRestorableState: TerminalRestorable {
    static var version: Int { 3 }

    /// Version 1 marks frames captured by the vendor-native screen-scoped
    /// geometry path. Older YEN builds could persist a window-scoped width here;
    /// discard that cache once so it cannot keep the restored panel narrow.
    private static let nativeGeometrySourceVersion = 1

    let focusedSurface: String?
    let surfaceTree: SplitTree<YEN.SurfaceView>
    let screenStateEntries: QuickTerminalScreenStateCache.Entries
    let splitPaneLabels: [String: String]?
    let geometrySourceVersion: Int?

    init(
        focusedSurface: String?,
        surfaceTree: SplitTree<YEN.SurfaceView>,
        screenStateEntries: QuickTerminalScreenStateCache.Entries,
        splitPaneLabels: [String: String]? = nil,
        geometrySourceVersion: Int? = nativeGeometrySourceVersion
    ) {
        self.focusedSurface = focusedSurface
        self.surfaceTree = surfaceTree
        self.screenStateEntries = screenStateEntries
        self.splitPaneLabels = splitPaneLabels
        self.geometrySourceVersion = geometrySourceVersion
    }

    init(from controller: QuickTerminalController) {
        controller.saveScreenState(exitFullscreen: true)
        let labels = SplitPaneLabelPersistence.snapshot(for: controller.surfaceTree)
        self.init(
            focusedSurface: controller.focusedSurface?.id.uuidString,
            surfaceTree: controller.surfaceTree,
            screenStateEntries: controller.screenStateCache.stateByDisplay,
            splitPaneLabels: labels.isEmpty ? nil : labels
        )
    }

    init(copy other: QuickTerminalRestorableState) {
        self.init(
            focusedSurface: other.focusedSurface,
            surfaceTree: other.surfaceTree,
            screenStateEntries: other.geometrySourceVersion == Self.nativeGeometrySourceVersion
                ? other.screenStateEntries
                : [:],
            splitPaneLabels: other.splitPaneLabels
        )
        SplitPaneLabelPersistence.restore(other.splitPaneLabels ?? [:], to: surfaceTree)
    }

    var baseConfig: YEN.SurfaceConfiguration? {
        var config = YEN.SurfaceConfiguration()
        config.environmentVariables["YEN_QUICK_TERMINAL"] = "1"
        return config
    }
}
