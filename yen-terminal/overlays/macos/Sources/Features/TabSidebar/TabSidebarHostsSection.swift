#if os(macOS)
import AppKit
import Combine
import SwiftUI

/// The tab sidebar's Hosts section: the user's other Macs and their sessions,
/// from `RemoteHostsStore`, with the palette's rows and actions
/// (`RemoteHostsPaletteRows`).
///
/// The sidebar can stay open all day, so an open sidebar is not Hosts intent.
/// The section starts collapsed in every new sidebar, and discovery (and its
/// timer) runs only while the section is expanded and the sidebar is showing.
@MainActor
final class TabSidebarHostsSection: ObservableObject {
    /// One sidebar row: a palette row without its "Hosts: " prefix.
    struct Row: Identifiable, Equatable {
        let entry: RemoteHostsPaletteEntry
        var id: String { entry.id }
        var title: String { TabSidebarHostsSection.displayTitle(entry.title) }
    }

    @Published private(set) var isExpanded = false
    @Published private(set) var rows: [Row] = []
    private(set) var isShowing = false

    private let store: RemoteHostsStore
    private let isOpenHere: @MainActor (RemotePaneIdentity) -> Bool
    private var snapshotSubscription: AnyCancellable?

    init(
        store: RemoteHostsStore? = nil,
        isOpenHere: (@MainActor (RemotePaneIdentity) -> Bool)? = nil
    ) {
        self.store = store ?? .shared
        self.isOpenHere = isOpenHere ?? { identity in RemotePanes.existingPane(for: identity) != nil }
    }

    nonisolated static func wantsDiscovery(expanded: Bool, showing: Bool) -> Bool {
        expanded && showing
    }

    nonisolated static func displayTitle(_ title: String) -> String {
        title.hasPrefix(RemoteHostsPaletteRows.titlePrefix)
            ? String(title.dropFirst(RemoteHostsPaletteRows.titlePrefix.count))
            : title
    }

    nonisolated static func accessibilityLabel(for row: Row) -> String {
        [row.title, row.entry.subtitle].compactMap { $0 }.joined(separator: ", ")
    }

    var isDiscovering: Bool { snapshotSubscription != nil }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        sync()
    }

    func toggleExpanded() { setExpanded(!isExpanded) }

    func setShowing(_ showing: Bool) {
        guard isShowing != showing else { return }
        isShowing = showing
        sync()
    }

    private func sync() {
        if Self.wantsDiscovery(expanded: isExpanded, showing: isShowing) {
            guard snapshotSubscription == nil else { return }
            store.surfaceDidAppear(self)
            // Rows follow the store's answers while the section is open.
            snapshotSubscription = store.$snapshot.sink { [weak self] snapshot in
                self?.rebuild(snapshot)
            }
        } else {
            guard snapshotSubscription != nil else { return }
            snapshotSubscription = nil
            store.surfaceDidDisappear(self)
        }
    }

    private func rebuild(_ snapshot: RemoteHostsStore.Snapshot) {
        let isOpenHere = self.isOpenHere
        let updated = RemoteHostsPaletteRows.entries(snapshot: snapshot, isOpenHere: { isOpenHere($0) }).map(Row.init)
        if updated != rows { rows = updated }
    }

    /// Run a row's action. `window` is the sidebar's terminal window; a typed
    /// command goes only into its focused pane, and only when that pane is local.
    func perform(_ row: Row, in window: NSWindow?) {
        switch row.entry.action {
        case .attach(let identity):
            _ = RemotePanes.open(identity, from: window)
        case .refresh:
            store.refresh()
        case .insertCommand(let command):
            guard let surface = (window?.windowController as? BaseTerminalController)?.focusedSurface,
                  surface.remotePaneIdentity == nil else { return }
            TerminalCommandPaletteView.insertCommand(command, into: surface)
        case .showHosts:
            setExpanded(true)
        }
    }

    deinit {
        // A section that goes away must not leave the store's timer running.
        MainActor.assumeIsolated {
            guard snapshotSubscription != nil else { return }
            store.surfaceDidDisappear(id: ObjectIdentifier(self))
        }
    }
}

/// The Hosts section under the tab list: a disclosure row while collapsed,
/// the Hosts rows while expanded.
struct TabSidebarHostsSectionView: View {
    @ObservedObject var section: TabSidebarHostsSection
    let targetWindow: () -> NSWindow?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button(action: { section.toggleExpanded() }) {
                HStack(spacing: 8) {
                    Image(systemName: section.isExpanded ? "chevron.down" : "chevron.right")
                        .settingsScaledSystemFont(size: 10, weight: .semibold)
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text("Hosts")
                        .settingsScaledSystemFont(size: 12.5, weight: .semibold)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(section.isExpanded ? "Hide your other Macs" : "Show your other Macs on Tailscale and their sessions")
            .accessibilityLabel("Hosts")
            .accessibilityValue(section.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(section.isExpanded ? "Hides your other Macs" : "Shows your other Macs on Tailscale and their sessions")

            if section.isExpanded {
                ForEach(section.rows) { row in
                    TabSidebarHostsRow(row: row) {
                        section.perform(row, in: targetWindow())
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: section.isExpanded)
    }
}

private struct TabSidebarHostsRow: View {
    let row: TabSidebarHostsSection.Row
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: row.entry.leadingIcon)
                    .settingsScaledSystemFont(size: 11)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .settingsScaledSystemFont(size: 12, weight: .medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle = row.entry.subtitle {
                        Text(subtitle)
                            .settingsScaledSystemFont(size: 11)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: YENDesignTokens.terminalFacingCornerRadius, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(row.entry.description)
        // The Button keeps its press action for VoiceOver and AX clients; a
        // replaced accessibility element would drop it.
        .accessibilityLabel(TabSidebarHostsSection.accessibilityLabel(for: row))
        .accessibilityHint(row.entry.description)
    }
}
#endif
