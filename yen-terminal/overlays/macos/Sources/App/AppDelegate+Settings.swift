#if os(macOS)
import AppKit

/// Extension to add native Settings panel support to AppDelegate.
/// Connected via MainMenu.xib overlay with Cmd+, shortcut.
extension AppDelegate {
    /// Toggles the native settings panel (Cmd+,)
    @IBAction func showSettings(_ sender: Any?) {
        SettingsController.shared.toggleVisibility()
    }
}
#endif // os(macOS)
