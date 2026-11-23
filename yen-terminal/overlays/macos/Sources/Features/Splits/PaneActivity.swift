import AppKit
import Combine
import SwiftUI

/// The foreground executable identifies tools that leave the terminal title alone.
/// Interpreters and session wrappers can instead expose the tool through its title.
enum PaneActivity: Hashable {
    case terminal, codex, claude, editor, git, files, ssh, monitor

    private static func known(_ name: String) -> Self? {
        switch name.lowercased() {
        case "codex", "codex-aarch64-apple-darwin", "codex-x86_64-apple-darwin": .codex
        case "claude": .claude
        case "vi", "vim", "nvim", "nano", "micro", "emacs", "hx": .editor
        case "git", "lazygit", "tig": .git
        case "yazi": .files
        case "ssh", "mosh-client": .ssh
        case "top", "htop", "btop": .monitor
        default: nil
        }
    }

    static func resolve(process: String, title: String) -> Self {
        if let activity = known(process) { return activity }
        // Shell titles often start with a directory. Match complete command words,
        // never a tool name embedded in a path, branch, or another command.
        let words = title.split(whereSeparator: \.isWhitespace)
            .drop(while: { $0.allSatisfy { !$0.isLetter && !$0.isNumber } })
        let first = words.first
        if first?.lowercased() == "openai", words.dropFirst().first?.lowercased() == "codex" { return .codex }
        return first.flatMap { known(String($0)) } ?? .terminal
    }

    @MainActor static func current(_ surface: YEN.SurfaceView) -> Self {
        // The local process of a remote pane is the CLI holding ssh open.
        if surface.remotePaneIdentity != nil { return .ssh }
        var name = [CChar](repeating: 0, count: 256)
        if let pid = surface.surfaceModel?.foregroundPID,
           proc_name(Int32(pid), &name, UInt32(name.count)) > 0 {
            let process = name.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            return resolve(process: process, title: surface.title)
        }
        return resolve(process: "", title: surface.title)
    }

    var agentName: String? {
        switch self {
        case .codex, .claude: appearance.name
        default: nil
        }
    }

    var appearance: (name: String, symbol: String, tint: Color) {
        switch self {
        case .terminal: ("Terminal", "terminal", .primary)
        case .codex: ("Codex", "command", .teal)
        case .claude: ("Claude Code", "asterisk", .orange)
        case .editor: ("Editor", "pencil", .blue)
        case .git: ("Git", "point.3.connected.trianglepath.dotted", .purple)
        case .files: ("Files", "folder", .yellow)
        case .ssh: ("SSH", "network", .cyan)
        case .monitor: ("Monitor", "waveform.path.ecg", .green)
        }
    }
}

struct PaneActivityReader<Content: View>: View {
    @ObservedObject var surface: YEN.SurfaceView
    @ViewBuilder let content: (PaneActivity) -> Content
    @State private var activity = PaneActivity.terminal

    var body: some View {
        content(activity)
            .task(id: surface.title) {
                while !Task.isCancelled {
                    activity = PaneActivity.current(surface)
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                }
            }
    }
}

struct PaneActivityIcon: View {
    let activity: PaneActivity

    // Resolve once per launch. Command-line-only installs use the symbol below.
    @MainActor private static let agentImages: [PaneActivity: NSImage] = {
        let bundles: [PaneActivity: String] = [.codex: "com.openai.codex", .claude: "com.anthropic.claudefordesktop"]
        return bundles.compactMapValues { identifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
    }()

    var body: some View {
        let style = activity.appearance
        let badge = RoundedRectangle(cornerRadius: 4)
        Group {
            if let icon = Self.agentImages[activity] {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: style.symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(style.tint)
                    .frame(width: 20, height: 16)
                    .background(Color(nsColor: .windowBackgroundColor), in: badge)
                    .overlay {
                        badge.strokeBorder(style.tint.opacity(0.45))
                    }
            }
        }
        .frame(width: 20, height: 18)
        .accessibilityLabel(style.name)
    }
}

/// The trailing accessory on a horizontal tab: the tab's session state
/// (`TabSessionState`) and the split count. A one-pane tab shows no count.
struct PaneTabSplitCount: View {
    let count: Int
    var session: TabSessionState? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let session {
                Image(systemName: session.symbolName)
                    .imageScale(.small)
                    .accessibilityLabel(session.label)
                    .help(session.label)
            }
            if count > 1 {
                HStack(spacing: 3) {
                    Image(systemName: "rectangle.split.2x1")
                        .imageScale(.small)
                    Text(count, format: .number)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(count) panes")
                .help("\(count) panes")
            }
        }
        .font(.system(size: NSFont.smallSystemFontSize))
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

/// Hosts the split count in the native tab's accessory stack. The name predates the
/// count and stays because the engine patch calls `install`. Let mouse clicks
/// through to AppKit so selecting or dragging a tab still works.
final class PaneTabIconAccessory: NSHostingView<PaneTabSplitCount> {
    private var observation: AnyCancellable?

    static func install(for controller: TerminalController, in window: NSWindow) {
        guard let stack = window.tab.accessoryView as? WorkspaceTabAccessory else { return }
        let host = PaneTabIconAccessory(rootView: PaneTabSplitCount(count: 0))
        stack.install(host, for: window)
        // Session state is fixed for a pane's life, so the tree is the only
        // input: recomputed when panes are added, removed or moved.
        host.observation = controller.$surfaceTree
            .map(Self.accessoryContent(for:))
            .removeDuplicates(by: Self.sameContent)
            .sink { [weak host] in
                host?.rootView = $0
                // A narrow tab drops the count for its title but keeps a
                // session marker, the one cue a truncated title can lose.
                (host?.superview as? WorkspaceTabAccessory)?.updateTrailingContent()
            }
    }

    static func accessoryContent(for tree: SplitTree<YEN.SurfaceView>) -> PaneTabSplitCount {
        let leaves: [YEN.SurfaceView] = tree.root?.leaves() ?? []
        let ids: [UUID] = leaves.map { $0.id }
        return PaneTabSplitCount(count: leaves.count, session: TabSessionState.of(paneIDs: ids))
    }

    static func sameContent(_ lhs: PaneTabSplitCount, _ rhs: PaneTabSplitCount) -> Bool {
        lhs.count == rhs.count && lhs.session == rhs.session
    }

    var showsSessionMarker: Bool { rootView.session != nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
