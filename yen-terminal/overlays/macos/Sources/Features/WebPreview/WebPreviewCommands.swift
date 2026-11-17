#if os(macOS)
import AppKit
import Foundation

enum WebPreviewPresentation: String, Equatable, Sendable {
    case window
    case split
    case automatic
}

enum BrowserSurfaceTarget: String, Equatable, Sendable {
    case window
    case split
    case focused
    case automatic
}

enum BrowserCommandSurface: Equatable, Sendable {
    case window
    case split
}

enum WebPreviewCommandAction: String, Equatable, Sendable {
    case open
    case back
    case forward
    case reload
    case close
    case status
}

struct WebPreviewCommandPayload: Equatable, Sendable {
    static let schemaVersion = "1"
    static let targetedSchemaVersion = "2"

    let action: WebPreviewCommandAction
    let urlString: String?
    let presentation: WebPreviewPresentation
    let responsePath: String?
    let targetExecutablePath: String?
    let target: BrowserSurfaceTarget

    init(
        action: WebPreviewCommandAction,
        urlString: String?,
        presentation: WebPreviewPresentation,
        responsePath: String?,
        targetExecutablePath: String?,
        target: BrowserSurfaceTarget = .automatic
    ) {
        self.action = action
        self.urlString = urlString
        self.presentation = presentation
        self.responsePath = responsePath
        self.targetExecutablePath = targetExecutablePath
        self.target = target
    }

    static func from(userInfo: [AnyHashable: Any]?) -> WebPreviewCommandPayload? {
        guard let schemaVersion = userInfo?["schema_version"] as? String,
              schemaVersion == Self.schemaVersion || schemaVersion == Self.targetedSchemaVersion else {
            return nil
        }
        guard let rawAction = userInfo?["action"] as? String,
              let action = WebPreviewCommandAction(rawValue: rawAction) else {
            return nil
        }

        let presentation: WebPreviewPresentation
        if let rawPresentation = userInfo?["presentation"] as? String {
            guard let parsedPresentation = WebPreviewPresentation(rawValue: rawPresentation) else {
                return nil
            }
            presentation = parsedPresentation
        } else {
            presentation = .window
        }

        let target: BrowserSurfaceTarget
        if let rawTarget = userInfo?["target"] as? String {
            guard let parsedTarget = BrowserSurfaceTarget(rawValue: rawTarget) else {
                return nil
            }
            target = parsedTarget
        } else {
            target = .automatic
        }

        let targetExecutablePath = userInfo?["target_executable_path"] as? String
        if schemaVersion == Self.targetedSchemaVersion {
            guard let targetExecutablePath = targetExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !targetExecutablePath.isEmpty else {
                return nil
            }
        }

        return WebPreviewCommandPayload(
            action: action,
            urlString: userInfo?["url"] as? String,
            presentation: presentation,
            responsePath: userInfo?["response_path"] as? String,
            targetExecutablePath: targetExecutablePath,
            target: target
        )
    }
}

struct WebPreviewCommandResult: Equatable, Sendable {
    let accepted: Bool
    let message: String
    let acknowledgedExecutablePath: String?

    init(accepted: Bool, message: String, acknowledgedExecutablePath: String? = nil) {
        self.accepted = accepted
        self.message = message
        self.acknowledgedExecutablePath = acknowledgedExecutablePath
    }
}

@MainActor
final class WebPreviewCommandReceiver: NSObject {
    static let shared = WebPreviewCommandReceiver()

    private var installed = false

    private override init() {
        super.init()
    }

    func setup() {
        guard !installed else { return }
        installed = true
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleWebCommand(_:)),
            name: .yenWebCommand,
            object: nil
        )
    }

    @objc private func handleWebCommand(_ notification: Notification) {
        guard let payload = WebPreviewCommandPayload.from(userInfo: notification.userInfo) else { return }
        guard Self.targetExecutablePathMatches(
            payload.targetExecutablePath,
            executablePath: Bundle.main.executableURL?.path
        ) else {
            return
        }
        let result = perform(payload)
        writeResponse(result, to: payload.responsePath)
    }

    @discardableResult
    func perform(_ payload: WebPreviewCommandPayload) -> WebPreviewCommandResult {
        BrowserCommandService.shared.perform(
            action: payload.action,
            urlString: payload.urlString,
            presentation: payload.presentation,
            target: payload.target,
            acknowledgedExecutablePath: acknowledgedExecutablePath(for: payload)
        )
    }

    private func acknowledgedExecutablePath(for payload: WebPreviewCommandPayload) -> String? {
        guard let targetExecutablePath = payload.targetExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !targetExecutablePath.isEmpty else {
            return nil
        }
        return Bundle.main.executableURL?.path
    }

    private func writeResponse(_ result: WebPreviewCommandResult, to responsePath: String?) {
        guard let responsePath, isAllowedResponsePath(responsePath) else { return }

        var payload: [String: Any] = [
            "accepted": result.accepted,
            "message": result.message,
        ]
        if let acknowledgedExecutablePath = result.acknowledgedExecutablePath {
            payload["acknowledged_executable_path"] = acknowledgedExecutablePath
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return
        }
        try? data.write(to: URL(fileURLWithPath: responsePath), options: .atomic)
    }

    nonisolated static func isAllowedResponsePath(_ path: String) -> Bool {
        let standardizedURL = URL(fileURLWithPath: path).standardizedFileURL
        let parentPath = standardizedURL.deletingLastPathComponent().path
        return (parentPath == "/tmp" || parentPath == "/private/tmp")
            && standardizedURL.lastPathComponent.hasPrefix("yen-web-command.")
    }

    nonisolated static func targetExecutablePathMatches(_ targetPath: String?, executablePath: String?) -> Bool {
        guard let targetPath = targetPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !targetPath.isEmpty else {
            return true
        }
        guard let executablePath else { return false }
        return URL(fileURLWithPath: targetPath).standardizedFileURL.path
            == URL(fileURLWithPath: executablePath).standardizedFileURL.path
    }

    private func isAllowedResponsePath(_ path: String) -> Bool {
        Self.isAllowedResponsePath(path)
    }
}

#if DEBUG
extension WebPreviewCommandReceiver {
    func _testSetKeyWindowProvider(_ provider: (() -> NSWindow?)?) {
        BrowserCommandService.shared._testSetKeyWindowProvider(provider)
    }
}
#endif
#endif
