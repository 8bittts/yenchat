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

/// The trailing split count on a horizontal tab. A tab with one pane shows nothing.
struct PaneTabSplitCount: View {
    let count: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: 3) {
                Image(systemName: "rectangle.split.2x1")
                    .imageScale(.small)
                Text(count, format: .number)
                    .monospacedDigit()
            }
            .font(.system(size: NSFont.smallSystemFontSize))
            .foregroundStyle(.secondary)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(count) panes")
            .help("\(count) panes")
        }
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
        host.observation = controller.$surfaceTree.map { $0.root?.leaves().count ?? 0 }
            .removeDuplicates()
            .sink { [weak host] in host?.rootView = PaneTabSplitCount(count: $0) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
