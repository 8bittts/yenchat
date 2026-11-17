import AppKit
import AppIntents

/// YEN overlay hardening:
/// - Replaces free-form action string with allowlisted `CommandEntity`.
/// - Enforces intent action parity checks + audit logging.
@available(macOS 14.0, *)
struct KeybindIntent: AppIntent {
    static var title: LocalizedStringResource = "Invoke an Allowlisted Action"

    @Parameter(
        title: "Terminal",
        description: "The terminal to invoke the action on."
    )
    var terminal: TerminalEntity

    @Parameter(
        title: "Action",
        description: "Approved action sourced from YEN command catalogs.",
        optionsProvider: CommandQuery()
    )
    var command: CommandEntity

#if compiler(>=6.2)
    @available(macOS 26.0, *)
    static var supportedModes: IntentModes = [.background, .foreground]
#endif

    @available(macOS, obsoleted: 26.0, message: "Replaced by supportedModes")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        let performed = try await performAllowlistedControlAction(terminal: terminal, command: command)
        return .result(value: performed)
    }
}
