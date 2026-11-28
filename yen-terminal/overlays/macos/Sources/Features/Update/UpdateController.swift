import Sparkle
import Cocoa
import Combine
import SwiftUI

/// Standard controller for managing Sparkle updates in YEN.
///
/// This controller wraps SPUStandardUpdaterController to provide a simpler interface
/// for managing updates with YEN's custom driver and delegate. It handles
/// initialization, starting the updater, and provides the check for updates action.
class UpdateController {
    private(set) var updater: SPUUpdater
    private let userDriver: UpdateDriver
    private var sessionObservation: AnyCancellable?
    private var stateObservation: AnyCancellable?
    private var updateWindow: NSWindow?

    var viewModel: UpdateViewModel {
        userDriver.viewModel
    }

    /// True if we're installing an update triggered manually.
    var shouldTerminateWithoutWarning: Bool {
        viewModel.state.shouldTerminateWithoutWarning
    }

    /// Initialize a new update controller.
    init() {
        let hostBundle = Bundle.main
        self.userDriver = UpdateDriver(
            viewModel: .init(),
            hostBundle: hostBundle)
        self.updater = SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: hostBundle,
            userDriver: userDriver,
            delegate: userDriver
        )
        stateObservation = viewModel.$state.dropFirst().sink { [weak self] state in
            guard let self else { return }
            if state == .idle {
                if self.sessionObservation == nil { self.updateWindow?.orderOut(nil) }
            } else {
                self.sessionObservation = nil
            }
        }
    }

    /// Start the updater.
    ///
    /// This must be called before the updater can check for updates. If starting fails,
    /// the error will be shown to the user.
    func startUpdater() {
        do {
            try updater.start()
        } catch {
            userDriver.viewModel.state = .error(.init(
                error: error,
                retry: { [weak self] in
                    self?.userDriver.viewModel.state = .idle
                    self?.startUpdater()
                },
                dismiss: { [weak self] in
                    self?.userDriver.viewModel.state = .idle
                }
            ))
        }
    }

    /// Check for updates.
    ///
    /// This is typically connected to a menu item action.
    func checkForUpdates() {
        if case let .installing(installing) = viewModel.state {
            // If the update is already installed, we can't actually
            // cancel it, and SPUUpdater.checkForUpdates will simply fail,
            // so we just show an alert to remind the user to restart.
            let alert = NSAlert()
            alert.alertStyle = .informational
            let accessoryView = NSHostingView(
                rootView: InstallingAccessoryView(installing: installing)
                    .frame(width: 228, alignment: .leading)
            )
            accessoryView.frame = .init(origin: .zero, size: accessoryView.fittingSize)
            alert.accessoryView = accessoryView
            alert.addButton(withTitle: "Restart Now")
            alert.addButton(withTitle: "Restart Later")
                .keyEquivalent = .init([KeyboardShortcut(.escape).key.character])
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                viewModel.state.confirm()
            default:
                break
            }
            return
        }

        if userDriver.hasUnobtrusiveTarget {
            presentUpdateWindow()
        } else if viewModel.state != .idle {
            userDriver.standard.showUpdateInFocus()
            return
        }
        guard viewModel.state == .idle else { return }
        if updater.sessionInProgress {
            // Sparkle may still be acknowledging an error or finishing a background check.
            guard sessionObservation == nil else { return }
            sessionObservation = updater.publisher(for: \.sessionInProgress)
                .filter { !$0 }.first().receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.sessionObservation = nil
                    if self.viewModel.state == .idle { self.checkForUpdates() }
                }
        } else {
            updater.checkForUpdates()
        }
    }

    private func presentUpdateWindow() {
        if updateWindow == nil {
            let controller = NSHostingController(rootView: ManualUpdateView(model: viewModel))
            let window = NSWindow(contentViewController: controller)
            window.title = "Software Update"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            updateWindow = window
        }
        NSApp.activate()
        updateWindow?.makeKeyAndOrderFront(nil)
    }
}

private struct ManualUpdateView: View {
    @ObservedObject var model: UpdateViewModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .installing:
                Text(model.state == .idle ? "Checking for updates…" : model.text)
                    .padding().frame(width: 300)
            default:
                UpdatePopoverView(model: model)
            }
        }.fixedSize()
    }
}

private struct InstallingAccessoryView: View {
    let installing: UpdateState.Installing

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Restart Required")
                    .font(YENTypography.headline)

                Text("The update is ready. Please restart the application to complete the installation.")
                    .font(YENTypography.secondary)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let item = installing.appcastItem, let releaseNotesURL = installing.releaseNotes?.url {
                    VStack(alignment: .leading, spacing: 4) {
                        Link(destination: releaseNotesURL) {
                            HStack(spacing: 6) {
                                Text("Version:")
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                                Text(item.displayVersionString)
                            }
                            .font(YENTypography.secondary)
                        }

                        if let date = item.date {
                            HStack(spacing: 6) {
                                Text("Released:")
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                            }
                            .font(YENTypography.secondary)
                        }
                    }
                    .textSelection(.enabled)
                }
            }
        }
    }
}
