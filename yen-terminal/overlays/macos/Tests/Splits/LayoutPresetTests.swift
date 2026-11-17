import AppKit
import Testing
import YENKit
@testable import YEN

@MainActor
struct LayoutPresetTests {
    @Test func layoutTemplateOrderIsStable() {
        #expect(LayoutTemplate.allCases.map(\.rawValue) == [
            "singlePane",
            "threeColumns",
            "rightStack",
            "bottomStack",
            "quad",
            "eastward13",
            "eastward21",
            "eastward23",
            "centerStage",
            "threeColumnBottom",
        ])
    }

    @Test func layoutTemplateSurfaceCountsAreStable() {
        #expect(LayoutTemplate.singlePane.newSurfaceCount == 0)
        #expect(LayoutTemplate.threeColumns.newSurfaceCount == 2)
        #expect(LayoutTemplate.rightStack.newSurfaceCount == 2)
        #expect(LayoutTemplate.bottomStack.newSurfaceCount == 2)
        #expect(LayoutTemplate.quad.newSurfaceCount == 3)
        #expect(LayoutTemplate.eastward13.newSurfaceCount == 3)
        #expect(LayoutTemplate.eastward21.newSurfaceCount == 2)
        #expect(LayoutTemplate.eastward23.newSurfaceCount == 4)
        #expect(LayoutTemplate.centerStage.newSurfaceCount == 3)
        #expect(LayoutTemplate.threeColumnBottom.newSurfaceCount == 3)
    }

    @Test func layoutTemplateSpecsAreStable() {
        #expect(LayoutTemplate.singlePane.nodeSpecSignature == nil)
        #expect(LayoutTemplate.threeColumns.nodeSpecSignature == "H0.3333(F,H0.5000(N0,N1))")
        #expect(LayoutTemplate.rightStack.nodeSpecSignature == "H0.5000(F,V0.5000(N0,N1))")
        #expect(LayoutTemplate.bottomStack.nodeSpecSignature == "V0.5000(F,H0.5000(N0,N1))")
        #expect(LayoutTemplate.quad.nodeSpecSignature == "H0.5000(V0.5000(F,N1),V0.5000(N0,N2))")
        #expect(LayoutTemplate.eastward13.nodeSpecSignature == "H0.5000(F,V0.3333(N0,V0.5000(N1,N2)))")
        #expect(LayoutTemplate.eastward21.nodeSpecSignature == "H0.5000(V0.5000(F,N0),N1)")
        #expect(LayoutTemplate.eastward23.nodeSpecSignature == "H0.5000(V0.5000(F,N0),V0.3333(N1,V0.5000(N2,N3)))")
        #expect(LayoutTemplate.centerStage.nodeSpecSignature == "H0.3333(F,H0.5000(V0.5000(N0,N1),N2))")
        #expect(LayoutTemplate.threeColumnBottom.nodeSpecSignature == "V0.5000(F,H0.3333(N0,H0.5000(N1,N2)))")
    }

    @Test(arguments: [
        (UInt16(18), 0),
        (UInt16(19), 1),
        (UInt16(20), 2),
        (UInt16(21), 3),
        (UInt16(23), 4),
        (UInt16(22), 5),
        (UInt16(26), 6),
        (UInt16(28), 7),
        (UInt16(25), 8),
        (UInt16(29), 9),
    ])
    func layoutShortcutMapsPhysicalDigitKeyCodes(_ keyCode: UInt16, _ expectedIndex: Int) {
        #expect(LayoutShortcutController.layoutIndex(forKeyCode: keyCode) == expectedIndex)
    }

    @Test func layoutShortcutMappingUsesSharedPhysicalDigitRowSource() {
        let expectedPairs: [(keyCode: UInt16, index: Int)] = [
            (18, 0),
            (19, 1),
            (20, 2),
            (21, 3),
            (23, 4),
            (22, 5),
            (26, 6),
            (28, 7),
            (25, 8),
            (29, 9),
        ]

        for pair in expectedPairs {
            #expect(PhysicalDigitRowKeyCodes.layoutIndex(forKeyCode: pair.keyCode) == pair.index)
            #expect(PhysicalDigitRowKeyCodes.keyCode(forLayoutIndex: pair.index) == pair.keyCode)
            #expect(LayoutShortcutController.layoutIndex(forKeyCode: pair.keyCode) == pair.index)
        }

        #expect(PhysicalDigitRowKeyCodes.keyCode(forDisplayDigit: 1) == 18)
        #expect(PhysicalDigitRowKeyCodes.keyCode(forDisplayDigit: 5) == 23)
        #expect(PhysicalDigitRowKeyCodes.keyCode(forDisplayDigit: 0) == 29)
        #expect(PhysicalDigitRowKeyCodes.keyCode(forDisplayDigit: 10) == nil)
    }

    @Test(arguments: [UInt16(17), UInt16(24), UInt16(27), UInt16(30)])
    func layoutShortcutIgnoresUnsupportedKeyCodes(_ keyCode: UInt16) {
        #expect(LayoutShortcutController.layoutIndex(forKeyCode: keyCode) == nil)
    }

    @Test func layoutShortcutsOnlyRouteToForegroundTerminalWindows() {
        #expect(
            !LayoutShortcutController.shouldRouteLayoutActionToTerminal(
                hasKeyWindow: true,
                keyWindowIsTerminal: false,
                mainWindowIsTerminal: true,
                hasModalWindow: false,
                keyWindowHasAttachedSheet: false,
                mainWindowHasAttachedSheet: false
            )
        )
        #expect(
            LayoutShortcutController.shouldRouteLayoutActionToTerminal(
                hasKeyWindow: true,
                keyWindowIsTerminal: true,
                mainWindowIsTerminal: true,
                hasModalWindow: false,
                keyWindowHasAttachedSheet: false,
                mainWindowHasAttachedSheet: false
            )
        )
        #expect(
            LayoutShortcutController.shouldRouteShortcutToTerminal(
                hasKeyWindow: true,
                keyWindowIsTerminal: false,
                mainWindowIsTerminal: true,
                hasModalWindow: false,
                keyWindowHasAttachedSheet: false,
                mainWindowHasAttachedSheet: false,
                keyWindowOwnsFocusedTerminalResponder: false
            ) == false
        )
        #expect(
            LayoutShortcutController.shouldRouteShortcutToTerminal(
                hasKeyWindow: true,
                keyWindowIsTerminal: true,
                mainWindowIsTerminal: true,
                hasModalWindow: false,
                keyWindowHasAttachedSheet: false,
                mainWindowHasAttachedSheet: false,
                keyWindowOwnsFocusedTerminalResponder: true
            ) == true
        )
        #expect(
            LayoutShortcutController.shouldRouteShortcutToTerminal(
                hasKeyWindow: false,
                keyWindowIsTerminal: false,
                mainWindowIsTerminal: true,
                hasModalWindow: false,
                keyWindowHasAttachedSheet: false,
                mainWindowHasAttachedSheet: false,
                keyWindowOwnsFocusedTerminalResponder: false
            ) == true
        )
    }

    @Test func layoutMenuActionsFailClosedForModalOrSheetState() {
        #expect(
            !LayoutShortcutController.shouldRouteLayoutActionToTerminal(
                hasKeyWindow: true,
                keyWindowIsTerminal: true,
                mainWindowIsTerminal: true,
                hasModalWindow: true,
                keyWindowHasAttachedSheet: false,
                mainWindowHasAttachedSheet: false
            )
        )
        #expect(
            !LayoutShortcutController.shouldRouteLayoutActionToTerminal(
                hasKeyWindow: true,
                keyWindowIsTerminal: true,
                mainWindowIsTerminal: true,
                hasModalWindow: false,
                keyWindowHasAttachedSheet: true,
                mainWindowHasAttachedSheet: false
            )
        )
    }

    @Test func layoutShortcutsFailClosedForModalSheetOrResponderMismatch() {
        #expect(
            !LayoutShortcutController.shouldRouteShortcutToTerminal(
                hasKeyWindow: true,
                keyWindowIsTerminal: true,
                mainWindowIsTerminal: true,
                hasModalWindow: true,
                keyWindowHasAttachedSheet: false,
                mainWindowHasAttachedSheet: false,
                keyWindowOwnsFocusedTerminalResponder: true
            )
        )
        #expect(
            !LayoutShortcutController.shouldRouteShortcutToTerminal(
                hasKeyWindow: true,
                keyWindowIsTerminal: true,
                mainWindowIsTerminal: true,
                hasModalWindow: false,
                keyWindowHasAttachedSheet: true,
                mainWindowHasAttachedSheet: false,
                keyWindowOwnsFocusedTerminalResponder: true
            )
        )
        #expect(
            !LayoutShortcutController.shouldRouteShortcutToTerminal(
                hasKeyWindow: true,
                keyWindowIsTerminal: true,
                mainWindowIsTerminal: true,
                hasModalWindow: false,
                keyWindowHasAttachedSheet: false,
                mainWindowHasAttachedSheet: false,
                keyWindowOwnsFocusedTerminalResponder: false
            )
        )
    }

    @Test func applyingSinglePaneRequiresSecondInvocationAndUndoRestoresSplitLabels() throws {
        let appDelegate = try requireAppDelegate()
        let controller = TerminalController(appDelegate.yen)
        let settings = SettingsController.shared
        defer { closeTerminalController(controller) }

        let undoManager = try #require(controller.undoManager)
        let originalGroupsByEvent = undoManager.groupsByEvent
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = originalGroupsByEvent }

        let focusedSurface = try #require(controller.surfaceTree.first)
        controller.focusedSurface = focusedSurface
        focusedSurface.setSplitPaneLabel("Editor")
        let sibling = try #require(
            performUndoableAction(undoManager) {
                controller.newSplit(at: focusedSurface, direction: .right)
            }
        )
        controller.focusedSurface = focusedSurface
        sibling.setSplitPaneLabel("Logs")

        settings.applyLayout(.singlePane, controller: controller)
        #expect(controller.surfaceTree.isSplit)
        #expect(Array(controller.surfaceTree).count == 2)

        performUndoableAction(undoManager) {
            settings.applyLayout(.singlePane, controller: controller)
        }
        #expect(!controller.surfaceTree.isSplit)
        #expect(Array(controller.surfaceTree).count == 1)
        #expect(controller.surfaceTree.first?.id == focusedSurface.id)
        #expect(controller.undoManager?.canUndo == true)

        controller.undoManager?.undo()
        #expect(controller.surfaceTree.isSplit)
        #expect(Array(controller.surfaceTree).count == 2)
        #expect(controller.surfaceTree.first(where: { $0.id == focusedSurface.id })?.splitPaneLabel == "Editor")
        #expect(controller.surfaceTree.first(where: { $0.id == sibling.id })?.splitPaneLabel == "Logs")

        controller.undoManager?.redo()
        #expect(!controller.surfaceTree.isSplit)
        #expect(Array(controller.surfaceTree).count == 1)
        #expect(controller.surfaceTree.first?.id == focusedSurface.id)
    }

    @Test func singlePaneConfirmationResetsWhenFocusedPaneChanges() throws {
        let appDelegate = try requireAppDelegate()
        let controller = TerminalController(appDelegate.yen)
        let settings = SettingsController.shared
        defer { closeTerminalController(controller) }

        let undoManager = try #require(controller.undoManager)
        let originalGroupsByEvent = undoManager.groupsByEvent
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = originalGroupsByEvent }

        let focusedSurface = try #require(controller.surfaceTree.first)
        controller.focusedSurface = focusedSurface
        let sibling = try #require(
            performUndoableAction(undoManager) {
                controller.newSplit(at: focusedSurface, direction: .right)
            }
        )

        settings.applyLayout(.singlePane, controller: controller)
        controller.focusedSurface = sibling
        settings.applyLayout(.singlePane, controller: controller)

        #expect(controller.surfaceTree.isSplit)
        #expect(Array(controller.surfaceTree).count == 2)
    }

    @Test func applyingLayoutPreservesZoomedFocusedSubtree() throws {
        let appDelegate = try requireAppDelegate()
        let controller = TerminalController(appDelegate.yen)
        let settings = SettingsController.shared
        defer { closeTerminalController(controller) }

        let undoManager = try #require(controller.undoManager)
        let originalGroupsByEvent = undoManager.groupsByEvent
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = originalGroupsByEvent }

        let focusedSurface = try #require(controller.surfaceTree.first)
        controller.focusedSurface = focusedSurface
        _ = try #require(
            performUndoableAction(undoManager) {
                controller.newSplit(at: focusedSurface, direction: .right)
            }
        )
        controller.focusedSurface = focusedSurface
        let focusedNode = try #require(controller.surfaceTree.root?.node(view: focusedSurface))
        controller.surfaceTree = SplitTree(root: controller.surfaceTree.root, zoomed: focusedNode)

        performUndoableAction(undoManager) {
            settings.applyLayout(.rightStack, controller: controller)
        }

        let zoomedNode = try #require(controller.surfaceTree.zoomed)
        #expect(zoomedNode.contains(where: { $0.id == focusedSurface.id }))
        #expect(Array(controller.surfaceTree).count == 4)
    }

    @Test func applyingLayoutCreatesNewSurfacesFromFocusedSplitInheritanceConfig() throws {
        let appDelegate = try requireAppDelegate()
        var baseConfig = YEN.SurfaceConfiguration()
        baseConfig.fontSize = 17
        baseConfig.workingDirectory = "/tmp"
        let controller = TerminalController(appDelegate.yen, withBaseConfig: baseConfig)
        let settings = SettingsController.shared
        defer { closeTerminalController(controller) }

        let undoManager = try #require(controller.undoManager)
        let originalGroupsByEvent = undoManager.groupsByEvent
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = originalGroupsByEvent }

        let focusedSurface = try #require(controller.surfaceTree.first)
        controller.focusedSurface = focusedSurface
        let focusedSurfaceModel = try #require(focusedSurface.surface)
        let expectedInheritedConfig = YEN.SurfaceConfiguration(
            from: yen_surface_inherited_config(focusedSurfaceModel, YEN_SURFACE_CONTEXT_SPLIT)
        )

        performUndoableAction(undoManager) {
            settings.applyLayout(.rightStack, controller: controller)
        }

        let newSurfaces = controller.surfaceTree.filter { $0.id != focusedSurface.id }
        #expect(newSurfaces.count == 2)
        for surfaceView in newSurfaces {
            let surfaceModel = try #require(surfaceView.surface)
            let inheritedConfig = YEN.SurfaceConfiguration(
                from: yen_surface_inherited_config(surfaceModel, YEN_SURFACE_CONTEXT_SPLIT)
            )
            #expect(inheritedConfig.fontSize == expectedInheritedConfig.fontSize)
            #expect(inheritedConfig.workingDirectory == expectedInheritedConfig.workingDirectory)
        }
    }

    @Test func rejectedLayoutClearsPendingSinglePaneConfirmation() throws {
        let appDelegate = try requireAppDelegate()
        let controller = TerminalController(appDelegate.yen)
        let otherController = TerminalController(appDelegate.yen)
        defer {
            closeTerminalController(controller)
            closeTerminalController(otherController)
        }
        let focusedSurface = try #require(controller.surfaceTree.first)
        let foreignSurface = try #require(otherController.surfaceTree.first)
        let undoManager = try #require(controller.undoManager)
        let originalGroupsByEvent = undoManager.groupsByEvent
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = originalGroupsByEvent }
        _ = try #require(performUndoableAction(undoManager) {
            controller.newSplit(at: focusedSurface, direction: .right)
        })
        controller.focusedSurface = focusedSurface
        let applier = SettingsLayoutApplier(showStatus: { _, _, _, _ in })
        applier.apply(.singlePane, controller: controller)
        controller.focusedSurface = foreignSurface
        applier.apply(.rightStack, controller: controller)
        controller.focusedSurface = focusedSurface
        performUndoableAction(undoManager) {
            applier.apply(.singlePane, controller: controller)
        }
        #expect(controller.surfaceTree.isSplit)
        #expect(Array(controller.surfaceTree).count == 2)
    }

    @Test(arguments: LayoutTemplate.allCases)
    func invalidFocusedPaneDoesNotCreateNewSurfaces(layout: LayoutTemplate) throws {
        let appDelegate = try requireAppDelegate()
        let controller = TerminalController(appDelegate.yen)
        let otherController = TerminalController(appDelegate.yen)
        defer {
            closeTerminalController(controller)
            closeTerminalController(otherController)
        }
        let originalSurface = try #require(controller.surfaceTree.first)
        let foreignSurface = try #require(otherController.surfaceTree.first)
        controller.focusedSurface = foreignSurface
        var createdCount = 0
        let createdViews = NSHashTable<YEN.SurfaceView>.weakObjects()
        var reportedStatus: String?
        let applier = SettingsLayoutApplier(
            showStatus: { message, _, _, _ in reportedStatus = message },
            makeSurface: { app, config in
                let view = YEN.SurfaceView(app, baseConfig: config)
                createdCount += 1
                createdViews.add(view)
                return view
            }
        )
        autoreleasepool {
            applier.apply(layout, controller: controller)
        }
        #expect(reportedStatus == "Layout failed")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(controller.surfaceTree.first?.id == originalSurface.id)
        #expect(Array(controller.surfaceTree).count == 1)
        #expect(createdViews.allObjects.isEmpty, "Failed layout must not retain detached surfaces")
        #expect(createdCount == 0, "Invalid target must be rejected before spawning terminals")
    }

    private func requireAppDelegate() throws -> AppDelegate {
        try #require(NSApp.delegate as? AppDelegate)
    }

    private func performUndoableAction<T>(
        _ undoManager: UndoManager,
        _ body: () throws -> T
    ) rethrows -> T {
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        return try body()
    }

    private func closeTerminalController(_ controller: TerminalController) {
        controller.window?.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}
