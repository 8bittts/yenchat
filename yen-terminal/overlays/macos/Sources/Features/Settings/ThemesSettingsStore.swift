#if os(macOS)
import Foundation
import SwiftUI

@MainActor
final class ThemesSettingsStore: SettingsSnapshotStore<ThemesSettingsStore.Snapshot> {
    struct Snapshot: Equatable {
        /// The theme catalog, in display order.
        let themes: [ThemeInfo]
        let selectedTheme: String
        let isThemeCatalogLoading: Bool

        @MainActor
        static func capture(from controller: SettingsController) -> Snapshot {
            Snapshot(
                themes: controller.availableThemes,
                selectedTheme: controller.selectedTheme,
                isThemeCatalogLoading: controller.isThemeCatalogLoading
            )
        }
    }

    private let controller: SettingsController

    init(controller: SettingsController) {
        self.controller = controller
        super.init(
            notification: .yenThemesSettingsDidChange,
            object: controller,
            capture: { Snapshot.capture(from: controller) }
        )
    }

    func applyTheme(_ theme: ThemeInfo) {
        controller.applyTheme(theme)
    }
}
#endif
