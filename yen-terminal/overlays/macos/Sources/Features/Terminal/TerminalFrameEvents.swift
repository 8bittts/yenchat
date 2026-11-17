import AppKit
import Combine

/// Keep terminal view identity stable while disabling all frame observers when unused.
@MainActor
enum TerminalFrameEvents {
    static func publisher(enabled: Bool, surface: NSView?, window: NSWindow?,
                          center: NotificationCenter = .default) -> AnyPublisher<Void, Never> {
        guard enabled else { return Empty().eraseToAnyPublisher() }
        var sources: [AnyPublisher<Void, Never>] = []
        if let surface {
            sources.append(center.publisher(for: NSView.frameDidChangeNotification, object: surface)
                .map { _ in () }.eraseToAnyPublisher())
        }
        if let window {
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
                sources.append(center.publisher(for: name, object: window)
                    .map { _ in () }.eraseToAnyPublisher())
            }
        }
        return Publishers.MergeMany(sources).eraseToAnyPublisher()
    }
}
