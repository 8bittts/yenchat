#if os(macOS)
import AppKit

/// Extension to launch the file browser in the active terminal.
/// Connected via MainMenu.xib overlay with Cmd + Shift + O shortcut.
///
/// Uses the shared terminal-command launcher so menu dispatch and command-palette
/// dispatch establish the same explicit command boundary before sending input.
///
/// Uses the `y` shell function defined in YEN shell integration, which provides:
/// - cd-on-quit: shell changes to the last visited directory when file browser exits
/// - stable launcher path: delegates to bundled `browse` wrapper with YEN defaults
///
/// Shell integration is auto-injected for shells launched by YEN. External
/// shells can enable it via `yen init`. Users without integration can type
/// `browse` manually (absolute path works without init).
extension AppDelegate {
    /// Launches file browser in the active terminal (Cmd + Shift + O)
    @IBAction func showFileBrowser(_ sender: Any?) {
        _ = TerminalSurfaceCommandLauncher.launchFileBrowser(in: NSApp.keyWindow)
    }
}
#endif
