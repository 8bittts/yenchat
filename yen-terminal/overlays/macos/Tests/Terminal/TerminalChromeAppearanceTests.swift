import AppKit
import Combine
import Foundation
import SwiftUI
import Testing
import YENKit
@testable import YEN

/// The Tab Sidebar once re-derived its background from the Settings theme
/// catalog by exact name. Any state the engine resolves differently then drew
/// a rail that did not match the terminal: no `theme` line, a name that differs
/// only in case, an explicit `background`, or a theme given by path.
@MainActor
@Suite(.serialized)
struct TerminalChromeAppearanceTests {
    @Test func releasingAConfigFreesItsNativeAllocation() throws {
        let raw = try #require(yen_config_new())
        let zone = try #require(malloc_zone_from_ptr(raw))
        var probe = AllocationProbe(address: UInt(bitPattern: raw))
        var owner: YEN.Config? = YEN.Config(config: raw)
        let wasLive = withExtendedLifetime(owner) { probe.isLive(in: zone) }
        owner = nil
        let stillLive = probe.isLive(in: zone)
        #expect(wasLive)
        #expect(!stillLive)
    }

    @Test func refocusingATabUsesTheCurrentGroupWidth() throws {
        let windows = (0..<3).map { _ in
            NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                     styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        }
        windows.forEach { $0.isReleasedWhenClosed = false }
        defer { windows.forEach { $0.close() } }

        let firstContent = try #require(windows[0].contentView)
        let secondContent = try #require(windows[2].contentView)
        let firstHost = NSView()
        let secondHost = NSView()
        firstHost.translatesAutoresizingMaskIntoConstraints = false
        secondHost.translatesAutoresizingMaskIntoConstraints = false
        firstContent.addSubview(firstHost)
        secondContent.addSubview(secondHost)
        let firstStrip = WorkspaceTabStrip()
        let secondStrip = WorkspaceTabStrip()

        windows[0].addTabbedWindow(windows[1], ordered: .above)
        let group = try #require(windows[1].tabGroup)
        firstStrip.fit(firstHost, to: group)
        firstContent.layoutSubtreeIfNeeded()
        let twoTabWidth = firstHost.frame.width
        #expect(twoTabWidth > 0)

        windows[0].addTabbedWindow(windows[2], ordered: .above)
        secondStrip.fit(secondHost, to: group)
        secondContent.layoutSubtreeIfNeeded()
        #expect(secondHost.frame.width > twoTabWidth)

        group.removeWindow(windows[1])
        group.selectedWindow = windows[2]
        // The test host can stay in the background while another app owns focus.
        NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: windows[2])
        secondContent.layoutSubtreeIfNeeded()
        #expect(group.selectedWindow === windows[2])
        #expect(group.windows.count == 2)
        #expect(secondHost.frame.width == twoTabWidth)
    }

    @available(macOS 27, *)
    @Test func horizontalTabKeepsItsPaneIconBeforeItsTitleWhenSelectionChanges() async throws {
        let groupID = UUID().uuidString
        let nib = try #require(NSNib(nibNamed: "TerminalTabsTitlebarTahoe", bundle: Bundle(for: TerminalWindow.self)))
        let windows = try ["Atlas", "Studio"].map { title in
            let owner = NSWindowController(window: nil)
            var objects: NSArray?
            try #require(nib.instantiate(withOwner: owner, topLevelObjects: &objects))
            let window = try #require(owner.window as? TitlebarTabsTahoeTerminalWindow)
            window.isReleasedWhenClosed = false
            window.tabbingIdentifier = groupID
            window.title = title
            return window
        }
        defer { windows.forEach { $0.close() } }
        let icons = try windows.map { window in
            let accessory = try #require(window.tab.accessoryView as? WorkspaceTabAccessory)
            let host = PaneTabIconAccessory(rootView: PaneTabIcons(surfaces: []))
            host.widthAnchor.constraint(equalToConstant: 20).isActive = true
            host.heightAnchor.constraint(equalToConstant: 18).isActive = true
            accessory.install(host, for: window)
            return host
        }
        windows[0].addTabbedWindow(windows[1], ordered: .above)
        let group = try #require(windows[0].tabGroup)
        for selected in windows {
            group.selectedWindow = selected
            selected.makeKeyAndOrderFront(nil)
            selected.setupTabBar()
            await Task.yield()
            let root = try #require(selected.contentView?.superview)
            root.layoutSubtreeIfNeeded()
            let labels = root.descendants(withClassName: "NSTextField").compactMap { $0 as? NSTextField }
            for (index, window) in windows.enumerated() {
                let icon = icons[index]
                let title = try #require(labels.first { $0.stringValue == window.title && $0.firstSuperview(withClassName: "NSTabButton") != nil })
                #expect(icon.window === title.window)
                let iconFrame = icon.convert(icon.bounds, to: root)
                let titleFrame = title.convert(title.bounds, to: root)
                #expect(iconFrame.maxX < titleFrame.minX, "Icon \(iconFrame), title \(titleFrame), hidden \(icon.isHidden), tab \(window.title)")
            }
        }
    }

    @Test func tabStripDoesNotSetTheMinimumWindowWidth() {
        let titlebar = NSView()
        let host = NSView()
        titlebar.addSubview(host)
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: titlebar.leadingAnchor, constant: 70),
            host.trailingAnchor.constraint(lessThanOrEqualTo: titlebar.trailingAnchor),
        ])

        let tabs = WorkspaceTabStrip()
        tabs.fit(host, to: nil)
        #expect(titlebar.fittingSize.width == 70)
    }

    @Test func tabStripClearsTheFullscreenButtonsWhenTheSystemControlsAppear() {
        let titlebar = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 40))
        let tabs = NSView()
        let buttons = NSView()
        for view in [tabs, buttons] {
            titlebar.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        let buttonsStart = buttons.leftAnchor.constraint(equalTo: titlebar.leftAnchor)
        NSLayoutConstraint.activate([
            WorkspaceTabStrip.start(tabs, at: titlebar.leftAnchor, inset: 70),
            tabs.rightAnchor.constraint(lessThanOrEqualTo: titlebar.rightAnchor),
            buttons.widthAnchor.constraint(equalToConstant: 62),
            buttonsStart,
        ])
        let strip = WorkspaceTabStrip()
        strip.fit(tabs, to: nil)
        strip.place(after: buttons)
        for inset: CGFloat in [0, 81, 0] {
            buttonsStart.constant = inset
            titlebar.layoutSubtreeIfNeeded()
            #expect(tabs.frame.minX >= buttons.frame.maxX)
            if inset == 0 { #expect(tabs.frame.minX == 70) }
        }
    }

    @Test func startsFromTheEngineResolvedBackground() throws {
        let config = try TemporaryConfig("background = #112233\n")
        let appearance = TerminalChromeAppearance(
            config: config,
            notificationCenter: NotificationCenter()
        )

        #expect(rgb(appearance.backgroundColor) == RGB(red: 0x11, green: 0x22, blue: 0x33))
    }

    @Test func explicitBackgroundWinsWithoutAnyTheme() throws {
        // No `theme` key at all: the catalog lookup had nothing to match and fell
        // back to the system window color while the terminal drew this one.
        let config = try TemporaryConfig("background = #0a0b0c\nforeground = #ffffff\n")
        let appearance = TerminalChromeAppearance(
            config: config,
            notificationCenter: NotificationCenter()
        )

        #expect(rgb(appearance.backgroundColor) == RGB(red: 0x0a, green: 0x0b, blue: 0x0c))
    }

    @Test func followsAppLevelConfigChanges() throws {
        let center = NotificationCenter()
        let appearance = TerminalChromeAppearance(
            config: try TemporaryConfig("background = #112233\n"),
            notificationCenter: center
        )
        var emissionCount = 0
        let cancellable = appearance.objectWillChange.sink { emissionCount += 1 }
        defer { cancellable.cancel() }

        let updated = try TemporaryConfig("background = #445566\n")
        center.post(
            name: .yenConfigDidChange,
            object: nil,
            userInfo: [Notification.Name.YENConfigChangeKey: updated]
        )

        #expect(rgb(appearance.backgroundColor) == RGB(red: 0x44, green: 0x55, blue: 0x66))
        #expect(emissionCount == 1)

        // An unchanged color must not republish; the rail would redraw on every reload.
        center.post(
            name: .yenConfigDidChange,
            object: nil,
            userInfo: [Notification.Name.YENConfigChangeKey: updated]
        )

        #expect(emissionCount == 1)
    }

    @Test func ignoresSurfaceLevelConfigChanges() throws {
        let center = NotificationCenter()
        let appearance = TerminalChromeAppearance(
            config: try TemporaryConfig("background = #112233\n"),
            notificationCenter: center
        )

        // A surface-level change carries its surface as the object. One pane's
        // config must not recolor chrome shared by the whole window.
        center.post(
            name: .yenConfigDidChange,
            object: NSObject(),
            userInfo: [
                Notification.Name.YENConfigChangeKey: try TemporaryConfig("background = #ff0000\n"),
            ]
        )

        #expect(rgb(appearance.backgroundColor) == RGB(red: 0x11, green: 0x22, blue: 0x33))
    }

    @Test func fallsBackToTheSystemWindowColorWithoutAConfig() {
        let appearance = TerminalChromeAppearance(
            config: nil,
            notificationCenter: NotificationCenter()
        )

        #expect(appearance.backgroundColor == Color(NSColor.windowBackgroundColor))
    }

    private struct RGB: Equatable {
        let red: Int
        let green: Int
        let blue: Int
    }

    private func rgb(_ color: Color) -> RGB? {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return RGB(
            red: Int((converted.redComponent * 255).rounded()),
            green: Int((converted.greenComponent * 255).rounded()),
            blue: Int((converted.blueComponent * 255).rounded())
        )
    }
}

// Observe the allocation without dereferencing a pointer after its owner goes away.
private struct AllocationProbe {
    let address: UInt
    var found = false

    mutating func isLive(in zone: UnsafeMutablePointer<malloc_zone_t>) -> Bool {
        found = false
        let status = zone.pointee.introspect.pointee.enumerator(
            mach_task_self_, &self, UInt32(MALLOC_PTR_IN_USE_RANGE_TYPE), UInt(bitPattern: zone), nil
        ) { _, context, _, ranges, count in
            guard let context, let ranges else { return }
            let probe = context.assumingMemoryBound(to: AllocationProbe.self)
            for range in UnsafeBufferPointer(start: ranges, count: Int(count)) where range.address == probe.pointee.address {
                probe.pointee.found = true
            }
        }
        precondition(status == KERN_SUCCESS)
        return found
    }
}
