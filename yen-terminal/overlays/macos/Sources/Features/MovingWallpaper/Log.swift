import Foundation
import os

@available(macOS 27.0, *)
enum WallpaperLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.yenchat.yen"

    static let youtube = Logger(subsystem: subsystem, category: "youtube")
    static let photos = Logger(subsystem: subsystem, category: "photos")
    static let power = Logger(subsystem: subsystem, category: "power")
    static let playback = Logger(subsystem: subsystem, category: "playback")
    static let updater = Logger(subsystem: subsystem, category: "updater")
}
