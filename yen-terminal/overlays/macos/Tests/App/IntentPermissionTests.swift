import AppKit
import Testing
import YENKit
@testable import YEN

private func makeAutomationCommand(
    actionKey: String,
    action: String,
    title: String = "Test Command",
    description: String = "Test Description"
) -> YEN.Command {
    let actionKeyPointer = strdup(actionKey)!
    let actionPointer = strdup(action)!
    let titlePointer = strdup(title)!
    let descriptionPointer = strdup(description)!
    defer {
        free(actionKeyPointer)
        free(actionPointer)
        free(titlePointer)
        free(descriptionPointer)
    }

    return YEN.Command(
        cValue: .init(
            action_key: UnsafePointer(actionKeyPointer),
            action: UnsafePointer(actionPointer),
            title: UnsafePointer(titlePointer),
            description: UnsafePointer(descriptionPointer)
        )
    )
}

@MainActor
struct IntentPermissionTests {
    @Test func promptPlanUsesSheetWhenAWindowExistsAndAppIsFrontmost() {
        let window = NSWindow()

        let plan = resolveIntentPermissionPromptPlan(
            keyWindow: nil,
            mainWindow: nil,
            orderedWindows: [window],
            windows: [window],
            isActive: true,
            isHidden: false,
            isFrontmost: true
        )

        #expect(plan.presentation == .sheet)
        #expect(!plan.requiresActivation)
    }

    @Test func promptPlanFallsBackToAppModalWhenNoWindowsExist() {
        let plan = resolveIntentPermissionPromptPlan(
            keyWindow: nil,
            mainWindow: nil,
            orderedWindows: [],
            windows: [],
            isActive: false,
            isHidden: true,
            isFrontmost: false
        )

        #expect(plan.presentation == .appModal)
        #expect(plan.requiresActivation)
    }

    @Test func requestIntentPermissionUsesExistingWindowWithoutForegrounding() async {
        let window = NSWindow()
        var preparedApp = false
        var capturedWindow: NSWindow?
        var presentedScopes: [IntentPermissionScope] = []

        let allowed = await requestIntentPermission(
            scope: .control,
            configResolver: { .ask },
            planResolver: {
                IntentPermissionPromptPlan(
                    presentation: .sheet,
                    requiresActivation: false
                )
            },
            promptWindowResolver: { window },
            appPreparer: { preparedApp = true },
            promptPresenter: { scope, resolvedWindow, completion in
                presentedScopes.append(scope)
                capturedWindow = resolvedWindow
                completion(true)
            }
        )

        #expect(allowed)
        #expect(!preparedApp)
        #expect(capturedWindow === window)
        #expect(presentedScopes == [.control])
    }

    @Test func requestIntentPermissionForegroundsAppAndUsesAppModalFallback() async {
        var prepareCount = 0
        var promptWindowResolved = false
        var capturedWindow: NSWindow?
        var presentedScopes: [IntentPermissionScope] = []

        let allowed = await requestIntentPermission(
            scope: .input,
            configResolver: { .ask },
            planResolver: {
                IntentPermissionPromptPlan(
                    presentation: .appModal,
                    requiresActivation: true
                )
            },
            promptWindowResolver: {
                promptWindowResolved = true
                return NSWindow()
            },
            appPreparer: { prepareCount += 1 },
            promptPresenter: { scope, resolvedWindow, completion in
                presentedScopes.append(scope)
                capturedWindow = resolvedWindow
                completion(true)
            }
        )

        #expect(allowed)
        #expect(prepareCount == 1)
        #expect(!promptWindowResolved)
        #expect(capturedWindow == nil)
        #expect(presentedScopes == [.input])
    }

    @Test func requestIntentPermissionFallsBackToAppModalWhenSheetWindowDisappears() async {
        var preparedApp = false
        var promptWindowResolved = false
        var capturedWindow: NSWindow?
        var presentedScopes: [IntentPermissionScope] = []

        let allowed = await requestIntentPermission(
            scope: .control,
            configResolver: { .ask },
            planResolver: {
                IntentPermissionPromptPlan(
                    presentation: .sheet,
                    requiresActivation: false
                )
            },
            promptWindowResolver: {
                promptWindowResolved = true
                return nil
            },
            appPreparer: { preparedApp = true },
            promptPresenter: { scope, resolvedWindow, completion in
                presentedScopes.append(scope)
                capturedWindow = resolvedWindow
                completion(true)
            }
        )

        #expect(allowed)
        #expect(!preparedApp)
        #expect(promptWindowResolved)
        #expect(capturedWindow == nil)
        #expect(presentedScopes == [.control])
    }

    @Test func requestIntentPermissionHonorsDenyConfigWithoutPrompting() async {
        var preparedApp = false
        var promptPresented = false

        let allowed = await requestIntentPermission(
            scope: .read,
            configResolver: { .deny },
            planResolver: {
                IntentPermissionPromptPlan(
                    presentation: .appModal,
                    requiresActivation: true
                )
            },
            appPreparer: { preparedApp = true },
            promptPresenter: { _, _, completion in
                promptPresented = true
                completion(true)
            }
        )

        #expect(!allowed)
        #expect(!preparedApp)
        #expect(!promptPresented)
    }

    @Test func automationCommandIdentityResolvesCanonicalActionStrings() {
        let command = makeAutomationCommand(
            actionKey: "new_tab",
            action: "new_tab"
        )

        let resolved = resolveAutomationCommandIdentity(
            "  NEW_TAB  ",
            commands: [command]
        )

        #expect(resolved?.action == "new_tab")
    }

    @Test func automationCommandIdentityRejectsTriggerPrefixesBlockedActionsAndUnsupportedCommands() {
        let blocked = makeAutomationCommand(
            actionKey: "crash-report",
            action: "crash-report"
        )
        let unsupported = makeAutomationCommand(
            actionKey: "toggle_window_decorations",
            action: "toggle_window_decorations"
        )
        let allowed = makeAutomationCommand(
            actionKey: "new_tab",
            action: "new_tab"
        )

        #expect(resolveAutomationCommandIdentity("+new_tab", commands: [allowed]) == nil)
        #expect(resolveAutomationCommandIdentity("crash-report", commands: [blocked]) == nil)
        #expect(
            resolveAutomationCommandIdentity(
                "toggle_window_decorations",
                commands: [unsupported]
            ) == nil
        )
    }

    @Test func automationCommandIdentityLegacyFallbackOnlyAppliesWhenRequested() {
        let splitLeft = makeAutomationCommand(
            actionKey: "goto_split",
            action: "goto_split:left"
        )

        #expect(resolveAutomationCommandIdentity("goto_split", commands: [splitLeft]) == nil)

        let resolved = resolveAutomationCommandIdentity(
            "goto_split",
            commands: [splitLeft],
            allowLegacyActionKeyFallback: true
        )

        #expect(resolved?.action == "goto_split:left")
    }

    @Test func automationCommandIdentityPrefersExactActionsBeforeLegacyFallback() {
        let splitLeft = makeAutomationCommand(
            actionKey: "goto_split",
            action: "goto_split:left"
        )
        let splitRight = makeAutomationCommand(
            actionKey: "goto_split",
            action: "goto_split:right"
        )

        let resolved = resolveAutomationCommandIdentity(
            "goto_split:right",
            commands: [splitLeft, splitRight],
            allowLegacyActionKeyFallback: true
        )

        #expect(resolved?.action == "goto_split:right")
    }
}

struct CommandEntityIdentityTests {
    @Test func commandEntityIDRoundTripsFullActionIdentity() {
        guard #available(macOS 14.0, *) else {
            return
        }

        let terminalID = UUID()
        let identity = CommandEntity.ID(
            terminalId: terminalID,
            actionIdentity: "goto_split:right"
        )

        let roundTripped = CommandEntity.ID(rawValue: identity.rawValue)

        #expect(roundTripped?.terminalId == terminalID)
        #expect(roundTripped?.actionIdentity == "goto_split:right")
    }
}
