#if os(macOS)
import Cocoa
import Combine
import SwiftUI

enum TabSidebarPresentationMode: String, CaseIterable {
    case transient
    case persistent
}

enum TabSidebarStatusTone: Equatable {
    case idle
    case running
    case success
    case warning
    case error
    case neutral

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .running:
            return Color.overlayAccent
        case .success:
            return Color(NSColor.systemGreen)
        case .warning:
            return Color(NSColor.systemOrange)
        case .error:
            return Color(NSColor.systemRed)
        case .neutral:
            return .primary
        }
    }
}

struct TabSidebarStatusSignal: Equatable {
    let summary: String
    let tone: TabSidebarStatusTone
}

struct TabSidebarItem: Identifiable, Equatable {
    let id: ObjectIdentifier
    let window: NSWindow
    let title: String
    let shortcut: String?
    let color: TerminalTabColor
    let isSelected: Bool
    let cwdSummary: String?
    let gitSummary: String?
    let statusSummary: String?
    let statusTone: TabSidebarStatusTone

    static func == (lhs: TabSidebarItem, rhs: TabSidebarItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.window === rhs.window &&
        lhs.title == rhs.title &&
        lhs.shortcut == rhs.shortcut &&
        lhs.color == rhs.color &&
        lhs.isSelected == rhs.isSelected &&
        lhs.cwdSummary == rhs.cwdSummary &&
        lhs.gitSummary == rhs.gitSummary &&
        lhs.statusSummary == rhs.statusSummary &&
        lhs.statusTone == rhs.statusTone
    }
}

@MainActor
class TabSidebarDataSource: NSObject, ObservableObject {
    @Published var tabs: [TabSidebarItem] = []

    func updateTabsIfNeeded(_ updatedTabs: [TabSidebarItem]) {
        guard tabs != updatedTabs else { return }
        tabs = updatedTabs
    }

    func switchToTab(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
    }

    func newTab() {}
}

#endif
