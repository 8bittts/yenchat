#if os(macOS)
import SwiftUI
import AppKit
#if canImport(Translation)
import Translation
#endif

// MARK: - Form Building Blocks

/// A standard grouped form with a clear background, so the inspector's glass
/// shows behind the sections.
struct SettingsStudioForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .modifier(SettingsFormTopMargin())
    }
}

/// Trims the grouped form's default top margin so the first section sits
/// close to the pane title. `contentMargins` needs macOS 14.
private struct SettingsFormTopMargin: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.contentMargins(.top, SettingsSpacing.formTopMargin, for: .scrollContent)
        } else {
            content
        }
    }
}

/// A row label with an optional second line that explains the setting.
struct SettingsStudioLabel: View {
    let title: String
    var hint: String = ""
    /// A child row sits under the row that reveals it.
    var isChild = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsSpacing.hintSpacing) {
            Text(title)
            if !hint.isEmpty {
                Text(hint)
                    .font(SettingsTypography.hint)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, isChild ? SettingsSpacing.childIndent : 0)
    }
}

/// A read-only value beside a slider or a stepper.
private struct SettingsStudioValueText: View {
    let text: String

    var body: some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: SettingsSpacing.valueMinWidth, alignment: .trailing)
    }
}

/// A status symbol with a label: allowed, or needs attention.
private struct SettingsStudioStatusLabel: View {
    let isOK: Bool
    let text: String

    var body: some View {
        // The symbol carries the state color and the text stays a label color,
        // so the state reads in both appearances and without color. The
        // symbols differ in shape as well as color.
        HStack(spacing: SettingsSpacing.iconTextSpacing) {
            Image(systemName: isOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isOK ? Color(NSColor.systemGreen) : Color(NSColor.systemOrange))
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// A caution line inside a section.
private struct SettingsStudioCaution: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsSpacing.iconTextSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(NSColor.systemOrange))
                .accessibilityHidden(true)
            Text(text)
                .font(SettingsTypography.note)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status Notice

/// Shows the controller's status message at the bottom of the inspector, only
/// while there is one. An error stays until it is dismissed or replaced.
struct SettingsStudioStatusNotice: View {
    let controller: SettingsController
    @State private var message = ""
    @State private var severity: SettingsStatusSeverity = .success

    static func symbolName(for severity: SettingsStatusSeverity) -> String {
        switch severity {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var symbolColor: Color {
        switch severity {
        case .success: return Color(NSColor.systemGreen)
        case .info: return .secondary
        case .warning: return Color(NSColor.systemOrange)
        case .error: return Color(NSColor.systemRed)
        }
    }

    var body: some View {
        Group {
            if !message.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    HStack(alignment: .firstTextBaseline, spacing: SettingsSpacing.controlSpacing) {
                        Image(systemName: Self.symbolName(for: severity))
                            .foregroundStyle(symbolColor)
                            .accessibilityHidden(true)
                        Text(message)
                            .font(SettingsTypography.note)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        if severity == .error {
                            Button {
                                controller.dismissStatus()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Dismiss")
                            .accessibilityLabel("Dismiss message")
                        }
                    }
                    .padding(.horizontal, SettingsSpacing.contentInset)
                    .padding(.vertical, SettingsSpacing.noticeVertical)
                }
                .transition(.opacity)
            }
        }
        .onReceive(controller.$statusMessage) { message = $0 }
        .onReceive(controller.$statusSeverity) { severity = $0 }
    }
}

// MARK: - Appearance

/// Border weights the Appearance pane offers, as stroke widths in points.
enum SettingsBorderWeight: Double, CaseIterable, Identifiable {
    case thin = 1
    case regular = 2
    case thick = 4

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .thin: return "Thin"
        case .regular: return "Regular"
        case .thick: return "Thick"
        }
    }

    /// The weight nearest to a stored width, so a width set by an older build
    /// still selects a segment.
    static func nearest(to width: Double) -> SettingsBorderWeight {
        allCases.min { abs($0.rawValue - width) < abs($1.rawValue - width) } ?? .regular
    }
}

/// Border scopes the Appearance pane offers.
enum SettingsBorderScopeChoice: String, CaseIterable, Identifiable {
    case window
    case focusedPane

    var id: String { rawValue }

    var scope: WindowBorderScope {
        switch self {
        case .window: return .window
        case .focusedPane: return .focusedSplit
        }
    }

    var title: String {
        switch self {
        case .window: return "Window"
        case .focusedPane: return "Focused Pane"
        }
    }

    init(scope: WindowBorderScope) {
        self = scope == .window ? .window : .focusedPane
    }
}

/// The child rows under the Border toggle, in display order.
enum SettingsBorderRow: CaseIterable, Identifiable {
    case color
    case scope
    case weight
    case spark
    case aura
    /// Shown only while the aura is on.
    case auraColor
    /// Shown only while the aura is on.
    case auraPulse

    var id: Self { self }
}

struct SettingsAppearancePane: View {
    @ObservedObject var store: GeneralSettingsStore

    static let opacityFooter = "Opacity applies the next time you open YEN."
    static let fontSizeRange: ClosedRange<Double> = 8...32
    static let opacityRange: ClosedRange<Double> = 0.1...1.0
    static let paddingRange: ClosedRange<Int> = 0...50
    static let paddingStep = 2

    static func borderHint(scope: WindowBorderScope) -> String {
        scope == .window ? "Outlines the window." : "Outlines the focused pane."
    }

    static func borderRows(enabled: Bool, auraEnabled: Bool) -> [SettingsBorderRow] {
        guard enabled else { return [] }
        let auraRows: Set<SettingsBorderRow> = [.auraColor, .auraPulse]
        return SettingsBorderRow.allCases.filter { auraEnabled || !auraRows.contains($0) }
    }

    static func sparkHint(limit: WindowBorderMotionLimit) -> String {
        switch limit {
        case .none: return "A light travels around the outline."
        case .reduceMotion: return "Reduce Motion is on, so the light is hidden."
        case .lowPowerMode: return "Low Power Mode is on, so the light is hidden."
        }
    }

    static func auraHint(limit: WindowBorderMotionLimit) -> String {
        switch limit {
        case .none: return "A soft glow pulses around the outline."
        case .reduceMotion: return "Reduce Motion is on, so the glow holds still."
        case .lowPowerMode: return "Low Power Mode is on, so the glow holds still."
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var powerState = LowPowerModeMonitor.shared

    private var motionLimit: WindowBorderMotionLimit {
        WindowBorderRenderingPolicy.motionLimit(
            reduceMotion: reduceMotion,
            lowPowerMode: powerState.isLowPowerModeEnabled
        )
    }

    var body: some View {
        let font = store.snapshot.font
        let cursor = store.snapshot.cursor
        let appearance = store.snapshot.appearance

        SettingsStudioForm {
            Section("Text") {
                if font.fonts.isEmpty {
                    // The font catalog is scanned off the main thread.
                    LabeledContent("Font") {
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                } else {
                    Picker(
                        "Font",
                        selection: Binding(get: { font.fontFamily }, set: { store.setFontFamily($0) })
                    ) {
                        ForEach(font.fonts, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                }

                LabeledContent("Size") {
                    HStack(spacing: SettingsSpacing.controlSpacing) {
                        Slider(
                            value: Binding(get: { font.fontSize }, set: { store.setFontSize($0) }),
                            in: Self.fontSizeRange,
                            step: 1
                        )
                        .frame(width: SettingsSpacing.inlineSliderWidth)
                        .accessibilityLabel("Font Size")
                        .accessibilityValue("\(Int(font.fontSize)) points")
                        SettingsStudioValueText(text: "\(Int(font.fontSize)) pt")
                    }
                }
            }

            Section("Cursor") {
                Picker(
                    "Style",
                    selection: Binding(get: { cursor.cursorStyle }, set: { store.setCursorStyle($0) })
                ) {
                    Text("Block").tag("block")
                    Text("Bar").tag("bar")
                    Text("Underline").tag("underline")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Cursor Style")

                Toggle("Blink", isOn: Binding(get: { cursor.cursorBlink }, set: { store.setCursorBlink($0) }))
                    .accessibilityLabel("Cursor Blink")
            }

            Section {
                LabeledContent("Opacity") {
                    HStack(spacing: SettingsSpacing.controlSpacing) {
                        Slider(
                            value: Binding(
                                get: { appearance.backgroundOpacity },
                                set: { store.setBackgroundOpacity($0) }
                            ),
                            in: Self.opacityRange,
                            step: 0.05
                        )
                        .frame(width: SettingsSpacing.inlineSliderWidth)
                        .accessibilityLabel("Background Opacity")
                        SettingsStudioValueText(text: "\(Int((appearance.backgroundOpacity * 100).rounded()))%")
                    }
                }

                LabeledContent("Padding") {
                    HStack(spacing: SettingsSpacing.controlSpacing) {
                        SettingsStudioValueText(text: "\(appearance.windowPaddingX) pt")
                        Stepper(
                            "Padding",
                            value: Binding(
                                get: { appearance.windowPaddingX },
                                set: { value in
                                    // One control sets both axes.
                                    store.setWindowPaddingX(value)
                                    store.setWindowPaddingY(value)
                                }
                            ),
                            in: Self.paddingRange,
                            step: Self.paddingStep
                        )
                        .labelsHidden()
                        .accessibilityValue("\(appearance.windowPaddingX) points")
                    }
                }

                LabeledContent {
                    HStack(spacing: SettingsSpacing.controlSpacing) {
                        if appearance.hasBackgroundImage {
                            Button("Remove") { store.removeBackgroundImage() }
                        }
                        Button(appearance.hasBackgroundImage ? "Replace…" : "Choose…") {
                            store.importBackgroundImage()
                        }
                    }
                } label: {
                    SettingsStudioLabel(
                        title: "Background Image",
                        hint: appearance.hasBackgroundImage ? appearance.backgroundImageDisplayTitle : ""
                    )
                }

                if !appearance.backgroundImageIssueDescription.isEmpty {
                    SettingsStudioCaution(text: appearance.backgroundImageIssueDescription)
                }

                if appearance.hasBackgroundImage {
                    Picker(
                        selection: Binding(
                            get: { appearance.backgroundImageScope },
                            set: { store.setBackgroundImageScope($0) }
                        )
                    ) {
                        Text("Each Pane").tag(BackgroundImageScope.eachSplit)
                        Text("Whole Window").tag(BackgroundImageScope.wholeWindow)
                    } label: {
                        SettingsStudioLabel(title: "Image Fills", isChild: true)
                    }
                    .accessibilityLabel("Background Image Fills")
                }

                Toggle(
                    isOn: Binding(
                        get: { appearance.windowBorderEnabled },
                        set: { store.setWindowBorderEnabled($0) }
                    )
                ) {
                    SettingsStudioLabel(
                        title: "Border",
                        hint: Self.borderHint(scope: appearance.windowBorderScope)
                    )
                }

                ForEach(
                    Self.borderRows(
                        enabled: appearance.windowBorderEnabled,
                        auraEnabled: appearance.windowBorderEffects.auraEnabled
                    )
                ) { row in
                    borderRow(row, appearance: appearance)
                }
            } header: {
                Text("Window")
            } footer: {
                Text(Self.opacityFooter)
            }
        }
    }

    @ViewBuilder
    private func borderRow(
        _ row: SettingsBorderRow,
        appearance: GeneralSettingsStore.Snapshot.Appearance
    ) -> some View {
        switch row {
        case .color:
            Picker(
                selection: Binding(
                    get: { appearance.windowBorderColorMode },
                    set: { store.setWindowBorderColorMode($0) }
                )
            ) {
                Text("Theme").tag(WindowBorderColorMode.matchTheme)
                Text("Accent").tag(WindowBorderColorMode.manual)
            } label: {
                SettingsStudioLabel(title: "Color", isChild: true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Border Color")

            // The theme has no usable accent colors, so the border draws
            // the accent palette instead.
            if appearance.windowBorderColorMode == .matchTheme,
               appearance.windowBorderMatchThemeUsesManualFallback {
                SettingsStudioCaution(text: appearance.windowBorderMatchThemeStatusMessage)
            }
        case .scope:
            Picker(
                selection: Binding(
                    get: { SettingsBorderScopeChoice(scope: appearance.windowBorderScope) },
                    set: { store.setWindowBorderScope($0.scope) }
                )
            ) {
                ForEach(SettingsBorderScopeChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            } label: {
                SettingsStudioLabel(title: "Outline", isChild: true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Border Outline")
        case .weight:
            Picker(
                selection: Binding(
                    get: { SettingsBorderWeight.nearest(to: appearance.windowBorderWidth) },
                    set: { store.setWindowBorderWidth($0.rawValue) }
                )
            ) {
                ForEach(SettingsBorderWeight.allCases) { weight in
                    Text(weight.title).tag(weight)
                }
            } label: {
                SettingsStudioLabel(title: "Weight", isChild: true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Border Weight")
        case .spark:
            Toggle(
                isOn: Binding(
                    get: { appearance.windowBorderEffects.sparkEnabled },
                    set: { store.setWindowBorderSparkEnabled($0) }
                )
            ) {
                SettingsStudioLabel(
                    title: "Spark",
                    hint: Self.sparkHint(limit: motionLimit),
                    isChild: true
                )
            }
            .accessibilityLabel("Border Spark")
        case .aura:
            Toggle(
                isOn: Binding(
                    get: { appearance.windowBorderEffects.auraEnabled },
                    set: { store.setWindowBorderAuraEnabled($0) }
                )
            ) {
                SettingsStudioLabel(
                    title: "Aura",
                    hint: Self.auraHint(limit: motionLimit),
                    isChild: true
                )
            }
            .accessibilityLabel("Border Aura")
        case .auraColor:
            ColorPicker(
                selection: Binding(
                    get: { appearance.windowBorderEffects.auraColor },
                    set: { store.setWindowBorderAuraColor($0) }
                ),
                supportsOpacity: false
            ) {
                SettingsStudioLabel(title: "Aura Color", isChild: true)
            }
            .accessibilityLabel("Border Aura Color")
        case .auraPulse:
            Picker(
                selection: Binding(
                    get: { appearance.windowBorderEffects.auraPulse },
                    set: { store.setWindowBorderAuraPulse($0) }
                )
            ) {
                ForEach(WindowBorderAuraPulse.allCases) { pulse in
                    Text(pulse.displayName).tag(pulse)
                }
            } label: {
                SettingsStudioLabel(title: "Aura Pulse", isChild: true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Border Aura Pulse")
        }
    }
}

// MARK: - General

/// The three Tab Sidebar states, stored as an enabled flag and a mode.
enum SettingsTabSidebarChoice: String, CaseIterable, Identifiable {
    case off = "Off"
    case floating = "Floating"
    case docked = "Docked"

    var id: String { rawValue }

    init(enabled: Bool, mode: TabSidebarPresentationMode) {
        guard enabled else {
            self = .off
            return
        }
        self = mode == .persistent ? .docked : .floating
    }
}

struct SettingsGeneralPane: View {
    let controller: SettingsController
    @ObservedObject var general: GeneralSettingsStore
    @StateObject private var workspace: WorkspaceSettingsStore
    @State private var sessionCount = 0

    static let loginApprovalText =
        "Waiting for approval. YEN will not open at login until you allow it in Login Items."
    static let copyOnSelectHint = "Selecting text copies it to the clipboard."
    static let persistentSessionsHint = "Panes keep running when YEN quits and reattach when their windows reopen."
    static let tabSidebarHint = "Lists tabs with their folder and Git branch."
    static let linksHint = "Web links from the terminal open in the built-in browser."
    static let scratchpadAction = "yen_toggle_scratchpad"

    init(controller: SettingsController, general: GeneralSettingsStore) {
        self.controller = controller
        self.general = general
        _workspace = StateObject(wrappedValue: WorkspaceSettingsStore(controller: controller))
    }

    /// The Scratchpad shortcut as it is bound now, or its default before the
    /// shortcut list has loaded.
    private var scratchpadShortcut: String {
        let entries = controller.keybindEntries.isEmpty ? KeybindRegistry.defaults : controller.keybindEntries
        return entries.first(where: { $0.action == Self.scratchpadAction })?.currentTrigger.glyphString ?? ""
    }

    private func setTabSidebar(_ choice: SettingsTabSidebarChoice) {
        switch choice {
        case .off:
            workspace.setTabSidebarEnabled(false)
        case .floating:
            workspace.setTabSidebarPresentationMode(.transient)
            workspace.setTabSidebarEnabled(true)
        case .docked:
            workspace.setTabSidebarPresentationMode(.persistent)
            workspace.setTabSidebarEnabled(true)
        }
    }

    private func refreshSessionCount() async {
        let count = await Task.detached(priority: .utility) {
            PersistentSessions.liveSessionIDs().count
        }.value
        if !Task.isCancelled { sessionCount = count }
    }

    var body: some View {
        let startup = general.snapshot.startup
        let behavior = general.snapshot.behavior
        let space = workspace.snapshot

        SettingsStudioForm {
            Section {
                Toggle(
                    "Open YEN at Login",
                    isOn: Binding(get: { startup.launchAtLogin }, set: { general.setLaunchAtLogin($0) })
                )

                // macOS can hold a login item for approval while the switch reads on.
                if startup.launchAtLoginNeedsApproval {
                    VStack(alignment: .leading, spacing: SettingsSpacing.controlSpacing) {
                        SettingsStudioCaution(text: Self.loginApprovalText)
                        Button("Open Login Items…") { general.openLoginItemsSettings() }
                    }
                }

                Toggle(
                    isOn: Binding(get: { behavior.copyOnSelect }, set: { general.setCopyOnSelect($0) })
                ) {
                    SettingsStudioLabel(title: "Copy on Select", hint: Self.copyOnSelectHint)
                }

                Toggle(
                    isOn: Binding(get: { behavior.persistentSessions }, set: { general.setPersistentSessions($0) })
                ) {
                    SettingsStudioLabel(title: "Keep Sessions Running", hint: Self.persistentSessionsHint)
                }
                // The switch always renders, so it owns the refresh; a task on a
                // row that is hidden while no session runs would never start.
                .task {
                    while !Task.isCancelled {
                        await refreshSessionCount()
                        try? await Task.sleep(for: .seconds(3))
                    }
                }

                if sessionCount > 0 {
                    PersistentSessionsStatusRow(controller: controller, count: sessionCount) {
                        await refreshSessionCount()
                    }
                }

                Picker(
                    "Scroll Bar",
                    selection: Binding(
                        get: { behavior.scrollbarVisibility == "never" ? "never" : "system" },
                        set: { general.setScrollbarVisibility($0) }
                    )
                ) {
                    Text("Automatic").tag("system")
                    Text("Never").tag("never")
                }
            }

            Section("Workspace") {
                Picker(
                    selection: Binding(
                        get: {
                            SettingsTabSidebarChoice(
                                enabled: space.tabSidebarEnabled,
                                mode: space.tabSidebarPresentationMode
                            )
                        },
                        set: { setTabSidebar($0) }
                    )
                ) {
                    ForEach(SettingsTabSidebarChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                } label: {
                    SettingsStudioLabel(title: "Tab Sidebar", hint: Self.tabSidebarHint)
                }
                .accessibilityLabel("Tab Sidebar")

                Toggle(
                    isOn: Binding(
                        get: { space.scratchpadEnabled },
                        set: { workspace.setScratchpadEnabled($0) }
                    )
                ) {
                    HStack(spacing: SettingsSpacing.controlSpacing) {
                        Text("Scratchpad")
                        if !scratchpadShortcut.isEmpty {
                            Text(scratchpadShortcut)
                                .font(SettingsTypography.note)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Shortcut \(scratchpadShortcut)")
                        }
                    }
                }
            }

            Section("Panes") {
                Picker("Pane Style", selection: Binding(
                    get: { space.paneStyle },
                    set: { workspace.setPaneStyle($0) }
                )) {
                    Text("Comfortable").tag(PaneStyle.comfortable)
                    Text("Compact").tag(PaneStyle.compact)
                }
                .pickerStyle(.segmented)

                Toggle(
                    "Pane Labels",
                    isOn: Binding(
                        get: { space.splitPaneLabelsEnabled },
                        set: { workspace.setSplitPaneLabelsEnabled($0) }
                    )
                )

                if space.splitPaneLabelsEnabled {
                    Toggle(
                        isOn: Binding(
                            get: { space.splitPaneWorktreeNamingEnabled },
                            set: { workspace.setSplitPaneWorktreeNamingEnabled($0) }
                        )
                    ) {
                        SettingsStudioLabel(title: "Name Panes After Their Worktree", isChild: true)
                    }
                }
            }

            Section("Menu Bar") { TokenUsagePreference() }

            Section("Links") {
                Toggle(
                    isOn: Binding(
                        get: { space.browserTerminalLinkCaptureEnabled },
                        set: { workspace.setBrowserTerminalLinkCaptureEnabled($0) }
                    )
                ) {
                    SettingsStudioLabel(title: "Open Links in YEN", hint: Self.linksHint)
                }

                Toggle(
                    "Open the Browser in a Split",
                    isOn: Binding(
                        get: { space.browserSplitEnabled },
                        set: { workspace.setBrowserSplitEnabled($0) }
                    )
                )
            }

            Section("Experimental") { MovingWallpaperPreference() }

            Section {
                LabeledContent("Reset All Settings") {
                    Button("Reset…", role: .destructive) {
                        controller.confirmResetAllSettings()
                    }
                }
            }
        }
    }
}

// MARK: - Persistent Sessions

/// How many pane sessions run now, and a way to end them all without the CLI.
/// The General pane lists the socket directory every few seconds while it is
/// visible and shows this row only while a session runs.
struct PersistentSessionsStatusRow: View {
    let controller: SettingsController
    let count: Int
    let refresh: () async -> Void

    static func title(count: Int) -> String {
        count == 1 ? "1 session running" : "\(count) sessions running"
    }

    var body: some View {
        LabeledContent(Self.title(count: count)) {
            Button("End All Sessions…", role: .destructive) {
                controller.confirmEndAllPersistentSessions(count: count) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        await refresh()
                    }
                }
            }
        }
    }
}

// MARK: - Notifications

struct SettingsNotificationsPane: View {
    @StateObject private var store: SoundsSettingsStore

    static let permissionWarning =
        "Notifications are not allowed for YEN, so banners and alert sounds stay silent."
    static let noDeliveryWarning = "The bell and the notification are both off, so nothing happens."
    static let delayRange: ClosedRange<Int> = 0...999_999
    static let delayStep = 5

    init(controller: SettingsController) {
        _store = StateObject(wrappedValue: SoundsSettingsStore(controller: controller))
    }

    static func serviceTitle(_ service: NotificationService) -> String {
        switch service {
        case .general: return "General"
        case .build: return "Build Finished"
        }
    }

    /// The sound the pop-up shows: None when the stream is silent for any
    /// reason, otherwise the stored sound.
    static func displayedSoundSelection(
        selection: String,
        deliveryMode: NotificationDeliveryMode,
        volume: Double
    ) -> String {
        guard deliveryMode.allowsSound, volume > 0 else {
            return NotificationSoundManager.silentSelectionID
        }
        return selection
    }

    /// The delivery mode after the user picks a sound. A mode that blocks sound
    /// would leave the choice silent, so it is raised to banner and sound.
    static func deliveryMode(
        afterChoosing selection: String,
        current: NotificationDeliveryMode
    ) -> NotificationDeliveryMode {
        guard selection != NotificationSoundManager.silentSelectionID else { return current }
        return current.allowsSound ? current : .bannerAndSound
    }

    private func chooseSound(_ selection: String, for preference: SoundsSettingsStore.Snapshot.NotificationServicePreference) {
        let service = preference.service
        store.setNotificationSoundSelection(selection, for: service)
        guard selection != NotificationSoundManager.silentSelectionID else { return }

        let mode = Self.deliveryMode(afterChoosing: selection, current: preference.deliveryMode)
        if mode != preference.deliveryMode {
            store.setNotificationSoundDeliveryMode(mode, for: service)
        }
        let volume = preference.volume > 0 ? preference.volume : 1.0
        if volume != preference.volume {
            store.setNotificationSoundVolume(volume, for: service)
        }
        store.previewSound(selection, volume: volume)
    }

    @ViewBuilder
    private func soundPicker(
        for preference: SoundsSettingsStore.Snapshot.NotificationServicePreference,
        sounds: [NotificationSoundOption]
    ) -> some View {
        let silent = NotificationSoundManager.silentSelectionID
        let displayed = Self.displayedSoundSelection(
            selection: preference.selection,
            deliveryMode: preference.deliveryMode,
            volume: preference.volume
        )
        Picker(
            Self.serviceTitle(preference.service),
            selection: Binding(get: { displayed }, set: { chooseSound($0, for: preference) })
        ) {
            Text("None").tag(silent)
            Divider()
            ForEach(sounds) { sound in
                Text(sound.name).tag(sound.id)
            }
            // A stored sound this Mac no longer lists stays visible.
            if displayed != silent, !sounds.contains(where: { $0.id == displayed }) {
                Text(store.displaySoundSelection(displayed)).tag(displayed)
            }
        }
        .accessibilityLabel("\(Self.serviceTitle(preference.service)) Alert Sound")
    }

    var body: some View {
        let access = store.snapshot.notificationAccess
        let command = store.snapshot.commandNotifications
        let focus = store.snapshot.focusBehavior
        let sounds = store.snapshot.notificationSoundLibrary.systemSounds
        let notifies = command.notifyOnCommandFinish != "never"

        SettingsStudioForm {
            Section {
                LabeledContent("Notifications") {
                    HStack(spacing: SettingsSpacing.controlSpacing) {
                        SettingsStudioStatusLabel(
                            isOK: access.authorizationAllowsDelivery,
                            text: access.authorizationStatusLabel
                        )
                        if !access.authorizationAllowsDelivery {
                            Button(access.authorizationActionTitle) {
                                store.handleNotificationAuthorizationAction()
                            }
                            .accessibilityHint(access.authorizationActionHint)
                        }
                    }
                }
                .help(access.authorizationDetailLine)
            }

            Section("When a Command Finishes") {
                Picker(
                    "Notify",
                    selection: Binding(
                        get: { command.notifyOnCommandFinish },
                        set: { store.setNotifyOnCommandFinish($0) }
                    )
                ) {
                    Text("Never").tag("never")
                    Text("When Pane Is Unfocused").tag("unfocused")
                    Text("Always").tag("always")
                }

                if notifies {
                    LabeledContent {
                        HStack(spacing: SettingsSpacing.controlSpacing) {
                            SettingsStudioValueText(text: "\(command.notifyOnCommandFinishAfterSeconds) s")
                            Stepper(
                                "Only After",
                                value: Binding(
                                    get: { command.notifyOnCommandFinishAfterSeconds },
                                    set: { store.setNotifyOnCommandFinishAfterSeconds($0) }
                                ),
                                in: Self.delayRange,
                                step: Self.delayStep
                            )
                            .labelsHidden()
                            .accessibilityValue("\(command.notifyOnCommandFinishAfterSeconds) seconds")
                        }
                    } label: {
                        SettingsStudioLabel(title: "Only After", isChild: true)
                    }

                    Toggle(
                        isOn: Binding(
                            get: { command.notifyOnCommandFinishActionBell },
                            set: { store.setNotifyOnCommandFinishActionBell($0) }
                        )
                    ) {
                        SettingsStudioLabel(title: "Ring the Terminal Bell", isChild: true)
                    }

                    Toggle(
                        isOn: Binding(
                            get: { command.notifyOnCommandFinishActionNotify },
                            set: { store.setNotifyOnCommandFinishActionNotify($0) }
                        )
                    ) {
                        SettingsStudioLabel(title: "Show a Notification", isChild: true)
                    }

                    if SettingsPanel.shouldShowCommandFinishPermissionWarning(
                        notifyMode: command.notifyOnCommandFinish,
                        notifyDeliveryEnabled: command.notifyOnCommandFinishActionNotify,
                        bellDeliveryEnabled: command.notifyOnCommandFinishActionBell,
                        notificationAuthorizationAllowsDelivery: command.notificationAuthorizationAllowsDelivery
                    ) {
                        SettingsStudioCaution(text: Self.permissionWarning)
                    }

                    if SettingsPanel.shouldShowCommandFinishNoDeliveryWarning(
                        notifyMode: command.notifyOnCommandFinish,
                        bellDeliveryEnabled: command.notifyOnCommandFinishActionBell,
                        notificationDeliveryEnabled: command.notifyOnCommandFinishActionNotify
                    ) {
                        SettingsStudioCaution(text: Self.noDeliveryWarning)
                    }
                }
            }

            Section("Alert Sounds") {
                ForEach(store.snapshot.notificationServicePreferences) { preference in
                    soundPicker(for: preference, sounds: sounds)
                }
            }

            Section("While YEN Is Active") {
                Toggle(
                    "Play Sounds",
                    isOn: Binding(get: { focus.soundWhenFocused }, set: { store.setSoundWhenFocused($0) })
                )
                Toggle(
                    "Show Banners",
                    isOn: Binding(get: { focus.bannerWhenFocused }, set: { store.setBannerWhenFocused($0) })
                )
            }
        }
    }
}

// MARK: - Dictation

struct SettingsDictationPane: View {
    @StateObject private var store: SoundsSettingsStore

    static let translateHint = "Translates what you say before it is typed."
    static let permissionsFooter =
        "Hold ⌥Space to dictate. Speech is recognized on this Mac when on-device recognition is available."

    init(controller: SettingsController) {
        _store = StateObject(wrappedValue: SoundsSettingsStore(controller: controller))
    }

    static func translationTargetFallbackLabel(
        translationSupportedOnThisMac: Bool,
        availableTargetLanguages: [DictationTranslationLanguageOption]
    ) -> String? {
        guard translationSupportedOnThisMac, availableTargetLanguages.isEmpty else { return nil }
        return "No compatible languages"
    }

    /// Lines shown under the Translation section for the current state.
    static func translationDetailTexts(
        translationSupportedOnThisMac: Bool,
        translateOnDictateEnabled: Bool,
        availableTargetLanguages: [DictationTranslationLanguageOption]
    ) -> [String] {
        guard translationSupportedOnThisMac else {
            return ["Translation is unavailable on this Mac."]
        }
        guard translateOnDictateEnabled else { return [] }

        var details: [String] = []
        if availableTargetLanguages.isEmpty {
            details.append("No languages are available for your dictation language.")
        }
        details.append("If translation fails or times out, YEN types what you said.")
        return details
    }

    @ViewBuilder
    private func permissionRow(
        _ name: String,
        granted: Bool,
        actionTitle: String,
        destination: DictationController.PrivacyDestination
    ) -> some View {
        LabeledContent(name) {
            HStack(spacing: SettingsSpacing.controlSpacing) {
                SettingsStudioStatusLabel(isOK: granted, text: granted ? "Allowed" : "Not Allowed")
                if !granted {
                    Button(actionTitle) {
                        DictationController.shared.openSettings(for: destination)
                    }
                    .accessibilityLabel("\(actionTitle) \(name)")
                }
            }
        }
    }

    var body: some View {
        let permissions = store.snapshot.permissions
        let dictation = store.snapshot.dictation
        let translation = store.snapshot.translation
        let details = Self.translationDetailTexts(
            translationSupportedOnThisMac: translation.translationSupportedOnThisMac,
            translateOnDictateEnabled: translation.translateOnDictateEnabled,
            availableTargetLanguages: translation.availableTargetLanguages
        )

        SettingsStudioForm {
            Section {
                permissionRow(
                    "Accessibility",
                    granted: permissions.accessibilityGranted,
                    actionTitle: "Grant",
                    destination: .accessibility
                )
                permissionRow(
                    "Microphone",
                    granted: permissions.microphoneGranted,
                    actionTitle: permissions.microphoneFixTitle,
                    destination: .microphone
                )
                permissionRow(
                    "Speech Recognition",
                    granted: permissions.speechRecognitionGranted,
                    actionTitle: permissions.speechFixTitle,
                    destination: .speechRecognition
                )

                if !permissions.dictationLocalSpeechServiceReady {
                    SettingsStudioCaution(text: permissions.dictationLocalServiceIssueDetail)
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text(Self.permissionsFooter)
            }

            Section {
                Picker(
                    "Microphone",
                    selection: Binding(
                        get: { dictation.selectedInputDeviceIdentifier },
                        set: { store.setSelectedInputDeviceIdentifier($0) }
                    )
                ) {
                    ForEach(dictation.inputDeviceOptions) { option in
                        Text(option.displayName).tag(option.identifier)
                    }
                }
                .accessibilityLabel("Dictation Microphone")
                .help(DictationCopy.settingsMicrophoneLine)

                if let reason = dictation.inputDeviceFallbackReason {
                    SettingsStudioCaution(text: reason)
                }

                Toggle(
                    "Show Live Transcript",
                    isOn: Binding(
                        get: { dictation.liveTranscriptPreviewEnabled },
                        set: { store.setLiveTranscriptPreviewEnabled($0) }
                    )
                )
                .help(DictationCopy.settingsLiveTranscriptPreviewLine)
            }

            Section {
                Toggle(
                    isOn: Binding(
                        get: { translation.translateOnDictateEnabled },
                        set: { store.setTranslateOnDictateEnabled($0) }
                    )
                ) {
                    SettingsStudioLabel(title: "Translate Dictation", hint: Self.translateHint)
                }
                .disabled(!translation.translationSupportedOnThisMac)

                if translation.translationSupportedOnThisMac, translation.translateOnDictateEnabled {
                    if let fallback = Self.translationTargetFallbackLabel(
                        translationSupportedOnThisMac: translation.translationSupportedOnThisMac,
                        availableTargetLanguages: translation.availableTargetLanguages
                    ) {
                        LabeledContent {
                            Text(fallback).foregroundStyle(.secondary)
                        } label: {
                            SettingsStudioLabel(title: "Translate To", isChild: true)
                        }
                    } else {
                        Picker(
                            selection: Binding(
                                get: { translation.targetLanguageIdentifier },
                                set: { store.setTargetLanguageIdentifier($0) }
                            )
                        ) {
                            ForEach(translation.availableTargetLanguages) { option in
                                Text(option.displayName).tag(option.identifier)
                            }
                        } label: {
                            SettingsStudioLabel(title: "Translate To", isChild: true)
                        }
                        .accessibilityLabel("Translate To")
                    }
                }
            } header: {
                Text("Translation")
            } footer: {
                if !details.isEmpty {
                    Text(details.joined(separator: " "))
                }
            }
        }
        .onAppear { store.startInputDeviceMonitoring() }
        .onDisappear { store.stopInputDeviceMonitoring() }
        .background {
#if canImport(Translation)
            if #available(macOS 26.0, *), let request = translation.preparationRequest {
                SettingsDictationTranslationPreparationTask(
                    request: request,
                    onPrepare: { session, requestID in
                        await store.prepareDictationTranslationAssets(with: session, requestID: requestID)
                    }
                )
            }
#endif
        }
    }
}

#if canImport(Translation)
/// Hosts the system translation session that downloads a language pair.
@available(macOS 26.0, *)
private struct SettingsDictationTranslationPreparationTask: View {
    let request: DictationTranslationPreparationRequest
    let onPrepare: @MainActor (TranslationSession, UUID) async -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(
                source: request.sourceLanguage,
                target: request.targetLanguage
            ) { session in
                await onPrepare(session, request.id)
            }
            .id(request.id)
    }
}
#endif

extension SettingsPanel {
    static func translationTargetFallbackLabelForTesting(
        translationSupportedOnThisMac: Bool,
        availableTargetLanguages: [DictationTranslationLanguageOption]
    ) -> String? {
        SettingsDictationPane.translationTargetFallbackLabel(
            translationSupportedOnThisMac: translationSupportedOnThisMac,
            availableTargetLanguages: availableTargetLanguages
        )
    }

    static func translationDetailTextsForTesting(
        translationSupportedOnThisMac: Bool,
        translateOnDictateEnabled: Bool,
        availableTargetLanguages: [DictationTranslationLanguageOption]
    ) -> [String] {
        SettingsDictationPane.translationDetailTexts(
            translationSupportedOnThisMac: translationSupportedOnThisMac,
            translateOnDictateEnabled: translateOnDictateEnabled,
            availableTargetLanguages: availableTargetLanguages
        )
    }
}

#endif // os(macOS)
