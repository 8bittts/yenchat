import AppKit
import SwiftUI
import Testing
@testable import YEN

struct CommandPaletteViewTests {
    @Test func externalDisplayedOptionsOverrideLocalFiltering() {
        let options = [
            option(id: "action:settings", title: "Settings"),
            option(id: "action:update", title: "Update"),
        ]
        let displayed = [
            option(id: "search:file:verify-guide.md", title: "verify-guide.md", badge: "file"),
            option(id: "search:content:notes.txt:2", title: "notes.txt:2", badge: "content"),
        ]

        let filtered = CommandPaletteView.filteredOptionsForTesting(
            options: options,
            displayedOptions: displayed
        )

        #expect(filtered.map(\.id) == displayed.map(\.id))
        #expect(filtered.map(\.badge) == ["file", "content"])
    }

    @Test func nilDisplayedOptionsReturnsUnfilteredOptions() {
        let options = [
            option(id: "action:update", title: "Update"),
            option(id: "action:settings", title: "Settings"),
            option(id: "action:reload", title: "Reload"),
        ]

        let filtered = CommandPaletteView.filteredOptionsForTesting(
            options: options
        )

        #expect(filtered.map(\.id) == options.map(\.id))
    }

    @Test func escapeDismissesEvenWhenTheQueryFieldDoesNotHaveFocus() {
        #expect(CommandPaletteView.shouldDismissForKeyDown(keyCode: 0x35))
        #expect(!CommandPaletteView.shouldDismissForKeyDown(keyCode: 0x24))
    }

    @Test func mouseDownOutsidePaletteDismissesWithoutConsumingInsideClicks() {
        let bounds = NSRect(x: 0, y: 0, width: 500, height: 260)

        #expect(
            CommandPaletteView.shouldDismissForMouseDown(
                eventType: .leftMouseDown,
                eventWindowMatchesPalette: true,
                locationInPalette: NSPoint(x: -1, y: 100),
                paletteBounds: bounds
            )
        )
        #expect(
            !CommandPaletteView.shouldDismissForMouseDown(
                eventType: .leftMouseDown,
                eventWindowMatchesPalette: true,
                locationInPalette: NSPoint(x: 250, y: 100),
                paletteBounds: bounds
            )
        )
        #expect(
            !CommandPaletteView.shouldDismissForMouseDown(
                eventType: .mouseMoved,
                eventWindowMatchesPalette: true,
                locationInPalette: NSPoint(x: -1, y: 100),
                paletteBounds: bounds
            )
        )
        #expect(
            CommandPaletteView.shouldDismissForMouseDown(
                eventType: .leftMouseDown,
                eventWindowMatchesPalette: false,
                locationInPalette: nil,
                paletteBounds: bounds
            )
        )
    }

    @MainActor
    @Test func applicationFocusLossDismissesPresentedPalette() {
        let state = CommandPalettePresentationState()
        let host = NSHostingView(
            rootView: CommandPaletteView(
                isPresented: Binding(
                    get: { state.isPresented },
                    set: { state.isPresented = $0 }
                ),
                options: [option(id: "action:test", title: "Test")],
                onDismiss: { state.dismissCount += 1 }
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        NotificationCenter.default.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        #expect(!state.isPresented)
        #expect(state.dismissCount == 1)
    }

    private func option(
        id: String,
        title: String,
        badge: String? = nil
    ) -> CommandOption {
        CommandOption(
            id: id,
            title: title,
            badge: badge
        ) {}
    }
}

@MainActor
private final class CommandPalettePresentationState {
    var isPresented = true
    var dismissCount = 0
}
