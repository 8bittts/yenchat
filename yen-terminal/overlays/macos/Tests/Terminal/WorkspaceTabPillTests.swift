import AppKit
import SwiftUI
import Testing
@testable import YEN

/// The horizontal tab pill: the title at the system 13 pt medium size, the pane
/// count alone on the trailing side, and the same 12 pt inset at both ends.
/// AppKit's tab bar draws its own 11 pt regular title unless the tab carries one.
@MainActor
@Suite(.serialized)
struct WorkspaceTabPillTests {
    private struct Tab {
        let window: TitlebarTabsTahoeTerminalWindow
        let count: PaneTabIconAccessory
    }

    private static let edgeInset: CGFloat = 12

    private func makeTabs(_ titles: [String], counts: [Int]) throws -> [Tab] {
        let groupID = UUID().uuidString
        let nib = try #require(NSNib(nibNamed: "TerminalTabsTitlebarTahoe", bundle: Bundle(for: TerminalWindow.self)))
        let tabs = try zip(titles, counts).map { title, count in
            let owner = NSWindowController(window: nil)
            var objects: NSArray?
            try #require(nib.instantiate(withOwner: owner, topLevelObjects: &objects))
            let window = try #require(owner.window as? TitlebarTabsTahoeTerminalWindow)
            window.isReleasedWhenClosed = false
            window.tabbingIdentifier = groupID
            window.title = title
            window.setContentSize(NSSize(width: 900, height: 400))
            let accessory = try #require(window.tab.accessoryView as? WorkspaceTabAccessory)
            let host = PaneTabIconAccessory(rootView: PaneTabSplitCount(count: count))
            accessory.install(host, for: window)
            return Tab(window: window, count: host)
        }
        tabs[0].window.addTabbedWindow(tabs[1].window, ordered: .above)
        return tabs
    }

    private func layOut(_ tabs: [Tab], selecting selected: Tab) async throws -> NSView {
        let group = try #require(selected.window.tabGroup)
        group.selectedWindow = selected.window
        selected.window.makeKeyAndOrderFront(nil)
        selected.window.setupTabBar()
        await Task.yield()
        let root = try #require(selected.window.contentView?.superview)
        root.layoutSubtreeIfNeeded()
        return root
    }

    private func tabButton(titled title: String, in root: NSView) throws -> (button: NSView, label: NSTextField) {
        let labels = root.descendants(withClassName: "NSTextField").compactMap { $0 as? NSTextField }
        let label = try #require(labels.first { $0.stringValue == title && $0.firstSuperview(withClassName: "NSTabButton") != nil })
        let button = try #require(label.firstSuperview(withClassName: "NSTabButton"))
        return (button, label)
    }

    private func closeButton(in button: NSView) throws -> NSView {
        try #require(button.descendants(withClassName: "NSButton").first { $0.identifier?.rawValue == "_closeButton" })
    }

    @available(macOS 27, *)
    @Test func theTitleUsesTheSystemThirteenPointMediumFace() async throws {
        let tabs = try makeTabs(["Atlas", "Studio"], counts: [1, 3])
        defer { tabs.forEach { $0.window.close() } }
        let root = try await layOut(tabs, selecting: tabs[1])
        for tab in tabs {
            let label = try tabButton(titled: tab.window.title, in: root).label
            let font = try #require(label.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
            #expect(font.pointSize == NSFont.systemFontSize, "Tab \(tab.window.title) draws at \(font.pointSize) pt")
            let weight = (font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat
            #expect(weight == NSFont.Weight.medium.rawValue, "Tab \(tab.window.title) weight \(String(describing: weight))")
        }
    }

    @available(macOS 27, *)
    @Test func theCountTrailsAtTheSameInsetAsTheTitleLeads() async throws {
        let tabs = try makeTabs(["Atlas", "Studio"], counts: [2, 3])
        defer { tabs.forEach { $0.window.close() } }
        let root = try await layOut(tabs, selecting: tabs[0])
        for tab in tabs {
            let (button, label) = try tabButton(titled: tab.window.title, in: root)
            let pill = button.convert(button.bounds, to: root)
            let title = try #require(label.superview).convert(try #require(label.superview).bounds, to: root)
            let count = tab.count.convert(tab.count.bounds, to: root)
            #expect(abs(title.minX - pill.minX - Self.edgeInset) <= 0.5, "Title leads at \(title.minX - pill.minX)")
            #expect(abs(pill.maxX - count.maxX - Self.edgeInset) <= 0.5, "Count trails at \(pill.maxX - count.maxX)")
            // The x takes no room until the pointer is over the tab.
            #expect(try button.descendants(withClassName: "NSButton").allSatisfy { $0.identifier?.rawValue != "_closeButton" })
        }
    }

    @available(macOS 27, *)
    @Test func hoveringShowsTheCloseButtonAfterTheCountWithItsGlyphAtTheSameInset() async throws {
        let tabs = try makeTabs(["Atlas", "Studio"], counts: [2, 3])
        defer { tabs.forEach { $0.window.close() } }
        var root = try await layOut(tabs, selecting: tabs[0])
        let accessory = try #require(tabs[1].window.tab.accessoryView as? WorkspaceTabAccessory)
        accessory.setHovered(true)
        root.layoutSubtreeIfNeeded()
        var (button, _) = try tabButton(titled: "Studio", in: root)
        var pill = button.convert(button.bounds, to: root)
        let close = try closeButton(in: button)
        let closeFrame = close.convert(close.bounds, to: root)
        let count = tabs[1].count.convert(tabs[1].count.bounds, to: root)
        #expect(close.frame.width > 0, "The x has its slot while the pointer is over the tab")
        let inset = WorkspaceTabAccessory.closeTrailingInset
        #expect(abs(pill.maxX - closeFrame.maxX - inset) <= 0.5, "Close ends at \(pill.maxX - closeFrame.maxX)")
        #expect(count.maxX < closeFrame.minX, "Count \(count) comes before the close button \(closeFrame)")

        accessory.setHovered(false)
        root = try await layOut(tabs, selecting: tabs[0])
        (button, _) = try tabButton(titled: "Studio", in: root)
        pill = button.convert(button.bounds, to: root)
        let restored = tabs[1].count.convert(tabs[1].count.bounds, to: root)
        #expect(abs(pill.maxX - restored.maxX - Self.edgeInset) <= 0.5, "Count trails at \(pill.maxX - restored.maxX)")
    }

    @Test func aOnePaneTabShowsNoCount() {
        let host = PaneTabIconAccessory(rootView: PaneTabSplitCount(count: 1))
        #expect(!host.showsCount)
        host.rootView = PaneTabSplitCount(count: 3)
        #expect(host.showsCount)
    }
}
