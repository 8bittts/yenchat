import AppKit
import ImageIO
import SwiftUI
import YENKit
import os

struct WindowReferenceReader: NSViewRepresentable {
    @Binding var window: NSWindow?
    @Binding var frameInWindow: CGRect

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.onMetricsChange = { newWindow, newFrame in
            DispatchQueue.main.async {
                self.window = newWindow
                self.frameInWindow = newFrame
            }
        }
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.onMetricsChange = { newWindow, newFrame in
            DispatchQueue.main.async {
                if self.window != newWindow {
                    self.window = newWindow
                }
                if self.frameInWindow != newFrame {
                    self.frameInWindow = newFrame
                }
            }
        }
    }
}

final class WindowReaderView: NSView {
    var onMetricsChange: ((NSWindow?, CGRect) -> Void)?
    private var windowObserverTokens: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowNotifications()
        emitMetrics()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        removeWindowObservers()
        onMetricsChange?(newWindow, .zero)
    }

    override func layout() {
        super.layout()
        emitMetrics()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        emitMetrics()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        emitMetrics()
    }

    deinit {
        removeWindowObservers()
    }

    private func observeWindowNotifications() {
        removeWindowObservers()
        guard let window else { return }

        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didMoveNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            .yenNativeFullscreenTransitionDidChange,
        ]

        windowObserverTokens = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.emitMetrics()
            }
        }
    }

    private func removeWindowObservers() {
        for token in windowObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        windowObserverTokens.removeAll(keepingCapacity: false)
    }

    private func emitMetrics() {
        guard let window else {
            onMetricsChange?(nil, .zero)
            return
        }
        onMetricsChange?(window, convert(bounds, to: nil))
    }
}

#if DEBUG
struct WindowReferenceReaderMetric: Equatable {
    let hasWindow: Bool
    let frameInWindow: CGRect
}

@MainActor
enum WindowReferenceReaderTesting {
    static func metricsForLifecycleEvents() -> [WindowReferenceReaderMetric] {
        let contentView = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView

        let readerView = WindowReaderView(frame: CGRect(x: 20, y: 30, width: 120, height: 80))
        var metrics: [WindowReferenceReaderMetric] = []
        readerView.onMetricsChange = { window, frame in
            metrics.append(WindowReferenceReaderMetric(hasWindow: window != nil, frameInWindow: frame))
        }

        contentView.addSubview(readerView)
        readerView.layoutSubtreeIfNeeded()
        readerView.setFrameSize(CGSize(width: 140, height: 90))
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        readerView.removeFromSuperview()

        return metrics
    }
}
#endif
