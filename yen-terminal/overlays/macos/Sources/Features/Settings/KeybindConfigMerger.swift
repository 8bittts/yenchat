#if os(macOS)
import Foundation

@MainActor
enum KeybindConfigMerger {
    /// Reconcile keybind lines with editable entries:
    /// - remove existing Settings-managed lines (action overrides + default unbinds)
    /// - preserve unsupported advanced trigger syntax unless the user is actively overriding that action
    /// - append overrides as "default trigger = unbind" + "new trigger = action"
    ///   so remaps replace defaults instead of creating additive bindings
    static func mergingKeybindOverrides(into lines: [String], entries: [KeybindEntry]) -> [String] {
        let editableEntries = entries.filter { $0.isEditable }
        let editableActions = Set(editableEntries.map { $0.action })
        let overriddenEntries = editableEntries.filter {
            $0.isUserOverride && KeybindRegistry.validationError(for: $0.currentTrigger) == nil
        }
        let overriddenActions = Set(overriddenEntries.map { $0.action })
        // Actions whose config line Settings writes with a `global:` prefix.
        // Which `global:` lines Settings may reclaim.
        //
        // Two competing failure modes, so this needs both halves:
        //   - Deriving from the LIVE entries let a user's own prefix widen the scope, and a
        //     hand-written `global:<default>=<action>` line was DELETED by any unrelated write.
        //   - Deriving from the static registry ALONE made the removal side disagree with the
        //     append side (which uses the live `entry.isGlobal`). A user-authored global that
        //     Settings had since rewritten became unreclaimable, so Reset was a permanent
        //     no-op AND its paired `=unbind` survived, leaving the default trigger dead.
        //
        // A `global:` line whose trigger is NOT that action's default can only be one
        // Settings wrote (loadKeybinds marks any non-default trigger as a user override), so
        // it is ours to reclaim. One at the default trigger is the hand-written case: preserve.
        let staticGlobalActions = Set(KeybindRegistry.defaults.filter(\.isGlobal).map(\.action))
        var defaultTriggerByAction: [String: String] = [:]
        for entry in editableEntries {
            defaultTriggerByAction[entry.action] = entry.defaultTrigger.configString
        }
        func ownsGlobalLine(action: String, trigger: String) -> Bool {
            let split = KeybindRegistry.splitGlobalPrefix(trigger)
            guard split.isGlobal, editableActions.contains(action) else { return false }
            if staticGlobalActions.contains(action) { return true }
            guard let remainder = KeybindRegistry.parseTrigger(split.remainder) else { return false }
            return remainder.configString != defaultTriggerByAction[action]
        }
        let defaultTriggerToEditableActions = Dictionary(
            grouping: editableEntries,
            by: { $0.defaultTrigger.configString }
        )
        .mapValues { Set($0.map(\.action)) }

        let existingManagedSimpleActions = Set(lines.compactMap { line -> String? in
            guard let entry = ManagedConfigDocument.entry(from: line),
                  entry.key == "keybind",
                  let parsedValue = Self.splitKeybindValue(entry.value),
                  parsedValue.action != "unbind",
                  editableActions.contains(parsedValue.action) else {
                return nil
            }
            // Strip `global:` here too. Without it a global bind line never entered this
            // set, so its paired `=unbind` was not recognised as Settings-owned and
            // survived a Reset — leaving the default unbound with nothing rebinding it,
            // i.e. Quick Terminal with no shortcut at all.
            let globalSplit = KeybindRegistry.splitGlobalPrefix(parsedValue.trigger)
            let effectiveTrigger = ownsGlobalLine(
                action: parsedValue.action,
                trigger: parsedValue.trigger
            ) ? globalSplit.remainder : parsedValue.trigger
            guard KeybindRegistry.parseTrigger(effectiveTrigger) != nil else { return nil }
            return parsedValue.action
        })

        var merged = lines.filter { line in
            guard let entry = ManagedConfigDocument.entry(from: line), entry.key == "keybind" else { return true }
            guard let parsedValue = Self.splitKeybindValue(entry.value) else { return true }
            // Strip an optional `global:` ONLY for actions Settings itself manages as
            // global. Those lines are ours — we emit them — so they must be reclaimable,
            // or Reset leaves the stale remap in place and it never returns to default.
            // For every other action `global:` stays opaque advanced syntax and the line
            // is preserved verbatim, which is why this is scoped rather than blanket.
            let globalSplit = KeybindRegistry.splitGlobalPrefix(parsedValue.trigger)
            let ownsGlobalPrefix = ownsGlobalLine(
                action: parsedValue.action,
                trigger: parsedValue.trigger
            )
            let parsedTrigger = KeybindRegistry.parseTrigger(
                ownsGlobalPrefix ? globalSplit.remainder : parsedValue.trigger
            )

            if editableActions.contains(parsedValue.action) {
                // Settings owns simple trigger syntax for editable actions, and it must
                // replace advanced bindings for actions the user actively remapped.
                if parsedTrigger != nil || overriddenActions.contains(parsedValue.action) {
                    return false
                }
            }

            // An unbind line's action is literally `unbind`, so `ownsGlobalPrefix` above is
            // always false for it. Strip unconditionally — the prefix is meaningless on an
            // unbind (upstream `removeExact` keys on the trigger alone) and leaving it
            // unparsed made legacy prefixed unbinds unreclaimable.
            let unbindTrigger = KeybindRegistry.splitGlobalPrefix(parsedValue.trigger).remainder
            if parsedValue.action == "unbind",
               let parsedTrigger = KeybindRegistry.parseTrigger(unbindTrigger),
               let affectedActions = defaultTriggerToEditableActions[parsedTrigger.configString],
               affectedActions.contains(where: {
                   overriddenActions.contains($0) || existingManagedSimpleActions.contains($0)
               }) {
                return false
            }

            return true
        }

        for entry in overriddenEntries {
            // The BIND line carries the `global:` prefix; the UNBIND line must NOT.
            // Prefix rationale: `KeybindRegistry.isGlobal`. An unbind carrying the prefix is
            // never reclaimed by the strict `parseTrigger` filter above, so it duplicates on
            // every write and permanently shadows the default, making Reset a no-op.
            let prefix = entry.isGlobal ? "global:" : ""
            merged.append("keybind = \(entry.defaultTrigger.configString)=unbind")
            merged.append("keybind = \(prefix)\(entry.currentTrigger.configString)=\(entry.action)")
        }
        return merged
    }

    static func splitKeybindValue(_ value: String) -> (trigger: String, action: String)? {
        let parts = value.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let trigger = parts[0].trimmingCharacters(in: .whitespaces)
        let action = parts[1].trimmingCharacters(in: .whitespaces)
        guard !trigger.isEmpty, !action.isEmpty else { return nil }
        return (trigger: String(trigger), action: String(action))
    }
}
#endif
