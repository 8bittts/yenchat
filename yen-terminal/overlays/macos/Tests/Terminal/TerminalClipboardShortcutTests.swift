import AppKit
import Testing
@testable import YEN

struct TerminalClipboardShortcutTests {
    @Test func commandVPrefersStandardClipboardPasteSelector() {
        let selector = YEN.SurfaceView.performableClipboardSelector(
            menuAction: #selector(YEN.SurfaceView.paste(_:)),
            standardClipboardHasContents: true,
            selectionClipboardHasContents: false
        )

        #expect(selector == #selector(YEN.SurfaceView.paste(_:)))
    }

    @Test func commandShiftVPrefersSelectionClipboardPasteSelector() {
        let selector = YEN.SurfaceView.performableClipboardSelector(
            menuAction: #selector(YEN.SurfaceView.pasteSelection(_:)),
            standardClipboardHasContents: false,
            selectionClipboardHasContents: true
        )

        #expect(selector == #selector(YEN.SurfaceView.pasteSelection(_:)))
    }

    @Test func clipboardSelectorBypassStaysClosedWhenShortcutIsNotPasteOrClipboardIsEmpty() {
        let standardPasteWithoutClipboard = YEN.SurfaceView.performableClipboardSelector(
            menuAction: #selector(YEN.SurfaceView.paste(_:)),
            standardClipboardHasContents: false,
            selectionClipboardHasContents: false
        )
        let unrelatedShortcut = YEN.SurfaceView.performableClipboardSelector(
            menuAction: #selector(YEN.SurfaceView.copy(_:)),
            standardClipboardHasContents: true,
            selectionClipboardHasContents: false
        )
        let missingMenuAction = YEN.SurfaceView.performableClipboardSelector(
            menuAction: nil,
            standardClipboardHasContents: true,
            selectionClipboardHasContents: true
        )

        #expect(standardPasteWithoutClipboard == nil)
        #expect(unrelatedShortcut == nil)
        #expect(missingMenuAction == nil)
    }

    @Test func fixedGitDrawerShortcutBypassesTerminalBindingGate() {
        let shouldDispatch = YEN.SurfaceView.shouldPerformYENMenuShortcutBeforeTerminalEncoding(
            menuAction: #selector(AppDelegate.toggleGitDrawer(_:)),
            bindingFlags: nil,
            keySequenceIsEmpty: true,
            keyTablesAreEmpty: true
        )

        #expect(shouldDispatch)
    }

    @Test func fixedGitDrawerShortcutDoesNotInterruptKeySequencesOrTables() {
        #expect(!YEN.SurfaceView.shouldPerformYENMenuShortcutBeforeTerminalEncoding(
            menuAction: #selector(AppDelegate.toggleGitDrawer(_:)),
            bindingFlags: nil,
            keySequenceIsEmpty: false,
            keyTablesAreEmpty: true
        ))
        #expect(!YEN.SurfaceView.shouldPerformYENMenuShortcutBeforeTerminalEncoding(
            menuAction: #selector(AppDelegate.toggleGitDrawer(_:)),
            bindingFlags: nil,
            keySequenceIsEmpty: true,
            keyTablesAreEmpty: false
        ))
    }

    @Test func nonFixedMenuShortcutStillRequiresConsumedTerminalBinding() {
        #expect(!YEN.SurfaceView.shouldPerformYENMenuShortcutBeforeTerminalEncoding(
            menuAction: #selector(YEN.SurfaceView.copy(_:)),
            bindingFlags: nil,
            keySequenceIsEmpty: true,
            keyTablesAreEmpty: true
        ))
        #expect(YEN.SurfaceView.shouldPerformYENMenuShortcutBeforeTerminalEncoding(
            menuAction: #selector(YEN.SurfaceView.copy(_:)),
            bindingFlags: [.consumed],
            keySequenceIsEmpty: true,
            keyTablesAreEmpty: true
        ))
        #expect(!YEN.SurfaceView.shouldPerformYENMenuShortcutBeforeTerminalEncoding(
            menuAction: #selector(YEN.SurfaceView.copy(_:)),
            bindingFlags: [.consumed, .performable],
            keySequenceIsEmpty: true,
            keyTablesAreEmpty: true
        ))
    }
}
