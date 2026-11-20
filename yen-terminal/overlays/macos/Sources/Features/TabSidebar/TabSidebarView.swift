#if os(macOS)
import SwiftUI

enum TabSidebarStyle {
	case floating
	case docked
}

/// Builds sidebar hosting views whose size is owned by AppKit.
///
/// Both presentation modes have an explicit external frame: the transient panel
/// mirrors its terminal window, while the docked rail is pinned by constraints.
/// Keeping content-derived sizing enabled lets a short intrinsic SwiftUI tree
/// resize or center itself inside that frame when only a few tabs are open.
@MainActor
enum TabSidebarHostingViewFactory {
	static func make<Model: TabSidebarDataSource>(
		model: Model,
		style: TabSidebarStyle
	) -> NSHostingView<TabSidebarView<Model>> {
		let hostingView = NSHostingView(rootView: TabSidebarView(model: model, style: style))
		if #available(macOS 13.0, *) {
			hostingView.sizingOptions = []
		}
		return hostingView
	}
}

struct TabSidebarRowAccessibilityDescriptor: Equatable {
	static let renameActionName = "Rename"

	let label: String
	let value: String
	let hint: String
	let showsRenameAction: Bool

	init(tab: TabSidebarItem, isEditingTitle: Bool) {
		var parts = [tab.title]
		if let cwdSummary = tab.cwdSummary {
			parts.append(cwdSummary)
		}
		if let gitSummary = tab.gitSummary {
			parts.append(gitSummary)
		}
		if let statusSummary = tab.statusSummary {
			parts.append(statusSummary)
		}
		if let shortcut = tab.shortcut {
			parts.append("Command \(shortcut)")
		}

		label = parts.joined(separator: ", ")
		value = isEditingTitle ? "Editing title" : (tab.isSelected ? "Selected" : "Not selected")
		hint = isEditingTitle
			? "Finish or cancel the rename to return to the tab list."
			: "Opens this tab. Use the Rename action or context menu to rename."
		showsRenameAction = !isEditingTitle
	}
}

struct TabSidebarColorControlAccessibilityDescriptor: Equatable {
	let label: String
	let hint: String

	init(color: TerminalTabColor) {
		label = "Tab color: \(color.localizedName)"
		hint = "Change tab color"
	}
}

/// SwiftUI view for the tab sidebar.
/// Shared between the transient floating panel and the persistent docked rail.
struct TabSidebarView<Model: TabSidebarDataSource>: View {
	@ObservedObject var model: Model
	let style: TabSidebarStyle

	// Standardized terminal-facing corner radius, shared with the Scratchpad,
	// Git Drawer, and Quick Terminal (10pt continuous).
	private var cornerRadius: CGFloat { YENDesignTokens.terminalFacingCornerRadius }

	private var bodyPadding: CGFloat { 10 }

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			header

			ScrollView {
				LazyVStack(alignment: .leading, spacing: 3) {
					ForEach(model.tabs) { tab in
						TabSidebarRow(tab: tab, style: style, accentColor: Color.overlayAccent) {
							model.switchToTab(tab.window)
						}
					}
				}
				.padding(.horizontal, bodyPadding)
				.padding(.vertical, 6)
				.accessibilityElement(children: .contain)
				.accessibilityLabel("Open tabs")
			}

			Spacer(minLength: 0)

			footer
		}
		.frame(width: TabSidebarController.panelWidth)
		.background(SidebarBackgroundView(style: style))
		.modifier(SidebarClipModifier(cornerRadius: cornerRadius))
	}

	private var header: some View {
		SidebarHeaderView(
			tabCount: model.tabs.count,
			style: style,
			bodyPadding: bodyPadding
		)
	}

	private var footer: some View {
		SidebarFooterView(
			style: style,
			bodyPadding: bodyPadding,
			newTab: model.newTab
		)
	}
}

/// Scoped view that observes SettingsController only for sidebar header actions.
private struct SidebarHeaderView: View {
	@ObservedObject private var settings = SettingsController.shared
	let tabCount: Int
	let style: TabSidebarStyle
	let bodyPadding: CGFloat

	var body: some View {
		HStack(alignment: .center, spacing: 10) {
			Text("Tabs")
				.settingsScaledSystemFont(size: 13, weight: .semibold)
			Text("\(tabCount)")
				.settingsScaledSystemFont(size: 11, weight: .medium)
				.foregroundColor(.secondary)
				.accessibilityLabel("\(tabCount) open tabs")

			Spacer(minLength: 0)

			Button(action: togglePersistentMode) {
				Image(systemName: settings.tabSidebarPresentationMode == .persistent ? "pin.fill" : "pin")
					.settingsScaledSystemFont(size: 12, weight: .semibold)
					.foregroundColor(settings.tabSidebarPresentationMode == .persistent ? Color.overlayAccent : .secondary)
					.frame(width: 28, height: 28)
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel(settings.tabSidebarPresentationMode == .persistent ? "Switch to transient tab sidebar" : "Pin tab sidebar inside terminal windows")
			.help(settings.tabSidebarPresentationMode == .persistent ? "Switch to transient sidebar" : "Pin sidebar inside terminal windows")

			Button(action: openWorkspaceSettings) {
				Image(systemName: "gearshape")
					.settingsScaledSystemFont(size: 12, weight: .semibold)
					.foregroundColor(.secondary)
					.frame(width: 28, height: 28)
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Open tab sidebar settings")
			.help("Open General settings")
		}
		.padding(.horizontal, bodyPadding)
		.padding(.top, style == .floating ? 12 : 10)
		.padding(.bottom, 10)
		.overlay(alignment: .bottom) {
			Divider()
				.opacity(style == .floating ? 0.35 : 0.6)
		}
	}

	private func togglePersistentMode() {
		let nextMode: TabSidebarPresentationMode =
			settings.tabSidebarPresentationMode == .persistent ? .transient : .persistent
		settings.tabSidebarPresentationMode = nextMode
	}

	private func openWorkspaceSettings() {
		SettingsController.shared.show(pane: .general)
	}
}

private struct SidebarFooterView: View {
	let style: TabSidebarStyle
	let bodyPadding: CGFloat
	let newTab: () -> Void

	var body: some View {
		HStack(spacing: 8) {
			Button(action: newTab) {
				HStack(spacing: 6) {
					Image(systemName: "plus")
						.settingsScaledSystemFont(size: 11, weight: .semibold)
					Text("New Tab")
						.settingsScaledSystemFont(size: 12, weight: .medium)
				}
				.foregroundColor(.secondary)
				.padding(.horizontal, 12)
				.padding(.vertical, 8)
				.background(Color.primary.opacity(0.05))
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
			}
			.buttonStyle(.plain)

			Spacer(minLength: 0)
		}
		.padding(.horizontal, bodyPadding)
		.padding(.top, 10)
		.padding(.bottom, style == .floating ? 10 : 12)
		.overlay(alignment: .top) {
			Divider()
				.opacity(style == .floating ? 0.35 : 0.6)
		}
	}
}

/// Scoped view that follows the terminal's resolved background color.
/// Theme updates stay localized here instead of invalidating the full sidebar tree.
private struct SidebarBackgroundView: View {
	@ObservedObject private var chrome = TerminalChromeAppearance.shared
	let style: TabSidebarStyle

	var body: some View {
		// Both styles sit flush against the window's leading edge, so the background
		// fills the rail and a 1pt border marks the terminal-facing trailing edge.
		ZStack {
			VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
			chrome.backgroundColor.opacity(style == .floating ? 0.9 : 0.96)
		}
		.overlay(alignment: .trailing) {
			Rectangle()
				.fill(borderColor)
				.frame(width: 1)
		}
	}

	private var borderColor: Color {
		Color(NSColor.separatorColor).opacity(0.45)
	}
}

private struct SidebarClipModifier: ViewModifier {
	let cornerRadius: CGFloat

	func body(content: Content) -> some View {
		// The Tab Sidebar is the left panel, so its trailing (right) edge faces into
		// the terminal. Both styles are flush against the window's leading edge: the
		// docked rail expands the window, and the transient panel rests inside it and
		// reveals from behind that edge. Only the terminal-facing trailing corners
		// round here; the transient panel's `EdgeRevealView` rounds the outer corners
		// it shares with the window to the window's own radius.
		content.clipShape(
			UnevenRoundedRectangle(
				topLeadingRadius: 0,
				bottomLeadingRadius: 0,
				bottomTrailingRadius: cornerRadius,
				topTrailingRadius: cornerRadius,
				style: .continuous
			)
		)
	}
}

enum TabSidebarInlineRenameResolver {
	static func resolvedTitleOverride(
		draftTitle: String,
		initialDraftTitle: String,
		existingOverride: String?
	) -> String? {
		guard !draftTitle.isEmpty else { return nil }
		if existingOverride == nil, draftTitle == initialDraftTitle {
			return nil
		}
		return draftTitle
	}
}

enum TabSidebarRenameInteraction: Equatable {
	case sidebarInline
	case nativeWindow

	static func resolve(for style: TabSidebarStyle) -> Self {
		switch style {
		case .docked:
			return .sidebarInline
		case .floating:
			// Floating panels intentionally stay non-key, so hand transient rename
			// off to the existing terminal-window title editor instead.
			return .nativeWindow
		}
	}
}

/// A single tab row in the sidebar.
private struct TabSidebarRow: View {
	let tab: TabSidebarItem
	let style: TabSidebarStyle
	let accentColor: Color
	let action: () -> Void
	@Environment(\.accessibilityReduceMotion) private var reduceMotion
	@State private var isHovered = false
	@State private var isEditingTitle = false
	@State private var draftTitle = ""
	@State private var initialDraftTitle = ""
	@FocusState private var titleFieldFocused: Bool

	private var controller: BaseTerminalController? {
		tab.window.windowController as? BaseTerminalController
	}

	private var terminalWindow: TerminalWindow? {
		tab.window as? TerminalWindow
	}

	private var rowBackground: Color {
		if tab.isSelected { return Color.primary.opacity(0.12) }
		return isHovered ? Color.primary.opacity(0.06) : .clear
	}

	private var rowAnimation: Animation? {
		reduceMotion ? nil : .easeOut(duration: 0.12)
	}

	private var rowCornerRadius: CGFloat {
		YENDesignTokens.terminalFacingCornerRadius
	}

	private var rowHorizontalPadding: CGFloat {
		8
	}

	private var rowVerticalPadding: CGFloat {
		5
	}

	private var accessibilityDescriptor: TabSidebarRowAccessibilityDescriptor {
		TabSidebarRowAccessibilityDescriptor(tab: tab, isEditingTitle: isEditingTitle)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 5) {
			HStack(alignment: .center, spacing: 8) {
				tabColorMenu

				titleView

				Spacer(minLength: 0)

				if let shortcut = tab.shortcut {
					Text("⌘\(shortcut)")
						.settingsScaledSystemFont(size: 10, design: .monospaced)
						.foregroundColor(.secondary)
				}
			}

			rowMetadataView
				.padding(.leading, 32)
		}
		.padding(.horizontal, rowHorizontalPadding)
		.padding(.vertical, rowVerticalPadding)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(
			RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
				.fill(rowBackground)
		)
		.contentShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
		.onHover { hovering in
			isHovered = hovering
		}
		.onTapGesture {
			guard !isEditingTitle else { return }
			action()
		}
		.contextMenu {
			rowContextMenu
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityDescriptor.label)
		.accessibilityValue(accessibilityDescriptor.value)
		.accessibilityHint(accessibilityDescriptor.hint)
		.accessibilityAddTraits(.isButton)
		.accessibilityAddTraits(tab.isSelected ? .isSelected : [])
		.accessibilityAction {
			guard !isEditingTitle else { return }
			action()
		}
		.accessibilityAction(named: TabSidebarRowAccessibilityDescriptor.renameActionName) {
			guard accessibilityDescriptor.showsRenameAction else { return }
			beginRenameInteraction()
		}
		.animation(rowAnimation, value: isHovered)
		.animation(rowAnimation, value: tab.isSelected)
	}

	@ViewBuilder
	private var rowMetadataView: some View {
		if tab.cwdSummary != nil || tab.gitSummary != nil || tab.statusSummary != nil {
			HStack(alignment: .center, spacing: 6) {
				if let cwdSummary = tab.cwdSummary {
					Text(cwdSummary)
						.lineLimit(1)
						.truncationMode(.middle)
				}

				if let gitSummary = tab.gitSummary {
					if tab.cwdSummary != nil {
						rowMetadataSeparator
					}
					Text(gitSummary)
						.lineLimit(1)
						.truncationMode(.tail)
				}

				if let statusSummary = tab.statusSummary {
					if tab.cwdSummary != nil || tab.gitSummary != nil {
						Spacer(minLength: 0)
					}
					HStack(spacing: 4) {
						Circle()
							.fill(tab.statusTone.color)
							.frame(width: 6, height: 6)
						Text(statusSummary)
							.lineLimit(1)
							.truncationMode(.tail)
					}
					.foregroundColor(tab.statusTone.color)
				}
			}
			.settingsScaledSystemFont(size: 11)
			.foregroundColor(.secondary)
		}
	}

	private var rowMetadataSeparator: some View {
		Circle()
			.fill(Color.secondary.opacity(0.55))
			.frame(width: 3, height: 3)
	}

	@ViewBuilder
	private var titleView: some View {
		if isEditingTitle {
			TextField("", text: $draftTitle, prompt: Text("Untitled Tab"))
				.textFieldStyle(.plain)
				.settingsScaledSystemFont(size: 12.5, weight: .semibold)
				.foregroundColor(.primary)
				.focused($titleFieldFocused)
				.onSubmit {
					commitInlineRename()
				}
				.onExitCommand {
					cancelInlineRename()
				}
				.onAppear {
					DispatchQueue.main.async {
						titleFieldFocused = true
					}
				}
				.onChange(of: titleFieldFocused) { focused in
					guard isEditingTitle, !focused else { return }
					commitInlineRename()
				}
				.padding(.horizontal, 6)
				.padding(.vertical, 4)
				.background(
					RoundedRectangle(cornerRadius: 7, style: .continuous)
						.fill(Color.primary.opacity(0.08))
				)
				.overlay(
					RoundedRectangle(cornerRadius: 7, style: .continuous)
						.stroke(accentColor.opacity(0.45), lineWidth: 1)
				)
				.frame(maxWidth: .infinity, alignment: .leading)
		} else {
			Text(tab.title)
				.settingsScaledSystemFont(size: 12.5, weight: tab.isSelected ? .semibold : .medium)
				.lineLimit(1)
				.truncationMode(.tail)
				.foregroundColor(.primary)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	private var tabColorMenu: some View {
		Menu {
			ForEach(TerminalTabColor.allCases, id: \.self) { color in
				Button {
					changeTabColor(to: color)
				} label: {
					HStack(spacing: 8) {
						TabSidebarColorSwatch(color: color)
						Text(color.localizedName)
						if color == tab.color {
							Image(systemName: "checkmark")
						}
					}
				}
			}
		} label: {
			TabSidebarColorControl(color: tab.color, isSelected: tab.isSelected, isHovered: isHovered)
		}
		.buttonStyle(.plain)
		.help("Change tab color")
	}

	@ViewBuilder
	private var rowContextMenu: some View {
		if let controller = tab.window.windowController as? TerminalController {
			Button("Change Title...") {
				beginRenameInteraction()
			}
			Divider()
			Button("Close Tab") {
				controller.closeTab(nil)
			}
			Button("Close Other Tabs") {
				controller.closeOtherTabs(nil)
			}
			Button("Close Tabs to the Right") {
				controller.closeTabsOnTheRight(nil)
			}
			Divider()
			Menu("Tab Color") {
				ForEach(TerminalTabColor.allCases, id: \.self) { color in
					Button {
						changeTabColor(to: color)
					} label: {
						HStack {
							Text(color.localizedName)
							if color == tab.color {
								Image(systemName: "checkmark")
							}
						}
					}
				}
			}
		} else {
			Button("Change Title...") {
				beginRenameInteraction()
			}
			Divider()
			Button("Close Tab") {
				tab.window.performClose(nil)
			}
		}
	}

	private func changeTabColor(to color: TerminalTabColor) {
		terminalWindow?.tabColor = color
	}

	private func beginRenameInteraction() {
		switch TabSidebarRenameInteraction.resolve(for: style) {
		case .sidebarInline:
			beginInlineRename()
		case .nativeWindow:
			beginNativeWindowRename()
		}
	}

	private func beginInlineRename() {
		guard let controller else {
			return
		}
		action()
		let startingTitle = controller.titleOverride ?? tab.title
		draftTitle = startingTitle
		initialDraftTitle = startingTitle
		isEditingTitle = true
	}

	private func beginNativeWindowRename() {
		guard let controller else {
			return
		}
		action()
		DispatchQueue.main.async {
			controller.changeTabTitle(self.tab.window as Any)
		}
	}

	private func cancelInlineRename() {
		isEditingTitle = false
		titleFieldFocused = false
		draftTitle = ""
		initialDraftTitle = ""
	}

	private func commitInlineRename() {
		guard let controller else {
			cancelInlineRename()
			return
		}

		controller.titleOverride = TabSidebarInlineRenameResolver.resolvedTitleOverride(
			draftTitle: draftTitle,
			initialDraftTitle: initialDraftTitle,
			existingOverride: controller.titleOverride
		)
		isEditingTitle = false
		titleFieldFocused = false
		draftTitle = ""
		initialDraftTitle = ""
	}
}

private struct TabSidebarColorControl: View {
	let color: TerminalTabColor
	let isSelected: Bool
	let isHovered: Bool

	private var accessibilityDescriptor: TabSidebarColorControlAccessibilityDescriptor {
		TabSidebarColorControlAccessibilityDescriptor(color: color)
	}

	var body: some View {
		Group {
			if color == .none {
				Image(systemName: "terminal")
					.settingsScaledSystemFont(size: 13, weight: .medium)
					.foregroundColor(isSelected || isHovered ? .primary : .secondary)
			} else {
				TabSidebarColorSwatch(color: color)
			}
		}
		.frame(width: 24, height: 24)
		.contentShape(Rectangle())
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityDescriptor.label)
		.accessibilityHint(accessibilityDescriptor.hint)
		.accessibilityAddTraits(.isButton)
	}
}

private struct TabSidebarColorSwatch: View {
	let color: TerminalTabColor
	var diameter: CGFloat = 10

	var body: some View {
		Circle()
			.fill(color.displayColor.map { Color(nsColor: $0) } ?? Color.clear)
			.overlay(
				Circle()
					.strokeBorder(Color.secondary.opacity(color == .none ? 0.45 : 0), lineWidth: 1)
			)
			.overlay {
				if color == .none {
					Rectangle()
						.fill(Color.secondary)
						.frame(width: diameter * 0.8, height: max(1, diameter * 0.12))
						.rotationEffect(.degrees(-45))
				}
			}
			.frame(width: diameter, height: diameter)
	}
}
#endif
