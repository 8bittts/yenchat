import CoreGraphics
import Foundation

/// Inputs the status menu needs from live wallpaper and updater state.
/// Built by `WallpaperManager`; rendered by `StatusBarController`.
@available(macOS 27.0, *)
struct MenuModelInput: Equatable {
    var downloadProgress: Double?
    var mode: WallpaperMode
    var isMuted: Bool
    var isPaused: Bool
    var hasAnyWallpaper: Bool
    var sharedFileName: String?
    var displays: [DisplayMenuInput]
}

@available(macOS 27.0, *)
struct DisplayMenuInput: Equatable {
    var id: CGDirectDisplayID
    var name: String
    var spaces: [SpaceMenuInput]
}

@available(macOS 27.0, *)
struct SpaceMenuInput: Equatable {
    var fileName: String?
    var isCurrent: Bool
}

@available(macOS 27.0, *)
enum MenuCommandID: Equatable {
    case cancelDownload
    case chooseFile
    case pasteYouTube
    case choosePhotos
    case shufflePhotos
    case clearAll
    case clearDisplay
    case toggleMute
    case togglePause
    case togglePerDesktop
}

@available(macOS 27.0, *)
struct MenuCommand: Equatable {
    var title: String
    var id: MenuCommandID
    var enabled: Bool = true
    var checked: Bool = false
    var displayID: CGDirectDisplayID? = nil
    var keyEquivalent: String = ""
    /// SF Symbol shown beside the title. Every command in a group has one or none does.
    var symbolName: String? = nil
}

@available(macOS 27.0, *)
enum MenuRow: Equatable {
    case disabled(String)
    case separator
    case sectionHeader(String)
    case command(MenuCommand)
    case submenu(title: String, checked: Bool = false, rows: [MenuRow])
}

/// Native menu rows for the wallpaper controls in General settings.
@available(macOS 27.0, *)
enum MenuSnapshot {
    static func rows(from input: MenuModelInput) -> [MenuRow] {
        var rows: [MenuRow] = []
        rows.append(contentsOf: downloadRows(progress: input.downloadProgress))
        rows.append(contentsOf: sourceRows(from: input))
        rows.append(.separator)
        rows.append(contentsOf: toggleRows(from: input))
        return rows
    }

    private static func downloadRows(progress: Double?) -> [MenuRow] {
        guard let progress else { return [] }
        return [
            .disabled(MenuBarLabelFormatter.downloadStatus(progress: progress)),
            .command(MenuCommand(title: "Cancel Download", id: .cancelDownload)),
            .separator,
        ]
    }

    private static func sourceRows(from input: MenuModelInput) -> [MenuRow] {
        switch input.mode {
        case .allDesktops:
            return allDesktopsRows(from: input)
        case .perDesktop:
            return perDesktopRows(from: input)
        }
    }

    private static func allDesktopsRows(from input: MenuModelInput) -> [MenuRow] {
        var rows: [MenuRow] = []
        if let fileName = input.sharedFileName {
            rows.append(.disabled(MenuBarLabelFormatter.sharedWallpaperTitle(fileName: fileName)))
        }
        rows.append(contentsOf: sourceCommands(displayID: nil, includeRemove: false))
        if input.sharedFileName != nil {
            rows.append(.command(MenuCommand(title: "Remove Moving Wallpaper", id: .clearAll, symbolName: "trash")))
        }
        return rows
    }

    private static func perDesktopRows(from input: MenuModelInput) -> [MenuRow] {
        let displays = input.displays
        if displays.isEmpty {
            return [.disabled("No Displays")]
        }

        var rows: [MenuRow] = []
        for (displayIndex, display) in displays.enumerated() {
            if displays.count > 1 {
                rows.append(.sectionHeader(MenuBarLabelFormatter.displayHeaderTitle(display.name)))
            }
            for (index, space) in display.spaces.enumerated() {
                rows.append(spaceRow(space, index: index + 1, displayID: display.id))
            }
            if displayIndex < displays.count - 1 {
                rows.append(.separator)
            }
        }
        if input.hasAnyWallpaper {
            rows.append(.command(MenuCommand(title: "Remove All Moving Wallpapers", id: .clearAll, symbolName: "trash")))
        }
        return rows
    }

    private static func spaceRow(
        _ space: SpaceMenuInput,
        index: Int,
        displayID: CGDirectDisplayID
    ) -> MenuRow {
        let label = MenuBarLabelFormatter.desktopWallpaperTitle(
            index: index,
            fileName: space.fileName ?? "No Moving Wallpaper"
        )
        let rows: [MenuRow] = space.isCurrent
            ? sourceCommands(displayID: displayID, includeRemove: space.fileName != nil)
            : [.disabled("Switch to This Desktop to Change")]
        return .submenu(title: label, checked: space.isCurrent, rows: rows)
    }

    private static func sourceCommands(
        displayID: CGDirectDisplayID?,
        includeRemove: Bool
    ) -> [MenuRow] {
        var rows: [MenuRow] = [
            .command(MenuCommand(
                title: "Choose File…", id: .chooseFile, displayID: displayID, symbolName: "folder"
            )),
            .command(MenuCommand(
                title: "Paste YouTube URL…", id: .pasteYouTube, displayID: displayID, symbolName: "link"
            )),
            .command(MenuCommand(
                title: "Choose from Photos…", id: .choosePhotos, displayID: displayID, symbolName: "photo.on.rectangle"
            )),
            .command(MenuCommand(
                title: "Shuffle from Photos", id: .shufflePhotos, displayID: displayID, symbolName: "shuffle"
            )),
        ]
        if includeRemove {
            rows.append(.command(MenuCommand(
                title: "Remove", id: .clearDisplay, displayID: displayID, symbolName: "trash"
            )))
        }
        return rows
    }

    /// Playback and app toggles. Mode is one checkmark item rather than a
    /// two-item submenu: All Desktops is simply Per Desktop turned off.
    private static func toggleRows(from input: MenuModelInput) -> [MenuRow] {
        var rows: [MenuRow] = []
        if input.hasAnyWallpaper {
            rows.append(.command(MenuCommand(
                title: input.isPaused ? "Resume" : "Pause",
                id: .togglePause
            )))
        }
        rows.append(.command(MenuCommand(
            title: input.isMuted ? "Turn Sound On" : "Turn Sound Off",
            id: .toggleMute
        )))
        rows.append(.command(MenuCommand(
            title: "Wallpaper per Desktop",
            id: .togglePerDesktop,
            checked: input.mode == .perDesktop
        )))
        return rows
    }

}
