import Combine
import SwiftUI

/// The engine's resolved terminal background, republished for chrome that sits
/// beside the terminal, such as the Tab Sidebar rail.
///
/// Chrome must read this value and never re-derive it from the theme catalog.
/// The engine loads the theme and then replays every loaded config file over
/// it, and it accepts references the catalog cannot match by name: an absolute
/// path, a `light:,dark:` pair, or no theme at all. Only the finalized config
/// holds the color the terminal draws.
@MainActor
final class TerminalChromeAppearance: ObservableObject {
    static let shared = TerminalChromeAppearance(config: AppDelegate.shared?.yen.config)

    @Published private(set) var backgroundColor: Color

    private var cancellables: Set<AnyCancellable> = []

    init(config: YEN.Config?, notificationCenter: NotificationCenter = .default) {
        self.backgroundColor = Self.resolvedBackgroundColor(for: config)

        notificationCenter.publisher(for: .yenConfigDidChange)
            .sink { [weak self] notification in
                // A surface-level change carries that surface as its object. Chrome
                // follows the app-level config, which is posted with a nil object.
                guard notification.object == nil,
                      let config = notification.userInfo?[
                          Notification.Name.YENConfigChangeKey
                      ] as? YEN.Config else { return }
                self?.apply(config)
            }
            .store(in: &cancellables)
    }

    private func apply(_ config: YEN.Config) {
        let updatedColor = Self.resolvedBackgroundColor(for: config)
        guard updatedColor != backgroundColor else { return }
        backgroundColor = updatedColor
    }

    private static func resolvedBackgroundColor(for config: YEN.Config?) -> Color {
        config?.backgroundColor ?? Color(NSColor.windowBackgroundColor)
    }
}
