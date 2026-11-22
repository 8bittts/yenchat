import AppKit
import AppIntents

/// App intent that invokes a command palette entry.
@available(macOS 14.0, *)
struct CommandPaletteIntent: AppIntent {
    static var title: LocalizedStringResource = "Invoke Command Palette Action"

    @Parameter(
        title: "Terminal",
        description: "The terminal to base available commands from."
    )
    var terminal: TerminalEntity

    @Parameter(
        title: "Command",
        description: "The command to invoke.",
        optionsProvider: CommandQuery()
    )
    var command: CommandEntity

    static var supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let performed = try await performAllowlistedControlAction(terminal: terminal, command: command)
        return .result(value: performed)
    }
}
