import Foundation

enum MenuBarLabelFormatter {
    /// Status text for a download in flight, shown by the loading overlay.
    static func downloadStatus(progress: Double) -> String {
        "Downloading \(Int(progress * 100))%"
    }
}
