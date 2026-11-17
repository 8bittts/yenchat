#!/usr/bin/env python3
"""
Align AppDelegate+AppleScript perform-action handling with YEN's shared
automation command policy.
"""

import sys


LEGACY_BLOCK = """        guard let terminal = command.evaluatedArguments?["on"] as? ScriptTerminal else {
            command.scriptErrorNumber = errAEParamMissed
            command.scriptErrorString = "Missing terminal target."
            return nil
        }

        return NSNumber(value: terminal.perform(action: action))
"""


ALLOWLIST_BLOCK = """        guard let terminal = command.evaluatedArguments?["on"] as? ScriptTerminal else {
            command.scriptErrorNumber = errAEParamMissed
            command.scriptErrorString = "Missing terminal target."
            return nil
        }

        guard isAppleScriptActionAllowed(action) else {
            logAutomationAudit(
                source: .appleScript,
                decision: "deny-action",
                detail: action
            )
            command.scriptErrorNumber = errAEEventFailed
            command.scriptErrorString = "This AppleScript action is not allowlisted in YEN."
            return nil
        }

        let performed = terminal.perform(action: action)
        if !performed {
            logAutomationAudit(
                source: .appleScript,
                decision: "perform-failed",
                detail: action
            )
        }

        return NSNumber(value: performed)
"""


CURRENT_BLOCK = """        guard let terminal = command.evaluatedArguments?["on"] as? ScriptTerminal else {
            command.scriptErrorNumber = errAEParamMissed
            command.scriptErrorString = "Missing terminal target."
            return nil
        }

        guard let resolvedCommand = resolveAutomationCommand(action) else {
            logAutomationAudit(
                source: .appleScript,
                decision: "deny-action",
                detail: action
            )
            command.scriptErrorNumber = errAEEventFailed
            command.scriptErrorString = "This AppleScript action is not allowlisted in YEN."
            return nil
        }

        let performed = terminal.perform(action: resolvedCommand.action)
        if !performed {
            logAutomationAudit(
                source: .appleScript,
                decision: "perform-failed",
                detail: resolvedCommand.action
            )
        }

        return NSNumber(value: performed)
"""


NEW_BLOCK = """        guard let terminal = command.evaluatedArguments?["on"] as? ScriptTerminal else {
            command.scriptErrorNumber = errAEParamMissed
            command.scriptErrorString = "Missing terminal target."
            return nil
        }

        guard isAppleScriptActionAllowed(action),
              let resolvedCommand = resolveAutomationCommand(action) else {
            logAutomationAudit(
                source: .appleScript,
                decision: "deny-action",
                detail: action
            )
            command.scriptErrorNumber = errAEEventFailed
            command.scriptErrorString = "This AppleScript action is not allowlisted in YEN."
            return nil
        }

        let performed = terminal.perform(action: resolvedCommand.action)
        if !performed {
            logAutomationAudit(
                source: .appleScript,
                decision: "perform-failed",
                detail: resolvedCommand.action
            )
        }

        return NSNumber(value: performed)
"""


def main():
    if len(sys.argv) != 2:
        print("usage: apple-script-action-policy.py <AppDelegate+AppleScript.swift>", file=sys.stderr)
        return 2

    path = sys.argv[1]
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as handle:
        content = handle.read()

    if NEW_BLOCK in content:
        print("    AppleScript perform action policy already aligned (idempotent skip)")
        return 0

    for candidate in (CURRENT_BLOCK, ALLOWLIST_BLOCK, LEGACY_BLOCK):
        if candidate in content:
            content = content.replace(candidate, NEW_BLOCK, 1)
            with open(path, "w", encoding="utf-8", errors="surrogateescape") as handle:
                handle.write(content)
            print("    Aligned AppleScript perform action with shared automation policy")
            return 0

    print("  ERROR: AppleScript perform action anchor not found in AppDelegate+AppleScript.swift")
    return 1


if __name__ == "__main__":
    sys.exit(main())
