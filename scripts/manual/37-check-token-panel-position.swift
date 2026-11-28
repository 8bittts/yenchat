// Run with the pid of a YENVerify copy showing the token panel with local fixture usage.
import AppKit
import ApplicationServices

func fail(_ reason: String) -> Never {
    FileHandle.standardError.write(Data((reason + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]),
      NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.yenchat.yenverify" else {
    fail("Pass the pid of the running YENVerify copy.")
}
let app = AXUIElementCreateApplication(pid)

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}

func displayButton(in element: AXUIElement) -> AXUIElement? {
    if attribute(element, kAXDescriptionAttribute) as? String == "Menu bar display" { return element }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let button = displayButton(in: child) { return button }
    }
    return nil
}

func reading() -> (mode: String, position: CGPoint, button: AXUIElement) {
    let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    guard let panel = windows.first(where: { attribute($0, kAXTitleAttribute) as? String == "YEN Token Usage" }),
          let button = displayButton(in: panel), let mode = attribute(button, kAXValueAttribute) as? String,
          let raw = attribute(button, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else {
        fail("Open the token panel in YENVerify.")
    }
    var position = CGPoint.zero
    guard AXValueGetValue(raw as! AXValue, .cgPoint, &position) else { fail("Missing button position.") }
    return (mode, position, button)
}

let start = reading()
var modes: Set<String> = [start.mode]
var current = start
for _ in 0..<4 {
    let previous = current.mode
    guard AXUIElementPerformAction(current.button, kAXPressAction as CFString) == .success else { fail("Press failed.") }
    for _ in 0..<20 {
        Thread.sleep(forTimeInterval: 0.05)
        current = reading()
        guard current.position == start.position else {
            fail("\(current.mode) moved the display button from \(start.position) to \(current.position).")
        }
    }
    guard current.mode != previous else { fail("The display did not cycle.") }
    modes.insert(current.mode)
}
guard modes.count == 4, current.mode == start.mode else { fail("Incomplete display cycle.") }
print("Verified all four menu bar displays at \(start.position).")
