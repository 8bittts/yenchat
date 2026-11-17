import Testing
@testable import YEN

@MainActor
struct TerminalCommandPaletteJumpTitleTests {
    @Test func jumpTitleUsesOverrideWhenPresent() {
        #expect(
            TerminalCommandPaletteView.jumpDisplayTitle(
                terminalTitle: "Session",
                titleOverride: "Pinned"
            ) == "Pinned"
        )
    }

    @Test func jumpTitleFallsBackToTerminalTitleWhenOverrideMissingOrEmpty() {
        #expect(
            TerminalCommandPaletteView.jumpDisplayTitle(
                terminalTitle: "Session",
                titleOverride: nil
            ) == "Session"
        )
        #expect(
            TerminalCommandPaletteView.jumpDisplayTitle(
                terminalTitle: "Session",
                titleOverride: ""
            ) == "Session"
        )
    }

    @Test func jumpTitleFallsBackToUntitledWhenNoNamesAvailable() {
        #expect(
            TerminalCommandPaletteView.jumpDisplayTitle(
                terminalTitle: "",
                titleOverride: nil
            ) == "Untitled"
        )
    }
}
