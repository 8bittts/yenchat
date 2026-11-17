// Working directory a coding agent reports for the pane it runs in.
//
// Agents such as Claude Code move into a git worktree with their own tools while the pane's shell
// stays in the main checkout. They never emit OSC 7, so `pwd` keeps naming the checkout and the
// split label, tab sidebar, and git drawer all describe the wrong tree. An agent hook reports its
// directory out of band instead: `yen pane cwd` posts a distributed notification carrying the
// pane's `YEN_SURFACE_ID`, the same channel `yen web` and the build notification hook use.
//
// The shell's `pwd` is never rewritten. New splits and the command palette keep following the
// shell, and only the three surfaces above read `effectiveWorkingDirectory`.
#if os(macOS)
import AppKit
import Combine
import ObjectiveC

/// One accepted report. It stands only while `ownerProcessID` is still the pane's foreground
/// process group, so it ends with the agent even when the shell never prints another prompt.
struct AgentWorkingDirectoryReport: Equatable {
    let directory: String
    let ownerProcessID: Int
}

enum AgentWorkingDirectoryRules {
    /// A live agent report wins; otherwise the pane describes its shell's `pwd`.
    static func effectiveDirectory(
        report: AgentWorkingDirectoryReport?,
        foregroundProcessID: Int?,
        shellDirectory: String?
    ) -> String? {
        guard let report, report.ownerProcessID == foregroundProcessID else { return shellDirectory }
        return report.directory
    }
}

/// A decoded `com.yenchat.yen.agentWorkingDirectory` notification.
struct AgentWorkingDirectoryPayload: Equatable {
    enum Change: Equatable {
        case report(directory: String)
        case clear
    }

    static let supportedSchemaVersion = "1"
    static let schemaVersionKey = "schema_version"
    static let surfaceIDKey = "surface_id"
    static let directoryKey = "directory"

    let surfaceID: UUID
    let change: Change

    /// Accepts schema 1 with a pane UUID. An empty directory clears the report; any other value
    /// must be an existing absolute directory, canonicalized the way the tab sidebar canonicalizes
    /// `pwd` so both describe the same path.
    @MainActor
    static func decode(userInfo: [AnyHashable: Any]?) -> AgentWorkingDirectoryPayload? {
        guard let userInfo,
              userInfo[schemaVersionKey] as? String == supportedSchemaVersion,
              let rawSurfaceID = userInfo[surfaceIDKey] as? String,
              let surfaceID = UUID(uuidString: rawSurfaceID.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }

        let rawDirectory = (userInfo[directoryKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawDirectory.isEmpty {
            return AgentWorkingDirectoryPayload(surfaceID: surfaceID, change: .clear)
        }

        guard rawDirectory.hasPrefix("/"),
              let directory = TabSidebarController.trustedWorkingDirectory(from: rawDirectory),
              isDirectory(directory)
        else {
            return nil
        }
        return AgentWorkingDirectoryPayload(surfaceID: surfaceID, change: .report(directory: directory))
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// Holds one pane's latest agent report. Any OSC 7 from the shell clears it, because the shell
/// only prints a prompt once the agent in front of it has exited.
@MainActor
final class AgentWorkingDirectoryState: ObservableObject {
    @Published private(set) var report: AgentWorkingDirectoryReport?

    private var shellDirectorySubscription: AnyCancellable?

    /// `shellDirectoryReports` fires on main once per OSC 7 and must not replay a current value.
    init(shellDirectoryReports: AnyPublisher<Void, Never>) {
        shellDirectorySubscription = shellDirectoryReports.sink { [weak self] in
            // OSC 7 arrives on main. Clear before a later agent report can replace it.
            MainActor.assumeIsolated { self?.clear() }
        }
    }

    func accept(_ report: AgentWorkingDirectoryReport) {
        guard self.report != report else { return }
        self.report = report
    }

    func clear() {
        guard report != nil else { return }
        report = nil
    }
}

/// Applies `yen pane cwd` reports to the pane named by their surface id.
@MainActor
final class AgentWorkingDirectoryReceiver: NSObject {
    static let shared = AgentWorkingDirectoryReceiver()

    private let findSurface: @MainActor (UUID) -> YEN.SurfaceView?
    private var installed = false

    init(findSurface: @escaping @MainActor (UUID) -> YEN.SurfaceView? = { uuid in
        AppDelegate.shared?.findSurface(forUUID: uuid)
    }) {
        self.findSurface = findSurface
        super.init()
    }

    func setup() {
        guard !installed else { return }
        installed = true
        // Process-lifetime singleton set up once at launch, so the observer is never removed.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleReport(_:)),
            name: .yenAgentWorkingDirectory,
            object: nil
        )
    }

    @objc private func handleReport(_ notification: Notification) {
        guard let payload = AgentWorkingDirectoryPayload.decode(userInfo: notification.userInfo),
              let surface = findSurface(payload.surfaceID)
        else {
            return
        }
        Self.apply(
            payload.change,
            to: surface.agentWorkingDirectoryState,
            foregroundProcessID: surface.surfaceModel?.foregroundPID
        )
    }

    /// Binds a report to the process in front of the pane when it arrives. Without a foreground
    /// process there is nothing to end the report, so it is dropped.
    static func apply(
        _ change: AgentWorkingDirectoryPayload.Change,
        to state: AgentWorkingDirectoryState,
        foregroundProcessID: Int?
    ) {
        switch change {
        case .clear:
            state.clear()
        case .report(let directory):
            guard let foregroundProcessID else { return }
            state.accept(AgentWorkingDirectoryReport(directory: directory, ownerProcessID: foregroundProcessID))
        }
    }
}

private var agentWorkingDirectoryStateAssociationKey: UInt8 = 0

extension YEN.SurfaceView {
    private var existingAgentWorkingDirectoryState: AgentWorkingDirectoryState? {
        objc_getAssociatedObject(self, &agentWorkingDirectoryStateAssociationKey) as? AgentWorkingDirectoryState
    }

    var agentWorkingDirectoryState: AgentWorkingDirectoryState {
        if let state = existingAgentWorkingDirectoryState {
            return state
        }

        let state = AgentWorkingDirectoryState(
            // `$pwd` replays its current value on subscribe; only later OSC 7 reports count.
            shellDirectoryReports: $pwd.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        objc_setAssociatedObject(
            self,
            &agentWorkingDirectoryStateAssociationKey,
            state,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return state
    }

    /// The directory the split label, tab sidebar, and git drawer describe: a live agent report,
    /// else the shell's `pwd`. The foreground process is only read when a report exists.
    var effectiveWorkingDirectory: String? {
        guard let report = existingAgentWorkingDirectoryState?.report else { return pwd }
        return AgentWorkingDirectoryRules.effectiveDirectory(
            report: report,
            foregroundProcessID: surfaceModel?.foregroundPID,
            shellDirectory: pwd
        )
    }
}
#endif
