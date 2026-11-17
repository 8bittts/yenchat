import Foundation
import AppKit
import Testing
@testable import YEN

@MainActor
struct SettingsConfigMergeTests {
    @Test func mergingKeybindOverridesRemovesManagedResetEntries() {
        var entries = KeybindRegistry.defaults
        let targetIndex = entries.firstIndex {
            $0.action == "new_split:right" && $0.isEditable
        }
        #expect(targetIndex != nil)
        guard let targetIndex else { return }

        entries[targetIndex].currentTrigger = entries[targetIndex].defaultTrigger
        entries[targetIndex].isUserOverride = false

        let lines = [
            "font-size = 14",
            "keybind = super+y=new_split:right",
            "keybind = super+d=unbind",
            "keybind = ctrl+x=do_the_thing",
        ]
        let merged = KeybindConfigMerger.mergingKeybindOverrides(into: lines, entries: entries)

        #expect(!merged.contains(where: { $0.contains("=new_split:right") }))
        #expect(!merged.contains("keybind = super+d=unbind"))
        #expect(merged.contains("keybind = ctrl+x=do_the_thing"))
    }

    @Test func mergingKeybindOverridesWritesCurrentOverrides() {
        var entries = KeybindRegistry.defaults
        let targetIndex = entries.firstIndex {
            $0.action == "new_split:right" && $0.isEditable
        }
        #expect(targetIndex != nil)
        guard let targetIndex else { return }

        entries[targetIndex].currentTrigger = KeyTrigger(
            modifiers: KeyModifiers(cmd: true),
            key: "y"
        )
        entries[targetIndex].isUserOverride = true

        let lines = [
            "font-size = 14",
            "keybind = super+d=new_split:right",
            "keybind = super+d=unbind",
            "keybind = ctrl+x=do_the_thing",
        ]
        let merged = KeybindConfigMerger.mergingKeybindOverrides(into: lines, entries: entries)
        let actionLines = merged.filter { $0.contains("=new_split:right") }
        let unbindLines = merged.filter { $0 == "keybind = super+d=unbind" }

        #expect(actionLines.count == 1)
        #expect(actionLines.first == "keybind = super+y=new_split:right")
        #expect(unbindLines.count == 1)
        #expect(merged.contains("keybind = ctrl+x=do_the_thing"))
    }

    @Test func mergingKeybindOverridesPersistsMultipleShortcutCombinations() {
        var entries = KeybindRegistry.defaults
        let splitIndex = entries.firstIndex {
            $0.action == "new_split:right" && $0.isEditable
        }
        let paletteIndex = entries.firstIndex {
            $0.action == "toggle_command_palette" && $0.isEditable
        }
        #expect(splitIndex != nil)
        #expect(paletteIndex != nil)
        guard let splitIndex, let paletteIndex else { return }

        entries[splitIndex].currentTrigger = KeyTrigger(
            modifiers: KeyModifiers(cmd: true, option: true),
            key: "right",
            keyCode: 124,
            displayKey: "Right"
        )
        entries[splitIndex].isUserOverride = true
        entries[paletteIndex].currentTrigger = KeyTrigger(
            modifiers: KeyModifiers(cmd: true, ctrl: true, shift: true),
            key: "p",
            keyCode: 35,
            displayKey: "P"
        )
        entries[paletteIndex].isUserOverride = true

        let merged = KeybindConfigMerger.mergingKeybindOverrides(
            into: ["font-size = 14"],
            entries: entries
        )

        #expect(merged.contains("keybind = super+d=unbind"))
        #expect(merged.contains("keybind = alt+super+right=new_split:right"))
        #expect(merged.contains("keybind = shift+super+p=unbind"))
        #expect(merged.contains("keybind = ctrl+shift+super+p=toggle_command_palette"))
    }

    @Test func mergingKeybindOverridesPreservesManualSimpleUnbindLinesWithoutManagedOverridePair() {
        let entries = KeybindRegistry.defaults
        let lines = [
            "font-size = 14",
            "keybind = super+d=unbind",
            "keybind = ctrl+x=do_the_thing",
        ]

        let merged = KeybindConfigMerger.mergingKeybindOverrides(into: lines, entries: entries)

        #expect(merged.contains("keybind = super+d=unbind"))
        #expect(merged.contains("keybind = ctrl+x=do_the_thing"))
    }

    @Test func mergingKeybindOverridesPreservesUnsupportedAdvancedKeybindSyntax() {
        var entries = KeybindRegistry.defaults
        let targetIndex = entries.firstIndex {
            $0.action == "new_split:right" && $0.isEditable
        }
        #expect(targetIndex != nil)
        guard let targetIndex else { return }

        entries[targetIndex].currentTrigger = entries[targetIndex].defaultTrigger
        entries[targetIndex].isUserOverride = false

        let lines = [
            "keybind = super+d=new_split:right",
            "keybind = global:ctrl+backquote=toggle_visual_bell",
            "keybind = work/super+d=new_split:right",
            "keybind = super+d>n=new_split:right",
        ]
        let merged = KeybindConfigMerger.mergingKeybindOverrides(into: lines, entries: entries)

        #expect(!merged.contains("keybind = super+d=new_split:right"))
        #expect(merged.contains("keybind = global:ctrl+backquote=toggle_visual_bell"))
        #expect(merged.contains("keybind = work/super+d=new_split:right"))
        #expect(merged.contains("keybind = super+d>n=new_split:right"))
    }

    @Test func keybindOverrideMergeRoundTripsResetWhilePreservingUnmanagedOriginalLines() {
        var entries = KeybindRegistry.defaults
        let targetIndex = entries.firstIndex {
            $0.action == "new_split:right" && $0.isEditable
        }
        #expect(targetIndex != nil)
        guard let targetIndex else { return }

        let originalLines = [
            "# keyboard hand edits",
            "",
            "  keybind = global:ctrl+backquote=toggle_visual_bell  ",
            "keybind = ctrl+x=do_the_thing",
        ]

        entries[targetIndex].currentTrigger = KeyTrigger(
            modifiers: KeyModifiers(cmd: true),
            key: "y"
        )
        entries[targetIndex].isUserOverride = true

        let overridden = KeybindConfigMerger.mergingKeybindOverrides(into: originalLines, entries: entries)

        #expect(Array(overridden.prefix(originalLines.count)) == originalLines)
        #expect(
            Array(overridden.suffix(2)) == [
                "keybind = \(entries[targetIndex].defaultTrigger.configString)=unbind",
                "keybind = super+y=new_split:right",
            ]
        )

        entries[targetIndex].currentTrigger = entries[targetIndex].defaultTrigger
        entries[targetIndex].isUserOverride = false

        let reset = KeybindConfigMerger.mergingKeybindOverrides(into: overridden, entries: entries)

        #expect(reset == originalLines)
    }

    @Test func mergePreservesEveryOccurrenceOfRepeatableKeys() {
        // ManagedConfigDocument.merged() de-duplicates by key. Before repeatableKeys
        // existed, only `keybind` survived: a hand-authored 16-entry palette block, a
        // font-family fallback chain, and multiple config-file includes were all
        // truncated to their first line the next time Settings wrote anything —
        // silent user-data loss on an edit the user never made.
        var existing: [String] = ["# user config", "font-size = 14"]
        for index in 0..<16 {
            existing.append("palette = \(index)=#1d1f21")
        }
        existing.append("config-file = ./work.yen")
        existing.append("config-file = ./personal.yen")
        existing.append("link = https://example.com,open")
        existing.append("link = https://other.example,open")

        // No theme selected, so palette lines are NOT theme-stripped.
        let document = ManagedConfigDocument(
            settings: [.init(key: "font-size", value: "16")],
            hasSelectedTheme: false,
            hasBackgroundImage: false
        )
        let merged = document.merged(intoExistingLines: existing)

        #expect(merged.filter { $0.hasPrefix("palette = ") }.count == 16)
        #expect(merged.filter { $0.hasPrefix("config-file = ") }.count == 2)
        #expect(merged.filter { $0.hasPrefix("link = ") }.count == 2)
        #expect(merged.contains("font-size = 16"))
        #expect(merged.contains("# user config"))
        // Order and content of the repeated block must be untouched.
        #expect(merged.contains("palette = 0=#1d1f21"))
        #expect(merged.contains("palette = 15=#1d1f21"))
        #expect(merged.contains("config-file = ./personal.yen"))
    }

    @Test func mergeReplacesOnlyTheFirstOccurrenceOfAManagedRepeatableKey() {
        // The managed value owns the PRIMARY entry; the user's fallback chain must
        // survive. Rewriting every occurrence would produce N copies of the picker's
        // font and silently delete the fallbacks.
        let existing = [
            "font-family = JetBrains Mono",
            "font-family = Symbols Nerd Font",
            "font-family = Apple Color Emoji",
        ]
        let document = ManagedConfigDocument(
            settings: [.init(key: "font-family", value: "SF Mono")],
            hasSelectedTheme: false,
            hasBackgroundImage: false
        )
        let merged = document.merged(intoExistingLines: existing)

        #expect(merged == [
            "font-family = SF Mono",
            "font-family = Symbols Nerd Font",
            "font-family = Apple Color Emoji",
        ])
    }

    @Test func mergeStillCollapsesNonRepeatableDuplicates() {
        // The de-dup itself is load-bearing for scalar keys — two font-size lines must
        // not both survive just because the repeatable fix relaxed the rule.
        let existing = ["font-size = 14", "font-size = 18", "window-padding-x = 4"]
        let document = ManagedConfigDocument(
            settings: [.init(key: "font-size", value: "16")],
            hasSelectedTheme: false,
            hasBackgroundImage: false
        )
        let merged = document.merged(intoExistingLines: existing)

        #expect(merged.filter { $0.hasPrefix("font-size") } == ["font-size = 16"])
        #expect(merged.contains("window-padding-x = 4"))
    }

    @Test func remappingAGlobalKeybindKeepsTheGlobalPrefix() {
        // Without the prefix, `yen_app_has_global_keybinds` goes false, the global event
        // tap is never installed, and Quick Terminal stops firing while YEN is not
        // frontmost — the entire point of the feature.
        var entries = KeybindRegistry.defaults
        let index = try! #require(entries.firstIndex {
            $0.action == "toggle_quick_terminal" && $0.isEditable
        })
        #expect(entries[index].isGlobal)

        entries[index].currentTrigger = KeyTrigger(
            modifiers: KeyModifiers(ctrl: true, option: true),
            key: "space"
        )
        entries[index].isUserOverride = true

        let merged = KeybindConfigMerger.mergingKeybindOverrides(
            into: ["keybind = global:ctrl+backquote=toggle_quick_terminal"],
            entries: entries
        )
        let lines = merged.filter { $0.contains("toggle_quick_terminal") }
        #expect(lines == ["keybind = global:ctrl+alt+space=toggle_quick_terminal"])
        // The BIND line keeps the prefix; the UNBIND line must not, or the merge's own
        // strict-parser cleanup can never reclaim it and it duplicates on every write.
        #expect(merged.contains("keybind = ctrl+backquote=unbind"))
        #expect(!merged.contains("keybind = global:ctrl+backquote=unbind"))
    }

    @Test func resettingARemappedGlobalKeybindClearsTheStaleBinding() {
        // After a remap, config holds `global:<new>=toggle_quick_terminal`. Reset clears
        // the override, so nothing re-emits it — the merge must RECLAIM that line or the
        // stale remap survives and Reset is a permanent no-op.
        let entries = KeybindRegistry.defaults  // toggle_quick_terminal at its default
        let merged = KeybindConfigMerger.mergingKeybindOverrides(
            into: [
                "keybind = ctrl+backquote=unbind",
                "keybind = global:ctrl+alt+space=toggle_quick_terminal",
            ],
            entries: entries
        )
        #expect(!merged.contains(where: { $0.contains("toggle_quick_terminal") }))
        // Assert the WHOLE result. Only checking that the action line is gone is exactly
        // what let an orphan `ctrl+backquote=unbind` ship: it survives a reset, unbinds
        // the built-in default, and leaves Quick Terminal with NO shortcut at all.
        #expect(!merged.contains(where: { $0.contains("=unbind") }))
        #expect(merged.isEmpty)
    }

    @Test func resettingAUserAuthoredGlobalRemapClearsBothLines() {
        // A user hand-wrote `global:` for a Settings-managed action, then remapped it in
        // Settings. Reset must clear BOTH the rewritten bind line and its paired unbind.
        // Regression: the removal side used only the static registry while the append side
        // used the live entry's isGlobal, so the line was unreclaimable — Reset became a
        // permanent no-op AND the orphan unbind left the default trigger dead.
        var remapped = KeybindRegistry.defaults
        let index = try! #require(remapped.firstIndex {
            $0.action == "new_window" && $0.isEditable
        })
        remapped[index].isGlobal = true  // as loadKeybinds would, from the user's config
        remapped[index].currentTrigger = KeyTrigger(
            modifiers: KeyModifiers(cmd: true, shift: true),
            key: "x"
        )
        remapped[index].isUserOverride = true

        let afterRemap = KeybindConfigMerger.mergingKeybindOverrides(
            into: ["font-size = 14"],
            entries: remapped
        )
        #expect(afterRemap.contains(where: { $0.contains("global:") && $0.contains("new_window") }))

        // Reset rebuilds from the static registry, so isGlobal returns to false.
        let afterReset = KeybindConfigMerger.mergingKeybindOverrides(
            into: afterRemap,
            entries: KeybindRegistry.defaults
        )
        #expect(afterReset == ["font-size = 14"])
    }

    @Test func handWrittenGlobalPrefixSurvivesAnUnrelatedSettingsWrite() {
        // Upstream documents `global:` as valid on ANY binding. A user who hand-writes one
        // for an action Settings manages must not lose it to an unrelated slider drag.
        // Regression: deriving the reclaim scope from the LIVE entries (which loadKeybinds
        // ORs the parsed isGlobal into) made the user's own prefix widen that scope, and
        // the line was deleted.
        var entries = KeybindRegistry.defaults
        let index = try! #require(entries.firstIndex {
            $0.action == "new_window" && $0.isEditable
        })
        #expect(!entries[index].isGlobal, "new_window must not be global in the static registry")
        // Simulate loadKeybinds having read `keybind = global:<default>=new_window`.
        entries[index].isGlobal = true

        let line = "keybind = global:\(entries[index].defaultTrigger.configString)=new_window"
        let merged = KeybindConfigMerger.mergingKeybindOverrides(
            into: ["font-size = 14", line],
            entries: entries
        )
        #expect(merged.contains(line))
    }

    @Test func repeatedWritesDoNotAccumulateGlobalKeybindLines() {
        // The merge output must be a fixed point. A `global:`-prefixed line the strict
        // parser could not reclaim used to duplicate on every unrelated Settings write.
        var entries = KeybindRegistry.defaults
        let index = try! #require(entries.firstIndex {
            $0.action == "toggle_quick_terminal" && $0.isEditable
        })
        entries[index].currentTrigger = KeyTrigger(
            modifiers: KeyModifiers(ctrl: true, option: true),
            key: "space"
        )
        entries[index].isUserOverride = true

        let first = KeybindConfigMerger.mergingKeybindOverrides(into: [], entries: entries)
        let second = KeybindConfigMerger.mergingKeybindOverrides(into: first, entries: entries)
        let third = KeybindConfigMerger.mergingKeybindOverrides(into: second, entries: entries)
        #expect(second == first)
        #expect(third == first)
        #expect(first.filter { $0.contains("toggle_quick_terminal") }.count == 1)
        #expect(first.filter { $0.contains("=unbind") }.count == 1)
    }

    @Test func nonGlobalKeybindRemapsWithoutAGlobalPrefix() {
        var entries = KeybindRegistry.defaults
        let index = try! #require(entries.firstIndex {
            $0.action == "new_split:right" && $0.isEditable
        })
        #expect(!entries[index].isGlobal)

        entries[index].currentTrigger = KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "y")
        entries[index].isUserOverride = true

        let merged = KeybindConfigMerger.mergingKeybindOverrides(into: [], entries: entries)
        #expect(merged.contains("keybind = super+y=new_split:right"))
        #expect(!merged.contains(where: { $0.contains("global:") }))
    }

    @Test func globalPrefixedOverridesAreReadBackAsUserOverrides() {
        // The write path is only half the round trip: `parseConfigLine` rejects any
        // trigger containing ':', so a remapped global binding used to be invisible on
        // the next launch and the shortcut list showed the default as current while
        // config actually bound something else.
        let parsed = try! #require(
            KeybindRegistry.parseConfigLineAllowingGlobal("global:ctrl+alt+space=toggle_quick_terminal")
        )
        #expect(parsed.isGlobal)
        #expect(parsed.action == "toggle_quick_terminal")
        #expect(parsed.trigger == KeyTrigger(
            modifiers: KeyModifiers(ctrl: true, option: true),
            key: "space"
        ))

        // Strict parsing is unchanged, so the merge still preserves advanced syntax.
        #expect(KeybindRegistry.parseConfigLine("global:ctrl+alt+space=toggle_quick_terminal") == nil)
        #expect(KeybindRegistry.splitGlobalPrefix("global:ctrl+alt+space").isGlobal)
        #expect(KeybindRegistry.splitGlobalPrefix("ctrl+alt+space").remainder == "ctrl+alt+space")
        // Table/sequence syntax must still be rejected outright.
        #expect(KeybindRegistry.parseConfigLineAllowingGlobal("work/super+d=new_split:right") == nil)
    }

    @Test func themePreviewRollbackRestoresEveryPaletteLine() {
        // Applying a theme strips every themeColorKey, including all 16 palette lines.
        // Rollback rebuilt them from a first-occurrence-only baseline map, so a
        // hand-authored palette block came back as ONE line and fifteen were destroyed.
        var baselineLines = ["theme = Old Theme", "font-size = 14"]
        for index in 0..<16 {
            baselineLines.append("palette = \(index)=#1d1f21")
        }
        let baseline = baselineLines.joined(separator: "\n")
        let previewed = SettingsController.configByApplyingTheme("Preview Theme", to: baseline)
        #expect(!previewed.contains("palette ="))

        let rolledBack = try! #require(
            SettingsController.configByRollingBackThemePreview(
                currentContents: previewed,
                baselineContents: baseline,
                baselineWasMissing: false,
                previewThemeName: "Preview Theme"
            )
        )
        #expect(rolledBack.components(separatedBy: .newlines).filter { $0.hasPrefix("palette = ") }.count == 16)
        #expect(rolledBack.contains("palette = 0=#1d1f21"))
        #expect(rolledBack.contains("palette = 15=#1d1f21"))
        #expect(rolledBack.contains("theme = Old Theme"))
        #expect(rolledBack.contains("font-size = 14"))
    }

    @Test func applyingThemeToEmptyConfigAddsThemeLine() {
        let updated = SettingsController.configByApplyingTheme("YEN", to: "")
        #expect(updated == "theme = YEN")
    }

    @Test func applyingThemeReplacesThemeAndStripsExplicitColorKeys() {
        let input = [
            "# keep comment",
            "background = #000000",
            "theme = old_theme",
            "foreground = #ffffff",
            "font-size = 14",
        ].joined(separator: "\n")

        let updated = SettingsController.configByApplyingTheme("YEN", to: input)

        #expect(updated.contains("# keep comment"))
        #expect(updated.contains("theme = YEN"))
        #expect(updated.contains("font-size = 14"))
        #expect(!updated.contains("background ="))
        #expect(!updated.contains("foreground ="))
    }

    @Test func applyingThemeCollapsesDuplicateThemeLines() {
        let input = [
            "theme = old_theme",
            "font-size = 14",
            "theme = older_theme",
        ].joined(separator: "\n")

        let updated = SettingsController.configByApplyingTheme("YEN", to: input)
        let themeLines = updated.components(separatedBy: .newlines).filter {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("theme =")
        }

        #expect(themeLines.count == 1)
        #expect(themeLines.first == "theme = YEN")
        #expect(updated.contains("font-size = 14"))
    }

    @Test func applyingThemeStripsSearchAndBoldColorOverrides() {
        let input = [
            "search-background = #111111",
            "search-foreground = #fefefe",
            "search-selected-background = #222222",
            "search-selected-foreground = #fafafa",
            "bold-color = #ff00ff",
            "font-size = 14",
        ].joined(separator: "\n")

        let updated = SettingsController.configByApplyingTheme("YEN", to: input)

        #expect(!updated.contains("search-background ="))
        #expect(!updated.contains("search-foreground ="))
        #expect(!updated.contains("search-selected-background ="))
        #expect(!updated.contains("search-selected-foreground ="))
        #expect(!updated.contains("bold-color ="))
        #expect(updated.contains("font-size = 14"))
        #expect(updated.contains("theme = YEN"))
    }

    @Test func applyingThemeTreatsManagedKeysCaseSensitively() {
        let input = [
            "# keep comment",
            "THEME = Upper Theme",
            "BACKGROUND = #101010",
            "theme = old-theme",
            "background = #000000",
            "font-size = 14",
        ].joined(separator: "\n")

        let updated = SettingsController.configByApplyingTheme("YEN", to: input)
        let lines = updated.components(separatedBy: .newlines)

        #expect(lines.contains("# keep comment"))
        #expect(lines.contains("THEME = Upper Theme"))
        #expect(lines.contains("BACKGROUND = #101010"))
        #expect(lines.contains("theme = YEN"))
        #expect(!lines.contains("theme = old-theme"))
        #expect(!lines.contains("background = #000000"))
        #expect(lines.contains("font-size = 14"))
    }

    @Test func themePreviewConfigSnapshotTreatsMissingConfigAsEmpty() throws {
        let snapshot = try SettingsController.themePreviewConfigSnapshot(
            fileExists: { false },
            readContents: {
                throw CocoaError(.fileReadNoSuchFile)
            }
        )

        #expect(snapshot == SettingsController.ThemePreviewConfigSnapshot(contents: "", wasMissing: true))
    }

    @Test func themePreviewConfigSnapshotReadsExistingConfig() throws {
        let snapshot = try SettingsController.themePreviewConfigSnapshot(
            fileExists: { true },
            readContents: {
                "font-size = 14\ntheme = YEN\n"
            }
        )

        #expect(
            snapshot == SettingsController.ThemePreviewConfigSnapshot(
                contents: "font-size = 14\ntheme = YEN\n",
                wasMissing: false
            )
        )
    }

    @Test func themePreviewConfigSnapshotFailsClosedForUnreadableExistingConfig() {
        do {
            _ = try SettingsController.themePreviewConfigSnapshot(
                fileExists: { true },
                readContents: {
                    throw NSError(
                        domain: NSCocoaErrorDomain,
                        code: CocoaError.fileReadNoPermission.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "fixture permission denied"]
                    )
                }
            )
            Issue.record("Expected unreadable existing config to fail closed")
        } catch let error as SettingsController.ThemePreviewConfigReadError {
            #expect(error == .unreadableExistingConfig("fixture permission denied"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func applyingKeyOverridesCanSetAndRemoveMultipleKeys() {
        let input = [
            "theme = old-theme",
            "background-image = /tmp/old.jpg",
            "background-image-fit = contain",
            "font-size = 14",
        ].joined(separator: "\n")

        let updated = SettingsController.configByApplyingKeyOverrides(
            [
                ("theme", "custom-theme"),
                ("background-image", "\"/Users/test/wallpapers/bg.jpg\""),
                ("background-image-fit", "cover"),
                ("background-image-repeat", "false"),
            ],
            to: input
        )

        #expect(updated.contains("theme = custom-theme"))
        #expect(updated.contains("background-image = \"/Users/test/wallpapers/bg.jpg\""))
        #expect(updated.contains("background-image-fit = cover"))
        #expect(updated.contains("background-image-repeat = false"))
        #expect(updated.contains("font-size = 14"))
    }

    @Test func applyingKeyOverridesRemovesKeysWhenValueIsNil() {
        let input = [
            "theme = custom-theme",
            "background-image = \"/Users/test/wallpapers/bg.jpg\"",
            "background-image-fit = cover",
            "font-size = 14",
        ].joined(separator: "\n")

        let updated = SettingsController.configByApplyingKeyOverrides(
            [
                ("theme", "YEN"),
                ("background-image", nil),
                ("background-image-fit", nil),
            ],
            to: input
        )

        #expect(updated.contains("theme = YEN"))
        #expect(!updated.contains("background-image ="))
        #expect(!updated.contains("background-image-fit ="))
        #expect(updated.contains("font-size = 14"))
    }

    @Test func parseConfigLineRejectsAdvancedTriggerSyntax() {
        #expect(KeybindRegistry.parseConfigLine("super+d=new_split:right") != nil)
        #expect(KeybindRegistry.parseConfigLine("global:ctrl+backquote=toggle_quick_terminal") == nil)
        #expect(KeybindRegistry.parseConfigLine("work/super+d=new_split:right") == nil)
        #expect(KeybindRegistry.parseConfigLine("super+d>n=new_split:right") == nil)
    }

    @Test func parseConfigLinePreservesLiteralEqualsShortcutKeys() {
        let equalize = KeybindRegistry.parseConfigLine("super+=equalize_splits")
        #expect(equalize?.trigger == KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "equal"))
        #expect(equalize?.action == "equalize_splits")

        let increaseFont = KeybindRegistry.parseConfigLine("super+=increase_font_size:1")
        #expect(increaseFont?.trigger == KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "equal"))
        #expect(increaseFont?.action == "increase_font_size:1")
    }

    @Test func parseConfigLinePreservesLiteralPlusShortcutKeys() {
        let increaseFont = KeybindRegistry.parseConfigLine("super++=increase_font_size:1")
        #expect(increaseFont?.trigger == KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "plus"))
        #expect(increaseFont?.action == "increase_font_size:1")
    }

    @Test func parseConfigLineNormalizesTriggerCaseButPreservesActionCase() throws {
        let parsed = try #require(KeybindRegistry.parseConfigLine("SUPER+L=MixedCase_Action:Value"))

        #expect(parsed.trigger == KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "l"))
        #expect(parsed.action == "MixedCase_Action:Value")
    }

    @Test func parseTriggerNormalizesPunctuationAliases() {
        #expect(KeybindRegistry.parseTrigger("super+'")?.key == "apostrophe")
        #expect(KeybindRegistry.parseTrigger("super+quote")?.key == "apostrophe")
        #expect(KeybindRegistry.parseTrigger("super+/")?.key == "slash")
        #expect(KeybindRegistry.parseTrigger("super+[")?.key == "left_bracket")
        #expect(KeybindRegistry.parseTrigger("super+\\")?.key == "backslash")
    }

    @Test func parseTriggerNormalizesArrowGlyphAliases() {
        #expect(KeybindRegistry.parseTrigger("super+←")?.key == "left")
        #expect(KeybindRegistry.parseTrigger("super+→")?.key == "right")
        #expect(KeybindRegistry.parseTrigger("super+↑")?.key == "up")
        #expect(KeybindRegistry.parseTrigger("super+↓")?.key == "down")
    }

    @Test func parseTriggerAcceptsLiteralPlusKey() {
        #expect(KeybindRegistry.parseTrigger("super++")?.key == "plus")
    }

    @Test func parseTriggerAcceptsSingleUnicodeLayoutCharacters() {
        #expect(
            KeybindRegistry.parseTrigger("super+é")
            == KeyTrigger(modifiers: KeyModifiers(cmd: true), key: "é")
        )
    }

    @Test func fallbackSymbolKeyRoundTripsThroughConfigString() {
        let descriptor = KeybindRegistry.keyDescriptor(
            forKeyCode: 200,
            translatedCharacters: nil,
            displayCharacters: "+"
        )
        let key = descriptor.key
        #expect(key == "plus")

        let trigger = KeyTrigger(modifiers: KeyModifiers(cmd: true), key: key)
        #expect(trigger.configString == "super+plus")
        #expect(KeybindRegistry.parseTrigger(trigger.configString) == trigger)
    }

    @Test func mergingKeybindOverridesRemovesAdvancedManagedActionLines() {
        var entries = KeybindRegistry.defaults
        let targetIndex = entries.firstIndex {
            $0.action == "new_split:right" && $0.isEditable
        }
        #expect(targetIndex != nil)
        guard let targetIndex else { return }

        entries[targetIndex].currentTrigger = KeyTrigger(
            modifiers: KeyModifiers(cmd: true),
            key: "y"
        )
        entries[targetIndex].isUserOverride = true

        let lines = [
            "keybind = global:ctrl+f=new_split:right",
            "keybind = work/super+d=new_split:right",
            "keybind = super+d>n=new_split:right",
            "keybind = global:ctrl+backquote=toggle_visual_bell",
        ]

        let merged = KeybindConfigMerger.mergingKeybindOverrides(into: lines, entries: entries)
        let managedActionLines = merged.filter { $0.contains("=new_split:right") }

        #expect(managedActionLines.count == 1)
        #expect(managedActionLines.first == "keybind = super+y=new_split:right")
        #expect(merged.contains("keybind = global:ctrl+backquote=toggle_visual_bell"))
    }

    @Test func mergingKeybindOverridesSkipsInvalidTriggerPolicies() {
        var entries = KeybindRegistry.defaults
        let targetIndex = entries.firstIndex {
            $0.action == "new_split:right" && $0.isEditable
        }
        #expect(targetIndex != nil)
        guard let targetIndex else { return }

        entries[targetIndex].currentTrigger = KeyTrigger(
            modifiers: KeyModifiers(shift: true),
            key: "g"
        )
        entries[targetIndex].isUserOverride = true
        var merged = KeybindConfigMerger.mergingKeybindOverrides(into: [], entries: entries)
        #expect(!merged.contains(where: { $0.contains("=new_split:right") }))

        entries[targetIndex].currentTrigger = KeyTrigger(
            modifiers: KeyModifiers(cmd: true, shift: true),
            key: "j"
        )
        entries[targetIndex].isUserOverride = true
        merged = KeybindConfigMerger.mergingKeybindOverrides(into: [], entries: entries)
        #expect(!merged.contains(where: { $0.contains("=new_split:right") }))
    }

    // MARK: - Additional configByApplyingKeyOverrides Tests

    @Test func applyingKeyOverridesWithEmptyOverridesArray() {
        let input = [
            "theme = old-theme",
            "font-size = 14",
        ].joined(separator: "\n")

        let updated = SettingsController.configByApplyingKeyOverrides([], to: input)

        #expect(updated.contains("theme = old-theme"))
        #expect(updated.contains("font-size = 14"))
    }

    @Test func applyingKeyOverridesWithAllNilValues() {
        let input = [
            "theme = old-theme",
            "background-image = /tmp/old.jpg",
            "font-size = 14",
        ].joined(separator: "\n")

        let updated = SettingsController.configByApplyingKeyOverrides(
            [
                ("theme", nil),
                ("background-image", nil),
            ],
            to: input
        )

        #expect(!updated.contains("theme ="))
        #expect(!updated.contains("background-image ="))
        #expect(updated.contains("font-size = 14"))
    }

    @Test func applyingKeyOverridesWithDuplicateKeyLastValueWins() {
        let input = [
            "theme = old-theme",
            "font-size = 14",
        ].joined(separator: "\n")

        let updated = SettingsController.configByApplyingKeyOverrides(
            [
                ("theme", "first-theme"),
                ("theme", "second-theme"),
                ("theme", "final-theme"),
            ],
            to: input
        )

        let themeLines = updated.components(separatedBy: .newlines).filter { $0.contains("theme =") }
        #expect(themeLines.count == 1)
        #expect(themeLines.first == "theme = final-theme")
    }

    @Test func applyingKeyOverridesOnEmptyConfig() {
        let updated = SettingsController.configByApplyingKeyOverrides(
            [
                ("theme", "new-theme"),
                ("font-size", "16"),
                ("background-image", nil),
            ],
            to: ""
        )

        #expect(updated.contains("theme = new-theme"))
        #expect(updated.contains("font-size = 16"))
        #expect(!updated.contains("background-image"))
    }

    @Test func applyingKeyOverridesTreatsManagedKeysCaseSensitively() {
        let input = [
            "THEME = Upper Theme",
            "theme = old-theme",
            "BACKGROUND-IMAGE = /tmp/upper.jpg",
            "background-image = /tmp/lower.jpg",
            "font-size = 14",
        ].joined(separator: "\n")

        let updated = SettingsController.configByApplyingKeyOverrides(
            [
                ("theme", "new-theme"),
                ("background-image", nil),
            ],
            to: input
        )
        let lines = updated.components(separatedBy: .newlines)

        #expect(lines.contains("THEME = Upper Theme"))
        #expect(lines.contains("theme = new-theme"))
        #expect(lines.contains("BACKGROUND-IMAGE = /tmp/upper.jpg"))
        #expect(!lines.contains("background-image = /tmp/lower.jpg"))
        #expect(lines.contains("font-size = 14"))
    }

    @Test func dictationTranslationIdentifierNormalizationFallsBackOnEmptyInput() {
        let normalized = SettingsController.normalizeDictationTranslationIdentifier("")
        #expect(!normalized.isEmpty)
    }

    @Test func validatedDictationTargetKeepsSupportedSelection() {
        let validated = SettingsController.validatedDictationTargetIdentifier(
            currentIdentifier: "es",
            supportedIdentifiers: ["en", "es", "fr"],
            preferredIdentifier: "en"
        )
        #expect(validated == "es")
    }

    @Test func validatedDictationTargetFallsBackToPreferredOrFirstSupported() {
        let preferredMatch = SettingsController.validatedDictationTargetIdentifier(
            currentIdentifier: "xx",
            supportedIdentifiers: ["en", "fr"],
            preferredIdentifier: "fr"
        )
        #expect(preferredMatch == "fr")

        let fallbackFirst = SettingsController.validatedDictationTargetIdentifier(
            currentIdentifier: "xx",
            supportedIdentifiers: ["en", "fr"],
            preferredIdentifier: "zz"
        )
        #expect(fallbackFirst == "en")
    }

    @Test func backgroundOpacityConfigParsingClampsRange() {
        let controller = SettingsController.shared
        let originalBackgroundOpacity = controller.backgroundOpacity
        defer {
            controller.backgroundOpacity = originalBackgroundOpacity
        }

        controller.applyConfigContentsForTesting(
            """
            background-opacity = 5
            """
        )

        #expect(controller.backgroundOpacity == 1.0)

        controller.applyConfigContentsForTesting(
            """
            background-opacity = 0.05
            """
        )

        #expect(controller.backgroundOpacity == 0.1)
    }

    @Test func backgroundOpacityParsingFallsBackForMalformedAndNonFiniteValues() {
        let controller = SettingsController.shared
        let originalBackgroundOpacity = controller.backgroundOpacity
        defer {
            controller.backgroundOpacity = originalBackgroundOpacity
        }

        controller.backgroundOpacity = 0.42

        controller.applyConfigContentsForTesting(
            """
            background-opacity = abc
            """
        )

        #expect(controller.backgroundOpacity == 1.0)

        controller.backgroundOpacity = 0.42

        controller.applyConfigContentsForTesting(
            """
            background-opacity = nan
            """
        )

        #expect(controller.backgroundOpacity == 1.0)
    }

    @Test func applyConfigContentsKeepsKeysCaseSensitiveButNormalizesSupportedValueCases() throws {
        TestExclusiveLock.withLock(named: "settings-config-parser") {
            let controller = SettingsController.shared
            let originalFontSize = controller.fontSize
            let originalCursorStyle = controller.cursorStyle
            let originalCursorBlink = controller.cursorBlink
            let originalCopyOnSelect = controller.copyOnSelect
            let originalScrollbarVisibility = controller.scrollbarVisibility
            let originalNotifyOnCommandFinish = controller.notifyOnCommandFinish
            let originalNotifyOnCommandFinishActionBell = controller.notifyOnCommandFinishActionBell
            let originalNotifyOnCommandFinishActionNotify = controller.notifyOnCommandFinishActionNotify
            let originalSelectedTheme = controller.selectedTheme
            defer {
                controller.fontSize = originalFontSize
                controller.cursorStyle = originalCursorStyle
                controller.cursorBlink = originalCursorBlink
                controller.copyOnSelect = originalCopyOnSelect
                controller.scrollbarVisibility = originalScrollbarVisibility
                controller.notifyOnCommandFinish = originalNotifyOnCommandFinish
                controller.notifyOnCommandFinishActionBell = originalNotifyOnCommandFinishActionBell
                controller.notifyOnCommandFinishActionNotify = originalNotifyOnCommandFinishActionNotify
                controller.selectedTheme = originalSelectedTheme
            }

            controller.applyConfigContentsForTesting(
                """
                FONT-SIZE = 20
                CURSOR-STYLE = underline
                COPY-ON-SELECT = false
                NOTIFY-ON-COMMAND-FINISH = always
                THEME = Upper Theme
                """
            )

            #expect(controller.fontSize == 14)
            #expect(controller.cursorStyle == "block")
            #expect(controller.copyOnSelect)
            #expect(controller.notifyOnCommandFinish == "never")
            #expect(controller.selectedTheme.isEmpty)

            controller.applyConfigContentsForTesting(
                """
                font-size = 20
                cursor-style = BAR
                cursor-style-blink = FALSE
                copy-on-select = CLIPBOARD
                scrollbar = NEVER
                notify-on-command-finish = UnFocused
                notify-on-command-finish-action = NO-BELL,NOTIFY
                theme = "Mixed Case Theme"
                """
            )

            #expect(controller.fontSize == 20)
            #expect(controller.cursorStyle == "bar")
            #expect(!controller.cursorBlink)
            #expect(controller.copyOnSelect)
            #expect(controller.scrollbarVisibility == "never")
            #expect(controller.notifyOnCommandFinish == "unfocused")
            #expect(!controller.notifyOnCommandFinishActionBell)
            #expect(controller.notifyOnCommandFinishActionNotify)
            #expect(controller.selectedTheme == "Mixed Case Theme")
        }
    }

    @Test func managedConfigMergePreservesCommentsBlankLinesAndCaseSensitiveUnknownKeys() throws {
        TestExclusiveLock.withLock(named: "settings-config-parser") {
            let controller = SettingsController.shared
            let originalFontSize = controller.fontSize
            let originalBackgroundOpacity = controller.backgroundOpacity
            let originalSelectedTheme = controller.selectedTheme
            let originalBackgroundImagePath = controller.backgroundImagePath
            defer {
                controller.fontSize = originalFontSize
                controller.backgroundOpacity = originalBackgroundOpacity
                controller.selectedTheme = originalSelectedTheme
                controller.backgroundImagePath = originalBackgroundImagePath
            }

            controller.fontSize = 18
            controller.backgroundOpacity = 0.65
            controller.selectedTheme = ""
            controller.backgroundImagePath = ""

            let merged = controller.mergedManagedConfigForTesting(
                existingContents: [
                    "# keep top",
                    "",
                    "FONT-SIZE = 99",
                    "font-size = 12",
                    "custom-key = keep",
                    "  # keep indented",
                    "",
                ].joined(separator: "\n")
            )
            let lines = merged.components(separatedBy: .newlines)

            #expect(
                Array(lines.prefix(7)) == [
                    "# keep top",
                    "",
                    "FONT-SIZE = 99",
                    "font-size = 18",
                    "custom-key = keep",
                    "  # keep indented",
                    "",
                ]
            )
            #expect(lines.contains("FONT-SIZE = 99"))
            #expect(lines.contains("font-size = 18"))
            #expect(lines.contains("custom-key = keep"))
            #expect(lines.contains("  # keep indented"))
            #expect(lines.contains("background-opacity = 0.65"))
        }
    }

    @Test func configEntryHelpersPreserveNarrowLineParsingSemantics() {
        let entry = SettingsController.configEntryForTesting("  theme = Mixed=Case Theme  ")
        #expect(entry?.key == "theme")
        #expect(entry?.value == "Mixed=Case Theme")

        let uppercaseEntry = SettingsController.configEntryForTesting("  THEME = Upper Theme  ")
        #expect(uppercaseEntry?.key == "THEME")
        #expect(uppercaseEntry?.value == "Upper Theme")

        #expect(SettingsController.configEntryForTesting("") == nil)
        #expect(SettingsController.configEntryForTesting("   # comment = ignored") == nil)
        #expect(SettingsController.configEntryForTesting("font-size") == nil)
        #expect(SettingsController.configEntryForTesting("font-size = ") == nil)
        #expect(SettingsController.configKeyForTesting("font-size") == "font-size")
        #expect(SettingsController.configKeyForTesting("  FONT-SIZE = 20") == "FONT-SIZE")
        #expect(SettingsController.configKeyForTesting("  # comment") == nil)
    }

    @Test func opacityManagedSettingsListIncludesFormattedBackgroundKeyOnly() {
        let controller = SettingsController.shared
        let originalBackgroundOpacity = controller.backgroundOpacity
        defer {
            controller.backgroundOpacity = originalBackgroundOpacity
        }

        controller.backgroundOpacity = 0.65
        let settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())

        #expect(settings["background-opacity"] == "0.65")
        #expect(settings["unfocused-split-opacity"] == nil)
    }

    @Test func backgroundImageConfigParsingNormalizesQuotedPath() {
        let controller = SettingsController.shared
        let originalBackgroundImagePath = controller.backgroundImagePath
        defer {
            controller.backgroundImagePath = originalBackgroundImagePath
        }

        controller.applyConfigContentsForTesting(
            """
            background-image = "/Users/test/Pictures/space bg.png"
            """
        )

        #expect(controller.backgroundImagePath == "/Users/test/Pictures/space bg.png")
    }

    @Test func backgroundImageManagedSettingsListWritesQuotedPathAndFixedRenderingDefaults() {
        let controller = SettingsController.shared
        let originalBackgroundImagePath = controller.backgroundImagePath
        let originalBackgroundImageScope = controller.backgroundImageScope
        defer {
            controller.backgroundImagePath = originalBackgroundImagePath
            controller.backgroundImageScope = originalBackgroundImageScope
        }

        controller.backgroundImagePath =
            "/Users/test/Library/Application Support/com.yenchat.yen/backgrounds/terminal-background-demo.png"
        controller.backgroundImageScope = .wholeWindow

        let settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(
            settings["background-image"]
                == "\"/Users/test/Library/Application Support/com.yenchat.yen/backgrounds/terminal-background-demo.png\""
        )
        #expect(settings["background-image-fit"] == "cover")
        #expect(settings["background-image-opacity"] == "1.0")
        #expect(settings["background-image-repeat"] == "false")
    }

    @Test func wholeWindowBackgroundRuntimeConfigSuppressesDuplicateSurfaceWallpaper() {
        let controller = SettingsController.shared
        let originalBackgroundImagePath = controller.backgroundImagePath
        let originalBackgroundImageScope = controller.backgroundImageScope
        let originalBackgroundOpacity = controller.backgroundOpacity
        defer {
            controller.backgroundImagePath = originalBackgroundImagePath
            controller.backgroundImageScope = originalBackgroundImageScope
            controller.backgroundOpacity = originalBackgroundOpacity
        }

        controller.backgroundImagePath =
            "/Users/test/Library/Application Support/com.yenchat.yen/backgrounds/terminal-background-demo.png"
        controller.backgroundImageScope = .wholeWindow
        controller.backgroundOpacity = 0.65

        let runtimeConfig = controller.wholeWindowBackgroundRuntimeConfigContentsForTesting()

        #expect(
            runtimeConfig.contains(
                "background-image = \"/Users/test/Library/Application Support/com.yenchat.yen/backgrounds/terminal-background-demo.png\""
            )
        )
        #expect(runtimeConfig.contains("background-opacity = 0.0"))
        #expect(runtimeConfig.contains("background-image-opacity = 0.0"))
    }

    @Test func currentManagedSurfaceRuntimeConfigKeepsBackgroundImageVisible() throws {
        try TestExclusiveLock.withLock(named: "background-runtime-config") {
            let controller = SettingsController.shared
            let originalBackgroundImagePath = controller.backgroundImagePath
            let originalBackgroundImageScope = controller.backgroundImageScope
            let originalBackgroundOpacity = controller.backgroundOpacity
            let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("yen-surface-runtime-\(UUID().uuidString)", isDirectory: true)
            let configPath = tempRoot.appendingPathComponent("config.yen", isDirectory: false).path

            try FileManager.default.createDirectory(
                at: tempRoot,
                withIntermediateDirectories: true,
                attributes: nil
            )
            SettingsController._testSetConfigPathOverride(configPath)
            defer {
                controller.backgroundImagePath = originalBackgroundImagePath
                controller.backgroundImageScope = originalBackgroundImageScope
                controller.backgroundOpacity = originalBackgroundOpacity
                SettingsController._testSetConfigPathOverride(nil)
                try? FileManager.default.removeItem(at: tempRoot)
            }

            controller.applyConfigContentsForTesting(
                """
                background-opacity = 0.65
                background-image = "/Users/test/Library/Application Support/com.yenchat.yen/backgrounds/terminal-background-demo.png"
                """
            )
            controller.backgroundImageScope = .wholeWindow

            let surfaceConfig = controller.currentManagedSurfaceConfigContentsForTesting()

            #expect(
                surfaceConfig.contains(
                    "background-image = \"/Users/test/Library/Application Support/com.yenchat.yen/backgrounds/terminal-background-demo.png\""
                )
            )
            #expect(surfaceConfig.contains("background-opacity = 0.65"))
            #expect(surfaceConfig.contains("background-image-opacity = 1.0"))
            #expect(!surfaceConfig.contains("background-opacity = 0.0"))
            #expect(!surfaceConfig.contains("background-image-opacity = 0.0"))
        }
    }

    @Test func rewritingRuntimeConfigRestoresPerSurfaceWallpaperVisibility() throws {
        try TestExclusiveLock.withLock(named: "background-runtime-config") {
            let controller = SettingsController.shared
            let originalBackgroundImagePath = controller.backgroundImagePath
            let originalBackgroundImageScope = controller.backgroundImageScope
            let originalBackgroundOpacity = controller.backgroundOpacity
            let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("yen-runtime-rewrite-\(UUID().uuidString)", isDirectory: true)
            let configPath = tempRoot.appendingPathComponent("config.yen", isDirectory: false).path
            let expectedRuntimeConfigPath = tempRoot
                .appendingPathComponent(".yen-whole-window-background-runtime.yen", isDirectory: false)
                .path

            try FileManager.default.createDirectory(
                at: tempRoot,
                withIntermediateDirectories: true,
                attributes: nil
            )
            SettingsController._testSetConfigPathOverride(configPath)
            defer {
                controller.backgroundImagePath = originalBackgroundImagePath
                controller.backgroundImageScope = originalBackgroundImageScope
                controller.backgroundOpacity = originalBackgroundOpacity
                SettingsController._testSetConfigPathOverride(nil)
                try? FileManager.default.removeItem(at: tempRoot)
            }

            controller.applyConfigContentsForTesting(
                """
                background-opacity = 0.65
                background-image = "/Users/test/Library/Application Support/com.yenchat.yen/backgrounds/terminal-background-demo.png"
                """
            )
            controller.backgroundImageScope = .wholeWindow

            let wholeWindowRuntimeConfigPath = try controller.writeWholeWindowBackgroundRuntimeConfig()
            #expect(wholeWindowRuntimeConfigPath == expectedRuntimeConfigPath)

            var runtimeConfigContents = try String(
                contentsOfFile: wholeWindowRuntimeConfigPath,
                encoding: .utf8
            )
            #expect(runtimeConfigContents.contains("background-opacity = 0.0"))
            #expect(runtimeConfigContents.contains("background-image-opacity = 0.0"))

            let surfaceRuntimeConfigPath = try controller.writeCurrentManagedSurfaceConfig()
            #expect(surfaceRuntimeConfigPath == expectedRuntimeConfigPath)

            runtimeConfigContents = try String(
                contentsOfFile: surfaceRuntimeConfigPath,
                encoding: .utf8
            )
            #expect(runtimeConfigContents.contains("background-opacity = 0.65"))
            #expect(runtimeConfigContents.contains("background-image-opacity = 1.0"))
            #expect(!runtimeConfigContents.contains("background-image-opacity = 0.0"))
        }
    }

    @Test func backgroundImageManagedConfigMergeRemovesKeysWhenCleared() {
        let controller = SettingsController.shared
        let originalBackgroundImagePath = controller.backgroundImagePath
        defer {
            controller.backgroundImagePath = originalBackgroundImagePath
        }

        controller.backgroundImagePath = ""

        let merged = controller.mergedManagedConfigForTesting(
            existingContents: [
                "# keep comment",
                "background-image = \"/Users/test/Pictures/bg.png\"",
                "background-image-fit = contain",
                "background-image-opacity = 0.45",
                "background-image-position = center",
                "background-image-repeat = true",
                "font-size = 14",
            ].joined(separator: "\n")
        )

        #expect(!merged.contains("background-image ="))
        #expect(!merged.contains("background-image-fit ="))
        #expect(!merged.contains("background-image-opacity ="))
        #expect(!merged.contains("background-image-position ="))
        #expect(!merged.contains("background-image-repeat ="))
        #expect(merged.contains("font-size = 14"))
        #expect(merged.contains("# keep comment"))
    }

    @Test func backgroundImagePresentationWarnsForUnsupportedExistingFormats() throws {
        let controller = SettingsController.shared
        let originalBackgroundImagePath = controller.backgroundImagePath
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("yen-background-presentation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer {
            controller.backgroundImagePath = originalBackgroundImagePath
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let source = tempRoot.appendingPathComponent("background-source.tiff", isDirectory: false)
        let image = NSImage(size: NSSize(width: 12, height: 12))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 12, height: 12)).fill()
        image.unlockFocus()
        let tiffData = try #require(image.tiffRepresentation)
        try tiffData.write(to: source, options: .atomic)

        controller.backgroundImagePath = source.path

        #expect(controller.backgroundImagePreview != nil)
        #expect(controller.backgroundImageIssueDescription == "Unsupported format; use PNG or JPEG.")
    }

    @Test func copyOnSelectConfigParsingSupportsFalseTrueAndClipboard() {
        let controller = SettingsController.shared
        let originalCopyOnSelect = controller.copyOnSelect
        defer {
            controller.copyOnSelect = originalCopyOnSelect
        }

        controller.applyConfigContentsForTesting(
            """
            copy-on-select = false
            """
        )
        #expect(!controller.copyOnSelect)

        controller.applyConfigContentsForTesting(
            """
            copy-on-select = true
            """
        )
        #expect(controller.copyOnSelect)

        controller.applyConfigContentsForTesting(
            """
            copy-on-select = clipboard
            """
        )
        #expect(controller.copyOnSelect)
    }

    @Test func copyOnSelectManagedSettingsListWritesClipboardOrFalse() {
        let controller = SettingsController.shared
        let originalCopyOnSelect = controller.copyOnSelect
        defer {
            controller.copyOnSelect = originalCopyOnSelect
        }

        controller.copyOnSelect = false
        var settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(settings["copy-on-select"] == "false")

        controller.copyOnSelect = true
        settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(settings["copy-on-select"] == "both")
    }

    @Test func scrollbarConfigParsingSupportsSystemAndNever() {
        let controller = SettingsController.shared
        let originalScrollbarVisibility = controller.scrollbarVisibility
        defer {
            controller.scrollbarVisibility = originalScrollbarVisibility
        }

        controller.applyConfigContentsForTesting(
            """
            scrollbar = never
            """
        )
        #expect(controller.scrollbarVisibility == "never")

        controller.applyConfigContentsForTesting(
            """
            scrollbar = system
            """
        )
        #expect(controller.scrollbarVisibility == "system")

        controller.applyConfigContentsForTesting(
            """
            scrollbar = legacy
            """
        )
        #expect(controller.scrollbarVisibility == "system")
    }

    @Test func scrollbarManagedSettingsListWritesNormalizedValue() {
        let controller = SettingsController.shared
        let originalScrollbarVisibility = controller.scrollbarVisibility
        defer {
            controller.scrollbarVisibility = originalScrollbarVisibility
        }

        controller.scrollbarVisibility = "never"
        var settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(settings["scrollbar"] == "never")

        controller.scrollbarVisibility = "invalid"
        settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(settings["scrollbar"] == "system")
    }

    @Test func managedConfigMergeUsesCurrentValuesAndNormalizesLegacyScrollbar() {
        let controller = SettingsController.shared
        let originalScrollbarVisibility = controller.scrollbarVisibility
        let originalMode = controller.notifyOnCommandFinish
        let originalBell = controller.notifyOnCommandFinishActionBell
        let originalNotify = controller.notifyOnCommandFinishActionNotify
        let originalAfterSeconds = controller.notifyOnCommandFinishAfterSeconds
        defer {
            controller.scrollbarVisibility = originalScrollbarVisibility
            controller.notifyOnCommandFinish = originalMode
            controller.notifyOnCommandFinishActionBell = originalBell
            controller.notifyOnCommandFinishActionNotify = originalNotify
            controller.notifyOnCommandFinishAfterSeconds = originalAfterSeconds
        }

        controller.scrollbarVisibility = "system"
        controller.notifyOnCommandFinish = "always"
        controller.notifyOnCommandFinishActionBell = false
        controller.notifyOnCommandFinishActionNotify = true
        controller.notifyOnCommandFinishAfterSeconds = 42

        let exported = controller.mergedManagedConfigForTesting(
            existingContents: [
                "# keep comment",
                "scrollbar = legacy",
                "notify-on-command-finish = never",
                "notify-on-command-finish-action = bell,no-notify",
                "notify-on-command-finish-after = 5s",
                "custom-unknown = preserve",
            ].joined(separator: "\n")
        )

        #expect(exported.contains("# keep comment"))
        #expect(exported.contains("custom-unknown = preserve"))
        #expect(exported.contains("scrollbar = system"))
        #expect(!exported.contains("scrollbar = legacy"))
        #expect(exported.contains("notify-on-command-finish = always"))
        #expect(exported.contains("notify-on-command-finish-action = no-bell,notify"))
        #expect(exported.contains("notify-on-command-finish-after = 42s"))
    }

    @Test func commandFinishConfigParsingSupportsModeActionAndDuration() {
        let controller = SettingsController.shared
        let originalMode = controller.notifyOnCommandFinish
        let originalBell = controller.notifyOnCommandFinishActionBell
        let originalNotify = controller.notifyOnCommandFinishActionNotify
        let originalAfterSeconds = controller.notifyOnCommandFinishAfterSeconds
        defer {
            controller.notifyOnCommandFinish = originalMode
            controller.notifyOnCommandFinishActionBell = originalBell
            controller.notifyOnCommandFinishActionNotify = originalNotify
            controller.notifyOnCommandFinishAfterSeconds = originalAfterSeconds
        }

        controller.applyConfigContentsForTesting(
            """
            notify-on-command-finish = unfocused
            notify-on-command-finish-action = no-bell,notify
            notify-on-command-finish-after = 1m30s
            """
        )

        #expect(controller.notifyOnCommandFinish == "unfocused")
        #expect(!controller.notifyOnCommandFinishActionBell)
        #expect(controller.notifyOnCommandFinishActionNotify)
        #expect(controller.notifyOnCommandFinishAfterSeconds == 90)
    }

    @Test func commandFinishConfigParsingNormalizesModeWhitespaceAndCase() {
        let controller = SettingsController.shared
        let originalMode = controller.notifyOnCommandFinish
        defer {
            controller.notifyOnCommandFinish = originalMode
        }

        controller.applyConfigContentsForTesting(
            """
            notify-on-command-finish =   UnFocused
            """
        )

        #expect(controller.notifyOnCommandFinish == "unfocused")
    }

    @Test func commandFinishManagedSettingsListWritesNormalizedValues() {
        let controller = SettingsController.shared
        let originalMode = controller.notifyOnCommandFinish
        let originalBell = controller.notifyOnCommandFinishActionBell
        let originalNotify = controller.notifyOnCommandFinishActionNotify
        let originalAfterSeconds = controller.notifyOnCommandFinishAfterSeconds
        defer {
            controller.notifyOnCommandFinish = originalMode
            controller.notifyOnCommandFinishActionBell = originalBell
            controller.notifyOnCommandFinishActionNotify = originalNotify
            controller.notifyOnCommandFinishAfterSeconds = originalAfterSeconds
        }

        controller.notifyOnCommandFinish = "always"
        controller.notifyOnCommandFinishActionBell = false
        controller.notifyOnCommandFinishActionNotify = true
        controller.notifyOnCommandFinishAfterSeconds = 12

        let settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(settings["notify-on-command-finish"] == "always")
        #expect(settings["notify-on-command-finish-action"] == "no-bell,notify")
        #expect(settings["notify-on-command-finish-after"] == "12s")
    }

    @Test func commandFinishManagedSettingsListPreservesExtendedDurationSyntax() {
        let controller = SettingsController.shared
        let originalMode = controller.notifyOnCommandFinish
        let originalBell = controller.notifyOnCommandFinishActionBell
        let originalNotify = controller.notifyOnCommandFinishActionNotify
        let originalAfterSeconds = controller.notifyOnCommandFinishAfterSeconds
        defer {
            controller.notifyOnCommandFinish = originalMode
            controller.notifyOnCommandFinishActionBell = originalBell
            controller.notifyOnCommandFinishActionNotify = originalNotify
            controller.notifyOnCommandFinishAfterSeconds = originalAfterSeconds
        }

        controller.applyConfigContentsForTesting(
            """
            notify-on-command-finish = always
            notify-on-command-finish-after = 500ms
            """
        )

        var settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(controller.notifyOnCommandFinishAfterSeconds == 1)
        #expect(settings["notify-on-command-finish-after"] == "500ms")

        controller.applyConfigContentsForTesting(
            """
            notify-on-command-finish = always
            notify-on-command-finish-after = 1w
            """
        )

        settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(controller.notifyOnCommandFinishAfterSeconds == 604_800)
        #expect(settings["notify-on-command-finish-after"] == "1w")
    }

    @Test func commandFinishDelayDisplayTextHumanizesZeroAndPreservesExtendedSyntaxUntilRewrite() {
        let controller = SettingsController.shared
        let originalMode = controller.notifyOnCommandFinish
        let originalAfterSeconds = controller.notifyOnCommandFinishAfterSeconds
        defer {
            controller.notifyOnCommandFinish = originalMode
            controller.notifyOnCommandFinishAfterSeconds = originalAfterSeconds
        }

        controller.applyConfigContentsForTesting(
            """
            notify-on-command-finish = always
            notify-on-command-finish-after = 0
            """
        )

        var settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(controller.notifyOnCommandFinishAfterSeconds == 0)
        #expect(settings["notify-on-command-finish-after"] == "0")

        controller.applyConfigContentsForTesting(
            """
            notify-on-command-finish = always
            notify-on-command-finish-after = 500ms
            """
        )

        settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(controller.notifyOnCommandFinishAfterSeconds == 1)
        #expect(settings["notify-on-command-finish-after"] == "500ms")

        controller.notifyOnCommandFinishAfterSeconds = 2

        settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(settings["notify-on-command-finish-after"] == "2s")
    }

    @Test func commandFinishActionParsingPreservesIndependentBellAndSilentStates() {
        let controller = SettingsController.shared
        let originalBell = controller.notifyOnCommandFinishActionBell
        let originalNotify = controller.notifyOnCommandFinishActionNotify
        defer {
            controller.notifyOnCommandFinishActionBell = originalBell
            controller.notifyOnCommandFinishActionNotify = originalNotify
        }

        controller.applyConfigContentsForTesting(
            """
            notify-on-command-finish-action = bell,no-notify
            """
        )

        #expect(controller.notifyOnCommandFinishActionBell)
        #expect(!controller.notifyOnCommandFinishActionNotify)

        controller.applyConfigContentsForTesting(
            """
            notify-on-command-finish-action = no-bell,no-notify
            """
        )

        #expect(!controller.notifyOnCommandFinishActionBell)
        #expect(!controller.notifyOnCommandFinishActionNotify)

        let settings = Dictionary(uniqueKeysWithValues: controller.managedSettingsListForTesting())
        #expect(settings["notify-on-command-finish-action"] == "no-bell,no-notify")
    }

    @Test func opacityManagedConfigMergeRemainsStableAcrossRepeatedMerges() {
        let controller = SettingsController.shared
        let originalBackgroundOpacity = controller.backgroundOpacity
        defer {
            controller.backgroundOpacity = originalBackgroundOpacity
        }

        controller.backgroundOpacity = 0.62

        let existing = [
            "# keep comment",
            "background-opacity = 0.55",
            "unfocused-split-opacity = 0.88",
            "custom-unknown = preserve",
        ].joined(separator: "\n")

        let mergedOnce = controller.mergedManagedConfigForTesting(existingContents: existing)
        let mergedTwice = controller.mergedManagedConfigForTesting(existingContents: mergedOnce)
        let lines = mergedTwice.components(separatedBy: .newlines)

        let backgroundLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("background-opacity =") }
        let splitLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("unfocused-split-opacity =") }

        #expect(backgroundLines.count == 1)
        #expect(splitLines.isEmpty)
        #expect(mergedTwice.contains("background-opacity = 0.60"))
        #expect(!mergedTwice.contains("unfocused-split-opacity ="))
        #expect(mergedTwice.contains("custom-unknown = preserve"))
        #expect(mergedTwice.contains("# keep comment"))
    }

    @Test func applyConfigContentsResetsRemovedManagedKeysToDefaults() {
        let controller = SettingsController.shared
        let originalFontFamily = controller.fontFamily
        let originalFontSize = controller.fontSize
        let originalCursorStyle = controller.cursorStyle
        let originalCursorBlink = controller.cursorBlink
        let originalCopyOnSelect = controller.copyOnSelect
        let originalScrollbarVisibility = controller.scrollbarVisibility
        let originalNotifyOnCommandFinish = controller.notifyOnCommandFinish
        let originalNotifyOnCommandFinishActionBell = controller.notifyOnCommandFinishActionBell
        let originalNotifyOnCommandFinishActionNotify = controller.notifyOnCommandFinishActionNotify
        let originalNotifyOnCommandFinishAfterSeconds = controller.notifyOnCommandFinishAfterSeconds
        let originalTheme = controller.selectedTheme
        let originalBackgroundImagePath = controller.backgroundImagePath
        let originalWindowPaddingX = controller.windowPaddingX
        let originalWindowPaddingY = controller.windowPaddingY
        defer {
            controller.fontFamily = originalFontFamily
            controller.fontSize = originalFontSize
            controller.cursorStyle = originalCursorStyle
            controller.cursorBlink = originalCursorBlink
            controller.copyOnSelect = originalCopyOnSelect
            controller.scrollbarVisibility = originalScrollbarVisibility
            controller.notifyOnCommandFinish = originalNotifyOnCommandFinish
            controller.notifyOnCommandFinishActionBell = originalNotifyOnCommandFinishActionBell
            controller.notifyOnCommandFinishActionNotify = originalNotifyOnCommandFinishActionNotify
            controller.notifyOnCommandFinishAfterSeconds = originalNotifyOnCommandFinishAfterSeconds
            controller.selectedTheme = originalTheme
            controller.backgroundImagePath = originalBackgroundImagePath
            controller.windowPaddingX = originalWindowPaddingX
            controller.windowPaddingY = originalWindowPaddingY
        }

        controller.fontFamily = "Menlo"
        controller.cursorStyle = "underline"
        controller.cursorBlink = false
        controller.copyOnSelect = false
        controller.scrollbarVisibility = "never"
        controller.notifyOnCommandFinish = "always"
        controller.notifyOnCommandFinishActionBell = false
        controller.notifyOnCommandFinishActionNotify = true
        controller.notifyOnCommandFinishAfterSeconds = 42
        controller.selectedTheme = "Custom Theme"
        controller.backgroundImagePath = "/Users/test/Pictures/bg.png"
        controller.windowPaddingX = 17
        controller.windowPaddingY = 19

        controller.applyConfigContentsForTesting(
            """
            font-size = 18
            """
        )

        #expect(controller.fontFamily == "JetBrains Mono")
        #expect(controller.fontSize == 18)
        #expect(controller.cursorStyle == "block")
        #expect(controller.cursorBlink)
        #expect(controller.copyOnSelect)
        #expect(controller.scrollbarVisibility == "system")
        #expect(controller.notifyOnCommandFinish == "never")
        #expect(controller.notifyOnCommandFinishActionBell)
        #expect(!controller.notifyOnCommandFinishActionNotify)
        #expect(controller.notifyOnCommandFinishAfterSeconds == 5)
        #expect(controller.selectedTheme.isEmpty)
        #expect(controller.backgroundImagePath.isEmpty)
        #expect(controller.windowPaddingX == 2)
        #expect(controller.windowPaddingY == 2)
    }

    @Test func previewRollbackRespectsExternalThemeEdits() {
        let baseline = [
            "theme = nord",
            "background = #111111",
            "foreground = #eeeeee",
            "font-size = 14",
        ].joined(separator: "\n")
        let current = [
            "theme = catppuccin",
            "font-size = 16",
            "background = #222222",
        ].joined(separator: "\n")

        let rolledBack = SettingsController.configByRollingBackThemePreview(
            currentContents: current,
            baselineContents: baseline,
            baselineWasMissing: false,
            previewThemeName: "YEN"
        )

        #expect(rolledBack == current)
    }

    @Test func previewRollbackTreatsUppercaseThemeKeyAsUnmanagedExternalEdit() {
        let baseline = [
            "theme = nord",
            "background = #111111",
            "foreground = #eeeeee",
            "font-size = 14",
        ].joined(separator: "\n")
        let current = [
            "THEME = YEN",
            "font-size = 16",
            "background = #222222",
        ].joined(separator: "\n")

        let rolledBack = SettingsController.configByRollingBackThemePreview(
            currentContents: current,
            baselineContents: baseline,
            baselineWasMissing: false,
            previewThemeName: "YEN"
        )

        #expect(rolledBack == current)
    }

    @Test func previewRollbackRestoresBaselineWhenPreviewThemeStillActive() {
        let baseline = [
            "theme = nord",
            "background = #111111",
            "foreground = #eeeeee",
            "font-size = 14",
        ].joined(separator: "\n")
        let current = [
            "theme = YEN",
            "font-size = 16",
        ].joined(separator: "\n")

        let rolledBack = SettingsController.configByRollingBackThemePreview(
            currentContents: current,
            baselineContents: baseline,
            baselineWasMissing: false,
            previewThemeName: "YEN"
        )

        #expect(rolledBack?.contains("theme = nord") == true)
        #expect(rolledBack?.contains("background = #111111") == true)
        #expect(rolledBack?.contains("foreground = #eeeeee") == true)
        #expect(rolledBack?.contains("font-size = 16") == true)
    }

    // MARK: - ManagedConfigDocument (pure merge algorithm, no controller/disk)

    @Test func managedDocumentPreservesCommentsAndUnknownKeysWhileReplacingManagedValue() {
        let doc = ManagedConfigDocument(
            settings: [ManagedConfigDocument.Entry(key: "font-size", value: "16")],
            hasSelectedTheme: false,
            hasBackgroundImage: false
        )
        let merged = doc.merged(intoExistingLines: [
            "# user comment",
            "",
            "font-size = 12",
            "custom-unmanaged = keep-me",
        ])
        #expect(merged == [
            "# user comment",
            "",
            "font-size = 16",
            "custom-unmanaged = keep-me",
        ])
    }

    @Test func managedDocumentAppendsMissingManagedKeys() {
        let doc = ManagedConfigDocument(
            settings: [
                ManagedConfigDocument.Entry(key: "font-size", value: "16"),
                ManagedConfigDocument.Entry(key: "cursor-style", value: "block"),
            ],
            hasSelectedTheme: false,
            hasBackgroundImage: false
        )
        let merged = doc.merged(intoExistingLines: ["font-size = 12"])
        #expect(merged == ["font-size = 16", "cursor-style = block"])
    }

    @Test func managedDocumentDropsBackgroundImageKeysWhenNoImageSet() {
        let doc = ManagedConfigDocument(
            settings: [],
            hasSelectedTheme: false,
            hasBackgroundImage: false
        )
        let merged = doc.merged(intoExistingLines: [
            "background-image = /tmp/x.png",
            "background-image-opacity = 0.5",
            "font-size = 12",
        ])
        #expect(merged == ["font-size = 12"])
    }

    @Test func managedDocumentKeepsBackgroundImageKeysWhenImageSet() {
        let doc = ManagedConfigDocument(
            settings: [],
            hasSelectedTheme: false,
            hasBackgroundImage: true
        )
        let merged = doc.merged(intoExistingLines: [
            "background-image = /tmp/x.png",
            "font-size = 12",
        ])
        #expect(merged == ["background-image = /tmp/x.png", "font-size = 12"])
    }

    @Test func managedDocumentStripsThemeColorKeysWhenThemeSelected() {
        let doc = ManagedConfigDocument(
            settings: [],
            hasSelectedTheme: true,
            hasBackgroundImage: false
        )
        let merged = doc.merged(intoExistingLines: [
            "background = #000000",
            "palette = 0=#111111",
            "font-size = 12",
        ])
        #expect(merged == ["font-size = 12"])
    }

    @Test func managedDocumentKeepsThemeColorKeysWhenNoThemeSelected() {
        let doc = ManagedConfigDocument(
            settings: [],
            hasSelectedTheme: false,
            hasBackgroundImage: false
        )
        let merged = doc.merged(intoExistingLines: ["background = #000000"])
        #expect(merged == ["background = #000000"])
    }

    @Test func managedDocumentDoesNotDedupRepeatableKeybindLines() {
        let doc = ManagedConfigDocument(
            settings: [],
            hasSelectedTheme: false,
            hasBackgroundImage: false
        )
        let existing = [
            "keybind = cmd+a=select_all",
            "keybind = cmd+b=toggle_bold",
        ]
        #expect(doc.merged(intoExistingLines: existing) == existing)
    }

    @Test func managedDocumentDropsLegacyTabSidebarAndSplitOpacityKeys() {
        let doc = ManagedConfigDocument(
            settings: [],
            hasSelectedTheme: false,
            hasBackgroundImage: false
        )
        let merged = doc.merged(intoExistingLines: [
            "tab-sidebar-enabled = true",
            "unfocused-split-opacity = 0.7",
            "font-size = 12",
        ])
        #expect(merged == ["font-size = 12"])
    }

    // Every write emits the whole managed list. A hand-written value that the
    // panel only normalized on load must survive an unrelated edit, and must
    // still be replaced when the panel changes that setting or resets it.

    @Test func unrelatedEditKeepsHandWrittenManagedValuesVerbatim() throws {
        let controller = SettingsController.shared
        let fixture = try makeRawPreservationFixture(controller)
        defer { fixture.restore() }

        #expect(controller.fontSize == 14)
        #expect(controller.windowPaddingX == 2)
        #expect(controller.cursorStyle == "block")

        controller.cursorBlink.toggle()
        let written = controller.currentManagedSurfaceConfigContentsForTesting()

        #expect(written.contains("font-size = 13.5"))
        #expect(written.contains("window-padding-x = 2,4"))
        #expect(written.contains("cursor-style = block_hollow"))
        #expect(written.contains("background-opacity = 0.93"))
        #expect(written.contains("cursor-style-blink = \(controller.cursorBlink ? "true" : "false")"))
        #expect(written.contains("# hand-written"))
        // A forced constant is not a preserved value.
        #expect(written.contains("window-save-state = always"))
        #expect(!written.contains("window-save-state = never"))
    }

    @Test func editingASettingReplacesItsHandWrittenValue() throws {
        let controller = SettingsController.shared
        let fixture = try makeRawPreservationFixture(controller)
        defer { fixture.restore() }

        controller.fontSize = 16
        let written = controller.currentManagedSurfaceConfigContentsForTesting()

        #expect(written.contains("font-size = 16"))
        #expect(!written.contains("font-size = 13.5"))
        #expect(written.contains("window-padding-x = 2,4"))
    }

    @Test func aRepeatedManagedKeyIsNotPreserved() throws {
        let controller = SettingsController.shared
        let fixture = try makeRawPreservationFixture(
            controller,
            contents: "font-size = 12.5\nfont-size = 13.5\n"
        )
        defer { fixture.restore() }

        controller.cursorBlink.toggle()
        let written = controller.currentManagedSurfaceConfigContentsForTesting()
        let fontSizeLines = written.components(separatedBy: .newlines)
            .filter { $0.hasPrefix("font-size =") }

        #expect(fontSizeLines == ["font-size = 14"])
    }

    private struct RawPreservationFixture {
        let contents: String
        let restore: () -> Void
    }

    private func makeRawPreservationFixture(
        _ controller: SettingsController,
        contents: String = [
            "# hand-written",
            "font-size = 13.5",
            "window-padding-x = 2,4",
            "cursor-style = block_hollow",
            "window-save-state = never",
            "background-opacity = 0.93",
            "",
        ].joined(separator: "\n")
    ) throws -> RawPreservationFixture {
        let originalFontSize = controller.fontSize
        let originalPaddingX = controller.windowPaddingX
        let originalCursorStyle = controller.cursorStyle
        let originalCursorBlink = controller.cursorBlink
        let originalOpacity = controller.backgroundOpacity
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("yen-raw-preservation-\(UUID().uuidString)", isDirectory: true)
        let configURL = tempRoot.appendingPathComponent("config.yen", isDirectory: false)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try contents.write(to: configURL, atomically: true, encoding: .utf8)
        SettingsController._testSetConfigPathOverride(configURL.path)
        controller.loadConfigForTesting()

        return RawPreservationFixture(contents: contents) {
            SettingsController._testSetConfigPathOverride(nil)
            controller.loadConfigForTesting()
            controller.fontSize = originalFontSize
            controller.windowPaddingX = originalPaddingX
            controller.cursorStyle = originalCursorStyle
            controller.cursorBlink = originalCursorBlink
            controller.backgroundOpacity = originalOpacity
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }
}
