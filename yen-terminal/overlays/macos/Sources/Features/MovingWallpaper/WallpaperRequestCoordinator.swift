import CoreGraphics
import Foundation

enum WallpaperAssignmentTarget: Hashable {
    /// Every display at once.
    case allDesktops
    /// One desktop: a display in All Desktops mode (the sentinel Space), or one
    /// Space of a display in Per Desktop mode. A request on one Space must not
    /// cancel a request still running for another Space of the same display.
    case desktop(DesktopKey)
}

@MainActor
final class WallpaperRequestCoordinator {
    private var activeTokens: [WallpaperAssignmentTarget: UUID] = [:]
    private var activeTasks: [WallpaperAssignmentTarget: Task<Void, Never>] = [:]

    @discardableResult
    func start(
        for target: WallpaperAssignmentTarget,
        operation: @escaping @MainActor (_ token: UUID) async -> Void
    ) -> Task<Void, Never> {
        cancel(target)

        let token = UUID()
        activeTokens[target] = token
        let task = Task { @MainActor [weak self] in
            guard let self, isCurrent(token, for: target) else { return }
            defer { finish(target, token: token) }
            await operation(token)
        }
        activeTasks[target] = task
        return task
    }

    func cancel(_ target: WallpaperAssignmentTarget) {
        activeTasks.removeValue(forKey: target)?.cancel()
        activeTokens.removeValue(forKey: target)
    }

    func cancelAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        activeTokens.removeAll()
    }

    func isCurrent(_ token: UUID, for target: WallpaperAssignmentTarget) -> Bool {
        activeTokens[target] == token && !Task.isCancelled
    }

    private func finish(_ target: WallpaperAssignmentTarget, token: UUID) {
        guard activeTokens[target] == token else { return }
        activeTasks.removeValue(forKey: target)
        activeTokens.removeValue(forKey: target)
    }
}
