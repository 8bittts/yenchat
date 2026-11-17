#if os(macOS)
import AppKit

extension NSApplication {
    /// macOS 14 deprecated `activate(ignoringOtherApps:)`; keep legacy behavior on older systems.
    func yenActivateCompat() {
        if #available(macOS 14, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}
#endif // os(macOS)
