import AppKit
import Foundation

enum IntentPermissionScope: String {
    case control
    case input
    case read

    var permissionKey: String {
        return "com.yenchat.yen.shortcutsPermission.\(rawValue)"
    }

    var promptMessage: String {
        switch self {
        case .control:
            return "Allow Shortcuts to control YEN terminal actions?"
        case .input:
            return "Allow Shortcuts to send keyboard/mouse/text input to YEN?"
        case .read:
            return "Allow Shortcuts to read terminal details from YEN?"
        }
    }

    var allowDuration: Duration {
        switch self {
        case .control:
            return .seconds(600)
        case .input:
            return .seconds(300)
        case .read:
            return .seconds(180)
        }
    }
}

enum AutomationActionSource: String {
    case appleScript = "applescript"
    case shortcuts = "shortcuts"
}

enum IntentPermissionPromptPresentation: String, Equatable {
    case sheet = "sheet"
    case appModal = "app-modal"
}

struct IntentPermissionPromptPlan: Equatable {
    let presentation: IntentPermissionPromptPresentation
    let requiresActivation: Bool
}

typealias IntentPermissionPromptPresenter = @MainActor (
    _ scope: IntentPermissionScope,
    _ window: NSWindow?,
    _ completion: @escaping (Bool) -> Void
) -> Void

func logAutomationAudit(source: AutomationActionSource, decision: String, detail: String = "") {
    if detail.isEmpty {
        NSLog("YEN automation audit source=%@ decision=%@", source.rawValue, decision)
    } else {
        NSLog("YEN automation audit source=%@ decision=%@ detail=%@", source.rawValue, decision, detail)
    }
}

func logIntentAudit(scope: IntentPermissionScope, decision: String, detail: String = "") {
    if detail.isEmpty {
        NSLog("YEN AppIntent audit scope=%@ decision=%@", scope.rawValue, decision)
    } else {
        NSLog("YEN AppIntent audit scope=%@ decision=%@ detail=%@", scope.rawValue, decision, detail)
    }
}

private func normalizedAutomationAction(_ action: String) -> String {
    action
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private let blockedActions: Set<String> = [
    "boo",
    "show-config",
    "crash-report",
]

private func isAutomationCommandBlocked(_ command: YEN.Command) -> Bool {
    blockedActions.contains(normalizedAutomationAction(command.actionKey))
}

private func loadStandaloneConfig() -> YEN.Config? {
#if DEBUG
    let config = YEN.Config(at: ProcessInfo.processInfo.environment["YEN_CONFIG_PATH"])
#else
    let config = YEN.Config()
#endif

    return config.loaded ? config : nil
}

@MainActor
private func resolveAllowlistedAutomationCommands() -> [YEN.Command] {
    let commands: [YEN.Command]

    if let delegate = AppDelegate.shared {
        commands = delegate.yen.config.commandPaletteEntries
    } else {
        guard let config = loadStandaloneConfig() else {
            return []
        }
        commands = config.commandPaletteEntries
    }

    return commands.filter(\.isSupported)
}

@MainActor
private func resolveAllowlistedAutomationActions() -> Set<String> {
    Set(
        resolveAllowlistedAutomationCommands()
            .map { normalizedAutomationAction($0.action) }
    )
}

func resolveAutomationCommandIdentity(
    _ identity: String,
    commands: [YEN.Command],
    allowLegacyActionKeyFallback: Bool = false
) -> YEN.Command? {
    let normalized = normalizedAutomationAction(identity)
    guard !normalized.isEmpty else { return nil }
    guard !normalized.hasPrefix("+") else { return nil }

    let supportedCommands = commands.filter(\.isSupported)

    if let exactMatch = supportedCommands.first(where: {
        normalizedAutomationAction($0.action) == normalized
    }) {
        return isAutomationCommandBlocked(exactMatch) ? nil : exactMatch
    }

    guard allowLegacyActionKeyFallback else { return nil }

    if let legacyMatch = supportedCommands.first(where: {
        normalizedAutomationAction($0.actionKey) == normalized
    }) {
        return isAutomationCommandBlocked(legacyMatch) ? nil : legacyMatch
    }

    return nil
}

@MainActor
func resolveAutomationCommand(_ identity: String) -> YEN.Command? {
    resolveAutomationCommandIdentity(
        identity,
        commands: resolveAllowlistedAutomationCommands()
    )
}

@MainActor
func resolveAutomationCommandAllowingLegacyIdentity(_ identity: String) -> YEN.Command? {
    resolveAutomationCommandIdentity(
        identity,
        commands: resolveAllowlistedAutomationCommands(),
        allowLegacyActionKeyFallback: true
    )
}

@MainActor
func isAutomationActionAllowed(_ action: String) -> Bool {
    let normalized = normalizedAutomationAction(action)
    guard !normalized.isEmpty else { return false }
    guard !normalized.hasPrefix("+") else { return false }
    guard !resolveAllowlistedAutomationActions().isEmpty else { return false }
    return resolveAutomationCommand(action) != nil
}

@MainActor
func isAppIntentActionAllowed(_ action: String) -> Bool {
    isAutomationActionAllowed(action)
}

@MainActor
func isAppleScriptActionAllowed(_ action: String) -> Bool {
    isAutomationActionAllowed(action)
}

@MainActor
private func resolveMacOSShortcutsConfig() -> YEN.Config.MacShortcuts? {
    if let delegate = AppDelegate.shared {
        return delegate.yen.config.macosShortcuts
    }

    return loadStandaloneConfig()?.macosShortcuts
}

@MainActor
private func permissionPromptWindowIfAvailable() -> NSWindow? {
    if let activeWindow = NSApp.keyWindow ?? NSApp.mainWindow {
        return activeWindow
    }
    return NSApp.orderedWindows.first(where: \.isVisible)
        ?? NSApp.windows.first(where: \.isVisible)
        ?? NSApp.orderedWindows.first
        ?? NSApp.windows.first
}

@MainActor
func resolveIntentPermissionPromptPlan(
    keyWindow: NSWindow?,
    mainWindow: NSWindow?,
    orderedWindows: [NSWindow],
    windows: [NSWindow],
    isActive: Bool,
    isHidden: Bool,
    isFrontmost: Bool
) -> IntentPermissionPromptPlan {
    let hasPromptWindow = keyWindow != nil
        || mainWindow != nil
        || orderedWindows.contains(where: \.isVisible)
        || windows.contains(where: \.isVisible)
        || !orderedWindows.isEmpty
        || !windows.isEmpty

    return IntentPermissionPromptPlan(
        presentation: hasPromptWindow ? .sheet : .appModal,
        requiresActivation: isHidden || !isActive || !isFrontmost
    )
}

@MainActor
func currentIntentPermissionPromptPlan() -> IntentPermissionPromptPlan {
    resolveIntentPermissionPromptPlan(
        keyWindow: NSApp.keyWindow,
        mainWindow: NSApp.mainWindow,
        orderedWindows: NSApp.orderedWindows,
        windows: NSApp.windows,
        isActive: NSApp.isActive,
        isHidden: NSApp.isHidden,
        isFrontmost: NSApp.isFrontmost
    )
}

@MainActor
func prepareAppForIntentPermissionPrompt() {
    NSApp.unhide(nil)
    NSApp.yenActivateCompat()
}

@MainActor
func presentIntentPermissionPrompt(
    scope: IntentPermissionScope,
    window: NSWindow?,
    completion: @escaping (Bool) -> Void
) {
    PermissionRequest.show(
        scope.permissionKey,
        message: scope.promptMessage,
        allowDuration: .duration(scope.allowDuration),
        rememberDuration: nil,
        window: window,
        completion: completion
    )
}

/// Requests permission for Shortcuts app to interact with YEN.
///
/// Permission decisions are scoped per intent class (`control`, `input`, `read`)
/// and cached for a bounded TTL to reduce stale broad grants.
func requestIntentPermission(
    scope: IntentPermissionScope = .control,
    configResolver: @escaping @MainActor () -> YEN.Config.MacShortcuts? = resolveMacOSShortcutsConfig,
    planResolver: @escaping @MainActor () -> IntentPermissionPromptPlan = currentIntentPermissionPromptPlan,
    promptWindowResolver: @escaping @MainActor () -> NSWindow? = permissionPromptWindowIfAvailable,
    appPreparer: @escaping @MainActor () -> Void = prepareAppForIntentPermissionPrompt,
    promptPresenter: @escaping IntentPermissionPromptPresenter = presentIntentPermissionPrompt
) async -> Bool {
    await withCheckedContinuation { continuation in
        Task { @MainActor in
            guard let shortcutsPolicy = configResolver() else {
                logIntentAudit(scope: scope, decision: "deny-config-unavailable")
                continuation.resume(returning: false)
                return
            }

            switch shortcutsPolicy {
            case .allow:
                logIntentAudit(scope: scope, decision: "allow-config")
                continuation.resume(returning: true)
                return

            case .deny:
                logIntentAudit(scope: scope, decision: "deny-config")
                continuation.resume(returning: false)
                return

            case .ask:
                break
            }

            let plan = planResolver()
            if plan.requiresActivation {
                appPreparer()
            }

            let promptWindow = plan.presentation == .sheet ? promptWindowResolver() : nil
            let actualPresentation: IntentPermissionPromptPresentation = promptWindow == nil ? .appModal : plan.presentation
            let detail = plan.requiresActivation
                ? "\(actualPresentation.rawValue):activated"
                : actualPresentation.rawValue

            promptPresenter(scope, promptWindow) { response in
                logIntentAudit(
                    scope: scope,
                    decision: response ? "allow" : "deny",
                    detail: detail
                )
                continuation.resume(returning: response)
            }
        }
    }
}

/// Shared body for the allowlisted control-action App Intents (`CommandPaletteIntent`,
/// `KeybindIntent`), whose `perform()` bodies were byte-identical. Returns whether the
/// resolved action was performed; throws `YENIntentError` on permission, surface, or
/// allowlist failure.
@available(macOS 14.0, *)
@MainActor
func performAllowlistedControlAction(terminal: TerminalEntity, command: CommandEntity) async throws -> Bool {
    guard await requestIntentPermission(scope: .control) else {
        throw YENIntentError.permissionDenied
    }

    guard let surface = terminal.surfaceModel else {
        throw YENIntentError.surfaceNotFound
    }

    guard isAppIntentActionAllowed(command.action),
          let resolvedCommand = resolveAutomationCommand(command.action) else {
        logIntentAudit(
            scope: .control,
            decision: "deny-action",
            detail: command.action
        )
        throw YENIntentError.actionNotAllowed
    }

    let performed = surface.perform(action: resolvedCommand.action)
    if !performed {
        logIntentAudit(
            scope: .control,
            decision: "perform-failed",
            detail: resolvedCommand.action
        )
    }
    return performed
}
