import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

// Measure key-to-frame latency of a running YEN copy.
//
// Posts a key to one process and reports the time until the next frame of one of its windows
// whose pixels changed reaches the display (ScreenCaptureKit display times).
//
// Build:  swiftc -O -parse-as-library -o key-latency scripts/manual/34-measure-key-latency.swift
// Usage:  key-latency probe
//         key-latency list <pid>
//         key-latency run <pid> <window-id> <count> <out-file> [prelude]
//
// - `probe` reports whether screen capture and event posting are allowed for the calling terminal.
// - `list` prints the process's capturable windows; use the visible layer-0 terminal window.
// - `run` types `a` `count` times and writes one latency in milliseconds per line. `prelude` is
//   typed first and followed by Return; `cat` gives a pane that echoes every key at once.
// - LAT_QUIET, LAT_GAP_MIN and LAT_GAP_MAX (milliseconds) set the quiet time before a key and the
//   pause after it; the defaults are 150, 90 and 210.
//
// The key goes to the process only (postToPid), and the run stops when that process is not
// frontmost, so no key can reach another app. Only the text area of the given window is captured:
// the focused window presents a frame on every refresh and its border can animate, so a frame
// counts only when its pixels differ from the frame before.
//
// Method and results: _docs/09-quality.md -> Native Test Suite.

final class Frames: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var times: [UInt64] = []
    private var previous = Data()
    private(set) var delivered = 0
    private(set) var stopped: Error?

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let all = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = all.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let shown = info[.displayTime] as? UInt64,
              let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        // The focused window presents a frame on every refresh, so a new frame alone says nothing.
        // Keep only the frames whose pixels differ from the frame before.
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixels), height = CVPixelBufferGetHeight(pixels)
        let used = CVPixelBufferGetWidth(pixels) * 4
        var current = Data(capacity: used * height)
        for row in 0..<height { current.append(base.advanced(by: row * rowBytes).assumingMemoryBound(to: UInt8.self), count: used) }
        lock.lock()
        delivered += 1
        if current != previous {
            if !previous.isEmpty { times.append(shown) }
            previous = current
        }
        lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { lock.lock(); stopped = error; lock.unlock() }

    /// The first frame shown at or after `start`, if one has arrived.
    func first(after start: UInt64) -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        return times.first { $0 >= start }
    }

    var latest: UInt64 { lock.lock(); defer { lock.unlock() }; return times.last ?? 0 }
    var count: Int { lock.lock(); defer { lock.unlock() }; return times.count }
}

let timebase: mach_timebase_info_data_t = {
    var value = mach_timebase_info_data_t()
    mach_timebase_info(&value)
    return value
}()
func milliseconds(_ ticks: UInt64) -> Double { Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1e6 }
func sleepMs(_ ms: Double) { usleep(useconds_t(ms * 1000)) }

func key(_ code: CGKeyCode, to pid: pid_t, flags: CGEventFlags = []) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
        event.flags = flags
        event.postToPid(pid)
        usleep(1500)
    }
}

@main
struct Latency {
    static func main() async {
        let args = CommandLine.arguments
        // A command-line tool has no window server connection until something asks for one.
        _ = CGMainDisplayID()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if args.count >= 2, args[1] == "probe" {
                print("screen capture allowed: windows=\(content.windows.count) trusted=\(AXIsProcessTrusted())")
                return
            }
            if args.count >= 3, args[1] == "list", let pid = pid_t(args[2]) {
                for w in content.windows where w.owningApplication?.processID == pid {
                    print("\(w.windowID)|\(w.title ?? "")|layer=\(w.windowLayer)|onscreen=\(w.isOnScreen)|\(Int(w.frame.width))x\(Int(w.frame.height))")
                }
                return
            }
            guard args.count >= 6, args[1] == "run", let pid = pid_t(args[2]), let windowID = UInt32(args[3]), let count = Int(args[4]) else {
                print("usage: key-latency run <pid> <window-id> <count> <out-file> [prelude]"); exit(2)
            }
            guard let window = content.windows.first(where: { $0.windowID == windowID && $0.owningApplication?.processID == pid }) else {
                print("ERROR window \(windowID) of pid \(pid) not found"); exit(1)
            }
            let config = SCStreamConfiguration()
            // The text area only, at one pixel per point: the title bar and the animated border stay out.
            let area = CGRect(x: 14, y: 44, width: window.frame.width - 28, height: window.frame.height - 60)
            config.sourceRect = area
            config.width = Int(area.width)
            config.height = Int(area.height)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval = CMTime(value: 1, timescale: 240)
            config.queueDepth = 8
            config.showsCursor = false
            let frames = Frames()
            let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: frames)
            try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames", qos: .userInteractive))
            try await stream.startCapture()
            sleepMs(800)

            // The frontmost app owns the first normal-level window in front-to-back order. A tool
            // without a run loop cannot trust NSWorkspace's cached answer.
            func frontmost() -> Bool {
                let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                let front = list.first { ($0[kCGWindowLayer as String] as? Int) == 0 }
                return (front?[kCGWindowOwnerPID as String] as? pid_t) == pid
            }
            func quiet(_ ms: Double) {
                // Wait until no frame has been shown for `ms`.
                var waited = 0.0
                while waited < 3000 {
                    let last = frames.latest
                    if last == 0 || milliseconds(mach_absolute_time() &- last) >= ms { return }
                    sleepMs(10); waited += 10
                }
            }
            guard frontmost() else { print("ERROR pid \(pid) is not frontmost"); exit(1) }
            // Optional prelude: type a command and Return, for example "cat".
            if args.count >= 7 {
                let codes: [Character: CGKeyCode] = ["a": 0, "c": 8, "t": 17]
                for ch in args[6] { if let code = codes[ch] { key(code, to: pid); sleepMs(40) } }
                key(36, to: pid); sleepMs(600)
            }
            let env = ProcessInfo.processInfo.environment
            let quietMs = Double(env["LAT_QUIET"] ?? "") ?? 150
            let gapMin = Double(env["LAT_GAP_MIN"] ?? "") ?? 90, gapMax = Double(env["LAT_GAP_MAX"] ?? "") ?? 210
            var samples: [Double] = [], misses = 0, aborted = false
            for i in 0..<count {
                guard frontmost() else { aborted = true; break }
                if frames.stopped != nil { aborted = true; break }
                quiet(quietMs)
                let start = mach_absolute_time()
                key(0, to: pid)
                var shown: UInt64?
                var waited = 0.0
                while waited < 400 {
                    shown = frames.first(after: start)
                    if shown != nil { break }
                    sleepMs(1); waited += 1
                }
                if let shown { samples.append(milliseconds(shown &- start)) } else { misses += 1 }
                // A line longer than the terminal driver's limit stops echoing, so end it now and then.
                if i % 40 == 39 { quiet(150); key(36, to: pid); sleepMs(120) }
                sleepMs(Double.random(in: gapMin...gapMax))
            }
            try? await stream.stopCapture()
            try samples.map { String(format: "%.3f", $0) }.joined(separator: "\n").write(toFile: args[5], atomically: true, encoding: .utf8)
            let sorted = samples.sorted()
            func pct(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
            let mean = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
            print(String(format: "keys=%d changed_frames=%d delivered=%d misses=%d aborted=%@ mean=%.2f p50=%.2f p90=%.2f p99=%.2f min=%.2f max=%.2f",
                         samples.count, frames.count, frames.delivered, misses, aborted ? "yes" : "no", mean, pct(0.5), pct(0.9), pct(0.99), sorted.first ?? 0, sorted.last ?? 0))
        } catch {
            print("ERROR \(error.localizedDescription)")
            exit(1)
        }
    }
}
