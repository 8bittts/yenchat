import Foundation
import Sparkle
import SwiftUI
import Testing
@testable import YEN

struct UpdateViewModelTests {
    @Test func idleText() {
        let viewModel = UpdateViewModel()
        viewModel.state = .idle
        #expect(viewModel.text == "")
    }

    @Test func permissionRequestText() {
        let viewModel = UpdateViewModel()
        let request = SPUUpdatePermissionRequest(systemProfile: [])
        viewModel.state = .permissionRequest(.init(request: request, reply: { _ in }))
        #expect(viewModel.text == "Enable Automatic Updates?")
    }

    @Test func checkingText() {
        let viewModel = UpdateViewModel()
        viewModel.state = .checking(.init(cancel: {}))
        #expect(viewModel.text == "Checking for Updates…")
    }

    @Test func downloadingTextWithKnownLength() {
        let viewModel = UpdateViewModel()
        viewModel.state = .downloading(.init(cancel: {}, expectedLength: 1000, progress: 500))
        #expect(viewModel.text == "Downloading: 50%")
    }

    @Test func downloadingTextWithUnknownLength() {
        let viewModel = UpdateViewModel()
        viewModel.state = .downloading(.init(cancel: {}, expectedLength: nil, progress: 500))
        #expect(viewModel.text == "Downloading…")
    }

    @Test func downloadingTextWithZeroExpectedLength() {
        let viewModel = UpdateViewModel()
        viewModel.state = .downloading(.init(cancel: {}, expectedLength: 0, progress: 500))
        #expect(viewModel.text == "Downloading…")
    }

    @Test func extractingText() {
        let viewModel = UpdateViewModel()
        viewModel.state = .extracting(.init(progress: 0.75))
        #expect(viewModel.text == "Preparing: 75%")
    }

    @Test func installingText() {
        let viewModel = UpdateViewModel()
        viewModel.state = .installing(.init(retryTerminatingApplication: {}))
        #expect(viewModel.text == "Installing…")

        viewModel.state = .installing(.init(appcastItem: .empty(), retryTerminatingApplication: {}))
        #expect(viewModel.text == "Restart to Complete Update")
    }

    @Test func notFoundText() {
        let viewModel = UpdateViewModel()
        viewModel.state = .notFound(.init(acknowledgement: {}))
        #expect(viewModel.text == "No Updates Available")
    }

    @Test func errorText() {
        let viewModel = UpdateViewModel()
        let error = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        viewModel.state = .error(.init(error: error, retry: {}, dismiss: {}))
        #expect(viewModel.text == "Network error")
    }

    @Test func maxWidthTextForDownloading() {
        let viewModel = UpdateViewModel()
        viewModel.state = .downloading(.init(cancel: {}, expectedLength: 1000, progress: 50))
        #expect(viewModel.maxWidthText == "Downloading: 100%")
    }

    @Test func maxWidthTextForExtracting() {
        let viewModel = UpdateViewModel()
        viewModel.state = .extracting(.init(progress: 0.5))
        #expect(viewModel.maxWidthText == "Preparing: 100%")
    }

    @Test func maxWidthTextForNonProgressState() {
        let viewModel = UpdateViewModel()
        viewModel.state = .checking(.init(cancel: {}))
        #expect(viewModel.maxWidthText == viewModel.text)
    }
}
