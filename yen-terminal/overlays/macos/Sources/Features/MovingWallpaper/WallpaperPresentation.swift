import AppKit

@available(macOS 27.0, *)
@MainActor
enum WallpaperPresentation {
    static func withForegroundActivation<T>(_ operation: () throws -> T) rethrows -> T {
        NSApp.activate()
        return try operation()
    }

    static func showAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        withForegroundActivation {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = style
            alert.runModal()
        }
    }
}
