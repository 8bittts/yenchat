import Foundation
import SwiftUI

@MainActor
final class GeneralSettingsStore: SettingsSnapshotStore<GeneralSettingsStore.Snapshot> {
    struct Snapshot: Equatable {
        struct Startup: Equatable {
            let launchAtLogin: Bool
            let launchAtLoginNeedsApproval: Bool
        }

        struct Font: Equatable {
            let fonts: [String]
            let fontFamily: String
            let fontSize: Double
        }

        struct Cursor: Equatable {
            let cursorStyle: String
            let cursorBlink: Bool
        }

        struct Behavior: Equatable {
            let copyOnSelect: Bool
            let persistentSessions: Bool
            let scrollbarVisibility: String
        }

        struct Appearance: Equatable {
            let backgroundOpacity: Double
            let hasBackgroundImage: Bool
            let backgroundImageDisplayTitle: String
            let backgroundImageScope: BackgroundImageScope
            let backgroundImageIssueDescription: String
            let backgroundImagePreview: PreviewImage
            let backgroundImagePreviewVersion: Int
            let windowPaddingX: Int
            let windowPaddingY: Int
            let windowBorderEnabled: Bool
            let windowBorderScope: WindowBorderScope
            let windowBorderWidth: Double
            let windowBorderRadius: Double
            let windowBorderColorMode: WindowBorderColorMode
            let windowBorderFocusedGradient: WindowBorderGradient
            let windowBorderMatchThemeStatusMessage: String
            let windowBorderMatchThemeUsesManualFallback: Bool

            /// Boxes the preview image so `Appearance` can synthesize `Equatable`
            /// (which no longer silently drops a newly-added field, as the old
            /// hand-written 22-field `==` could). The image is intentionally
            /// EXCLUDED from equality — `NSImage` isn't `Equatable` and its
            /// reference churns without a semantic change, so change detection is
            /// driven entirely by the sibling `backgroundImagePreviewVersion`
            /// (bumped on each regeneration).
            struct PreviewImage: Equatable {
                let image: NSImage?
                static func == (lhs: PreviewImage, rhs: PreviewImage) -> Bool { true }
            }
        }

        let startup: Startup
        let font: Font
        let cursor: Cursor
        let behavior: Behavior
        let appearance: Appearance

        @MainActor
        static func capture(from controller: SettingsController) -> Snapshot {
            Snapshot(
                startup: Startup(
                    launchAtLogin: controller.launchAtLogin,
                    launchAtLoginNeedsApproval: controller.launchAtLoginNeedsApproval
                ),
                font: Font(
                    fonts: controller.availableFonts,
                    fontFamily: controller.fontFamily,
                    fontSize: controller.fontSize
                ),
                cursor: Cursor(
                    cursorStyle: controller.cursorStyle,
                    cursorBlink: controller.cursorBlink
                ),
                behavior: Behavior(
                    copyOnSelect: controller.copyOnSelect,
                    persistentSessions: controller.persistentSessionsEnabled,
                    scrollbarVisibility: controller.scrollbarVisibility
                ),
                appearance: Appearance(
                    backgroundOpacity: controller.backgroundOpacity,
                    hasBackgroundImage: controller.hasBackgroundImage,
                    backgroundImageDisplayTitle: controller.backgroundImageDisplayTitle,
                    backgroundImageScope: controller.backgroundImageScope,
                    backgroundImageIssueDescription: controller.backgroundImageIssueDescription,
                    backgroundImagePreview: .init(image: controller.backgroundImagePreview),
                    backgroundImagePreviewVersion: controller.backgroundImagePreviewVersion,
                    windowPaddingX: controller.windowPaddingX,
                    windowPaddingY: controller.windowPaddingY,
                    windowBorderEnabled: controller.windowBorderEnabled,
                    windowBorderScope: controller.windowBorderScope,
                    windowBorderWidth: controller.windowBorderWidth,
                    windowBorderRadius: controller.windowBorderRadius,
                    windowBorderColorMode: controller.windowBorderColorMode,
                    windowBorderFocusedGradient: controller.windowBorderFocusedGradient,
                    windowBorderMatchThemeStatusMessage: controller.windowBorderMatchThemeStatusMessage,
                    windowBorderMatchThemeUsesManualFallback: controller.windowBorderMatchThemeUsesManualFallback
                )
            )
        }
    }

    private let controller: SettingsController

    init(controller: SettingsController) {
        self.controller = controller
        super.init(
            notification: .yenGeneralSettingsDidChange,
            object: controller,
            capture: { Snapshot.capture(from: controller) }
        )
    }

    func setLaunchAtLogin(_ value: Bool) {
        controller.launchAtLogin = value
    }

    func openLoginItemsSettings() {
        controller.openLoginItemsSettings()
    }

    func setFontFamily(_ value: String) {
        controller.fontFamily = value
    }

    func setFontSize(_ value: Double) {
        controller.fontSize = value
    }

    func setCursorStyle(_ value: String) {
        controller.cursorStyle = value
    }

    func setCursorBlink(_ value: Bool) {
        controller.cursorBlink = value
    }

    func setCopyOnSelect(_ value: Bool) {
        controller.copyOnSelect = value
    }

    func setPersistentSessions(_ value: Bool) {
        controller.persistentSessionsEnabled = value
    }

    func setScrollbarVisibility(_ value: String) {
        controller.scrollbarVisibility = value
    }

    func setBackgroundOpacity(_ value: Double) {
        controller.backgroundOpacity = value
    }

    func importBackgroundImage() {
        controller.importBackgroundImage()
    }

    func removeBackgroundImage() {
        controller.removeBackgroundImage()
    }

    func setBackgroundImageScope(_ value: BackgroundImageScope) {
        controller.backgroundImageScope = value
    }

    func setWindowPaddingX(_ value: Int) {
        controller.windowPaddingX = value
    }

    func setWindowPaddingY(_ value: Int) {
        controller.windowPaddingY = value
    }

    func setWindowBorderEnabled(_ value: Bool) {
        controller.windowBorderEnabled = value
    }

    func setWindowBorderWidth(_ value: Double) {
        controller.windowBorderWidth = value
    }

    func setWindowBorderColorMode(_ value: WindowBorderColorMode) {
        controller.windowBorderColorMode = value
    }

}
