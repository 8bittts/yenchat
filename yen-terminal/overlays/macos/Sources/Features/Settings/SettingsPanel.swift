#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Design Constants

/// Every spacing value the Settings window uses. Views use these tokens, never
/// a literal, so the inspector, the panes and the dock share one rhythm.
enum SettingsSpacing {
    // Window and floating panels.
    static let panelMinWidth: CGFloat = 980
    static let panelIdealWidth: CGFloat = 1100
    /// Width of the floating inspector. Wide enough for a permission row with
    /// its name, status and button on one line.
    static let inspectorWidth: CGFloat = 380
    /// Gap between the window edge and a floating glass panel.
    static let floatingInset: CGFloat = 12
    /// Gap between the theme dock and the inspector.
    static let floatingGap: CGFloat = 12
    /// Padding inside the theme dock.
    static let dockPadding: CGFloat = 14

    // Inspector.
    /// Horizontal inset of everything outside the form, equal to the grouped
    /// form's own section inset so the header lines up with the sections.
    static let contentInset: CGFloat = 20
    static let headerTop: CGFloat = 16
    /// Between the pane switcher and the pane title.
    static let headerSpacing: CGFloat = 12
    /// Between the pane title, or a control below it, and the form.
    static let headerBottom: CGFloat = 4
    /// The grouped form's top margin, trimmed so the first section sits close
    /// to the pane title (macOS 14 and later).
    static let formTopMargin: CGFloat = 8

    // Rows.
    /// Between controls that share a row.
    static let controlSpacing: CGFloat = 8
    /// Between a symbol and its text.
    static let iconTextSpacing: CGFloat = 6
    /// Between a row label and its hint.
    static let hintSpacing: CGFloat = 2
    /// Leading indent of a row revealed by the row above it.
    static let childIndent: CGFloat = 14
    static let inlineSliderWidth: CGFloat = 118
    static let valueMinWidth: CGFloat = 40
    /// Vertical padding of the status notice.
    static let noticeVertical: CGFloat = 10

    // Theme dock.
    static let swatchSpacing: CGFloat = 9
    static let dockHeaderSpacing: CGFloat = 10

    // Preview.
    /// Room kept clear for the window controls above the first line.
    static let previewTopInset: CGFloat = 52
    static let previewLeadingInset: CGFloat = 20
    /// The preview caption sits to the right of the window controls.
    static let previewCaptionLeading: CGFloat = 86
}

/// The text styles the Settings window uses, by role. All are Dynamic Type
/// styles; rows use the form's default body style.
enum SettingsTypography {
    static let paneTitle: Font = .title3.weight(.semibold)
    /// The second line under a row label.
    static let hint: Font = .caption
    /// Cautions, the status notice and other sentences inside a pane.
    static let note: Font = .callout
    /// The theme dock header.
    static let dockTitle: Font = .callout
    /// The preview caption and the notes under a shortcut row.
    static let caption: Font = .caption
}

enum SettingsCornerRadius {
    /// Theme swatches.
    static let prominent: CGFloat = 10
    /// Floating glass panels: the inspector and the theme dock.
    static let glassPanel: CGFloat = 22
}

// MARK: - Panes

/// The five Settings panes, in display order.
enum SettingsPane: String, CaseIterable {
    case appearance = "Appearance"
    case general = "General"
    case notifications = "Notifications"
    case dictation = "Dictation"
    case shortcuts = "Shortcuts"

    var symbolName: String {
        switch self {
        case .appearance: return "paintpalette"
        case .general: return "gearshape"
        case .notifications: return "bell"
        case .dictation: return "mic"
        case .shortcuts: return "keyboard"
        }
    }
}

// MARK: - Root

/// The Settings window content.
///
/// The window is a live terminal preview: every appearance setting changes it in
/// place. The controls float above it in Liquid Glass, an inspector with the
/// five panes and a dock with the theme catalog. Glass sits on the control
/// layer only; the preview is the content layer, and the forms inside the
/// inspector are standard grouped forms.
///
/// There is no search, no import or export, and no permanent status bar. The
/// whole settings set fits in five short panes. A notice appears at the bottom
/// of the inspector only while the controller has something to report.
struct SettingsPanel: View {
    let controller: SettingsController
    @StateObject private var general: GeneralSettingsStore
    @StateObject private var themes: ThemesSettingsStore
    @State private var selectedPane: SettingsPane

    init(controller: SettingsController) {
        self.controller = controller
        _general = StateObject(wrappedValue: GeneralSettingsStore(controller: controller))
        _themes = StateObject(wrappedValue: ThemesSettingsStore(controller: controller))
        _selectedPane = State(initialValue: controller.selectedSettingsPane)
    }

    /// Whether a command-finish alert is enabled while notification permission
    /// is off, which silences its banner and its sound.
    static func shouldShowCommandFinishPermissionWarning(
        notifyMode: String,
        notifyDeliveryEnabled: Bool,
        bellDeliveryEnabled: Bool = false,
        notificationAuthorizationAllowsDelivery: Bool
    ) -> Bool {
        notifyMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "never" &&
            (notifyDeliveryEnabled || bellDeliveryEnabled) &&
            !notificationAuthorizationAllowsDelivery
    }

    /// Whether command-finish alerts are on with neither delivery method chosen.
    static func shouldShowCommandFinishNoDeliveryWarning(
        notifyMode: String,
        bellDeliveryEnabled: Bool,
        notificationDeliveryEnabled: Bool
    ) -> Bool {
        notifyMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "never" &&
            !bellDeliveryEnabled &&
            !notificationDeliveryEnabled
    }

    private var paneSelection: Binding<SettingsPane> {
        Binding(
            get: { selectedPane },
            set: { pane in
                guard selectedPane != pane else { return }
                selectedPane = pane
                if controller.selectedSettingsPane != pane {
                    controller.selectedSettingsPane = pane
                }
            }
        )
    }

    var body: some View {
        let previewTheme = SettingsStudioTheme.resolve(
            selectedTheme: themes.snapshot.selectedTheme,
            in: themes.snapshot.themes
        )
        ZStack(alignment: .bottomLeading) {
            SettingsStudioPreview(
                appearance: general.snapshot.appearance,
                font: general.snapshot.font,
                cursor: general.snapshot.cursor,
                theme: previewTheme
            )
            .ignoresSafeArea()

            // A quiet label beside the traffic lights, in the preview's own dim
            // text color so it reads on light and dark themes. The top safe-area
            // inset is the titlebar band the traffic lights are centered in, so
            // centering in it lines the label up with them on every macOS version.
            GeometryReader { proxy in
                Text("Live Preview")
                    .font(SettingsTypography.caption)
                    .foregroundStyle(previewTheme.foreground.opacity(0.6))
                    .frame(height: proxy.safeAreaInsets.top)
                    .padding(.leading, SettingsSpacing.previewCaptionLeading)
                    .offset(y: -proxy.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            if selectedPane == .appearance {
                SettingsStudioThemeDock(store: themes)
                    .padding(.leading, SettingsSpacing.floatingInset)
                    .padding(.bottom, SettingsSpacing.floatingInset)
                    .padding(
                        .trailing,
                        SettingsSpacing.inspectorWidth + SettingsSpacing.floatingInset + SettingsSpacing.floatingGap
                    )
                    .transition(.opacity)
            }

            SettingsStudioInspector(
                controller: controller,
                general: general,
                selection: paneSelection
            )
            .frame(width: SettingsSpacing.inspectorWidth)
            .padding(SettingsSpacing.floatingInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .ignoresSafeArea()
        }
        .frame(
            minWidth: SettingsSpacing.panelMinWidth,
            idealWidth: SettingsSpacing.panelIdealWidth,
            minHeight: SettingsWindowFactory.minimumContentHeight
        )
        .onReceive(controller.$selectedSettingsPane.removeDuplicates()) { pane in
            guard selectedPane != pane else { return }
            selectedPane = pane
        }
    }
}

// MARK: - Inspector

/// The floating glass inspector: a pane switcher, the pane title, and the form.
struct SettingsStudioInspector: View {
    let controller: SettingsController
    @ObservedObject var general: GeneralSettingsStore
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: SettingsSpacing.headerSpacing) {
                // Five equal segments across the full width of the inspector.
                SettingsSegmentedControl(
                    accessibilityLabel: "Settings Pane",
                    segments: SettingsPane.allCases.map {
                        SettingsSegment(value: $0, title: $0.rawValue, symbolName: $0.symbolName)
                    },
                    selection: $selection,
                    controlSize: .large
                )

                Text(selection.rawValue)
                    .font(SettingsTypography.paneTitle)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, SettingsSpacing.contentInset)
            .padding(.top, SettingsSpacing.headerTop)
            .padding(.bottom, SettingsSpacing.headerBottom)

            Group {
                switch selection {
                case .appearance:
                    SettingsAppearancePane(store: general)
                case .general:
                    SettingsGeneralPane(controller: controller, general: general)
                case .notifications:
                    SettingsNotificationsPane(controller: controller)
                case .dictation:
                    SettingsDictationPane(controller: controller)
                case .shortcuts:
                    SettingsShortcutsPane(controller: controller)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            SettingsStudioStatusNotice(controller: controller)
        }
        .settingsGlassPanel()
    }
}

#endif // os(macOS)
