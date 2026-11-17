import Combine
import Foundation

@MainActor
final class TerminalPresentationSettings: ObservableObject {
    struct Snapshot: Equatable {
        let backgroundImagePath: String
        let backgroundImageScope: BackgroundImageScope
        let backgroundOpacity: Double
        let wholeWindowBackgroundImageEnabled: Bool
        let windowBorderEnabled: Bool
        let windowBorderScope: WindowBorderScope
        let windowBorderWidth: Double
        let windowBorderRadius: Double
        let windowBorderFocusedGradient: WindowBorderGradient
        let windowBorderUnfocusedGradient: WindowBorderGradient

        @MainActor
        static func capture(from settingsController: SettingsController) -> Snapshot {
            Snapshot(
                backgroundImagePath: settingsController.backgroundImagePath,
                backgroundImageScope: settingsController.backgroundImageScope,
                backgroundOpacity: settingsController.backgroundOpacity,
                wholeWindowBackgroundImageEnabled: settingsController.wholeWindowBackgroundImageEnabled,
                windowBorderEnabled: settingsController.windowBorderEnabled,
                windowBorderScope: settingsController.windowBorderScope,
                windowBorderWidth: settingsController.windowBorderWidth,
                windowBorderRadius: settingsController.windowBorderRadius,
                windowBorderFocusedGradient: settingsController.windowBorderFocusedGradient,
                windowBorderUnfocusedGradient: settingsController.windowBorderUnfocusedGradient
            )
        }
    }

    static let shared = TerminalPresentationSettings()

    @Published private(set) var snapshot: Snapshot

    private let settingsController: SettingsController
    private var cancellables: Set<AnyCancellable> = []

    init(settingsController: SettingsController? = nil) {
        let settingsController = settingsController ?? .shared
        self.settingsController = settingsController
        self.snapshot = Snapshot.capture(from: settingsController)

        NotificationCenter.default.publisher(
            for: .yenTerminalPresentationSettingsDidChange,
            object: settingsController
        )
            .sink { [weak self] _ in
                self?.refreshIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func refreshIfNeeded() {
        let updatedSnapshot = Snapshot.capture(from: settingsController)
        guard updatedSnapshot != snapshot else { return }
        snapshot = updatedSnapshot
    }
}

@MainActor
final class SplitPaneLabelSettings: ObservableObject {
    static let shared = SplitPaneLabelSettings()

    @Published private(set) var isEnabled: Bool
    /// True only when split labels are on AND worktree naming is on, so callers never have to
    /// re-check the parent toggle.
    @Published private(set) var isWorktreeNamingEnabled: Bool

    private let settingsController: SettingsController
    private var cancellables: Set<AnyCancellable> = []

    init(settingsController: SettingsController? = nil) {
        let settingsController = settingsController ?? .shared
        self.settingsController = settingsController
        self.isEnabled = settingsController.splitPaneLabelsEnabled
        self.isWorktreeNamingEnabled = Self.worktreeNamingEnabled(in: settingsController)

        NotificationCenter.default.publisher(
            for: .yenSplitPaneLabelSettingsDidChange,
            object: settingsController
        )
            .sink { [weak self] _ in
                self?.refreshIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func refreshIfNeeded() {
        let updatedValue = settingsController.splitPaneLabelsEnabled
        if updatedValue != isEnabled {
            isEnabled = updatedValue
        }

        let updatedWorktreeNaming = Self.worktreeNamingEnabled(in: settingsController)
        if updatedWorktreeNaming != isWorktreeNamingEnabled {
            isWorktreeNamingEnabled = updatedWorktreeNaming
        }
    }

    private static func worktreeNamingEnabled(in controller: SettingsController) -> Bool {
        controller.splitPaneLabelsEnabled && controller.splitPaneWorktreeNamingEnabled
    }
}

extension Notification.Name {
    static let yenTerminalPresentationSettingsDidChange = Notification.Name(
        "yenTerminalPresentationSettingsDidChange"
    )
    static let yenSplitPaneLabelSettingsDidChange = Notification.Name(
        "yenSplitPaneLabelSettingsDidChange"
    )
}
