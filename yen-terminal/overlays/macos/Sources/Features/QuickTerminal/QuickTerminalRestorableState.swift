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
    /// Remote panes by UUID; restore reattaches each to its session.
    let remotePanes: RemotePanes.SavedIdentities?

    private enum CodingKeys: String, CodingKey {
        case focusedSurface, surfaceTree, screenStateEntries, splitPaneLabels, geometrySourceVersion, remotePanes
    }

    init(
        focusedSurface: String?,
        surfaceTree: SplitTree<YEN.SurfaceView>,
        screenStateEntries: QuickTerminalScreenStateCache.Entries,
        splitPaneLabels: [String: String]? = nil,
        geometrySourceVersion: Int? = nativeGeometrySourceVersion,
        remotePanes: RemotePanes.SavedIdentities? = nil
    ) {
        self.focusedSurface = focusedSurface
        self.surfaceTree = surfaceTree
        self.screenStateEntries = screenStateEntries
        self.splitPaneLabels = splitPaneLabels
        self.geometrySourceVersion = geometrySourceVersion
        self.remotePanes = remotePanes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        focusedSurface = try container.decodeIfPresent(String.self, forKey: .focusedSurface)
        // Read before the tree: decoding the tree creates each pane's surface,
        // and a remote pane must get its attach command at creation.
        let remotePanes = try? container.decodeIfPresent(RemotePanes.SavedIdentities.self, forKey: .remotePanes)
        self.remotePanes = remotePanes
        surfaceTree = try RemotePanes.decodingTree(restoring: remotePanes?.entries) {
            try container.decode(SplitTree<YEN.SurfaceView>.self, forKey: .surfaceTree)
        }
        screenStateEntries = try container.decode(QuickTerminalScreenStateCache.Entries.self, forKey: .screenStateEntries)
        splitPaneLabels = try container.decodeIfPresent([String: String].self, forKey: .splitPaneLabels)
        geometrySourceVersion = try container.decodeIfPresent(Int.self, forKey: .geometrySourceVersion)
    }

    init(from controller: QuickTerminalController) {
        controller.saveScreenState(exitFullscreen: true)
        let labels = SplitPaneLabelPersistence.snapshot(for: controller.surfaceTree)
        self.init(
            focusedSurface: controller.focusedSurface?.id.uuidString,
            surfaceTree: controller.surfaceTree,
            screenStateEntries: controller.screenStateCache.stateByDisplay,
            splitPaneLabels: labels.isEmpty ? nil : labels,
            remotePanes: RemotePanes.snapshot(for: controller.surfaceTree).map(RemotePanes.SavedIdentities.init)
        )
    }

    init(copy other: QuickTerminalRestorableState) {
        self.init(
            focusedSurface: other.focusedSurface,
            surfaceTree: other.surfaceTree,
            screenStateEntries: other.geometrySourceVersion == Self.nativeGeometrySourceVersion
                ? other.screenStateEntries
                : [:],
            splitPaneLabels: other.splitPaneLabels,
            remotePanes: other.remotePanes
        )
        SplitPaneLabelPersistence.restore(other.splitPaneLabels ?? [:], to: surfaceTree)
    }

    var baseConfig: YEN.SurfaceConfiguration? {
        var config = YEN.SurfaceConfiguration()
        config.environmentVariables["YEN_QUICK_TERMINAL"] = "1"
        return config
    }
}
