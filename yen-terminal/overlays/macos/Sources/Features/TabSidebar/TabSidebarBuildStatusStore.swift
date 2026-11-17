#if os(macOS)
import Cocoa
import Combine
import SwiftUI

@MainActor
final class TabSidebarBuildStatusStore: NSObject {
    typealias ObserverRegistrar = (_ name: Notification.Name, _ handler: @escaping (Notification) -> Void) -> NSObjectProtocol
    typealias ObserverRemover = (_ observer: NSObjectProtocol) -> Void

    static let shared = TabSidebarBuildStatusStore()
    private static let signalExpiry: TimeInterval = 120

    private struct Entry {
        let signal: TabSidebarStatusSignal
        let observedAt: Date
    }

    private let registerObserver: ObserverRegistrar
    private let removeObserver: ObserverRemover
    private let now: @MainActor () -> Date
    private var entries: [UUID: Entry] = [:]
    private var hasSetup = false
    private var observer: NSObjectProtocol?

    init(
        registerObserver: ObserverRegistrar? = nil,
        removeObserver: ObserverRemover? = nil,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.now = now
        if let registerObserver {
            self.registerObserver = registerObserver
        } else {
            self.registerObserver = { name, handler in
                DistributedNotificationCenter.default().addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { notification in
                    handler(notification)
                }
            }
        }
        if let removeObserver {
            self.removeObserver = removeObserver
        } else {
            self.removeObserver = { observer in
                DistributedNotificationCenter.default().removeObserver(observer)
            }
        }
    }

    func setup() {
        ensureSetup()
    }

    private func ensureSetup() {
        guard !hasSetup else { return }
        hasSetup = true
        observer = registerObserver(.yenBuildNotification) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleBuildNotification(notification)
            }
        }
    }

    func signal(for surfaceID: UUID?) -> TabSidebarStatusSignal? {
        ensureSetup()
        guard let surfaceID else { return nil }
        pruneExpired()
        return entries[surfaceID]?.signal
    }

    deinit {
        if let observer {
            removeObserver(observer)
        }
    }

    private func handleBuildNotification(_ notification: Notification) {
        guard let envelope = ServiceNotificationEnvelope.decode(
            from: notification,
            fallbackTitle: "YEN Terminal"
        ) else {
            return
        }
        guard let rawSurfaceID = ServiceNotificationRouteMetadata(userInfo: notification.userInfo).surfaceID,
              let surfaceID = UUID(uuidString: rawSurfaceID),
              let signal = Self.signal(from: envelope.title) else {
            return
        }

        entries[surfaceID] = Entry(signal: signal, observedAt: now())
        pruneExpired()
        NotificationCenter.default.post(
            name: .yenTabSidebarBuildStatusDidChange,
            object: surfaceID
        )
    }

    private func pruneExpired() {
        let cutoff = now().addingTimeInterval(-Self.signalExpiry)
        entries = entries.filter { $0.value.observedAt >= cutoff }
    }

    static func signal(from title: String) -> TabSidebarStatusSignal? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("YEN ") ? String(trimmed.dropFirst(4)) : trimmed

        if let failedRange = normalized.range(of: " failed", options: [.caseInsensitive]) {
            let task = String(normalized[..<failedRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            return TabSidebarStatusSignal(summary: "\(task) failed", tone: .error)
        }

        if let completedRange = normalized.range(of: " completed", options: [.caseInsensitive]) {
            let task = String(normalized[..<completedRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            return TabSidebarStatusSignal(summary: "\(task) complete", tone: .success)
        }

        return nil
    }
}

#endif
