import Foundation
import Sparkle
import Testing
@testable import YEN

struct UpdateStateTests {
    @Test func idleEquality() {
        let state1: UpdateState = .idle
        let state2: UpdateState = .idle
        #expect(state1 == state2)
    }

    @Test func checkingEquality() {
        let state1: UpdateState = .checking(.init(cancel: {}))
        let state2: UpdateState = .checking(.init(cancel: {}))
        #expect(state1 == state2)
    }

    @Test func notFoundEquality() {
        let state1: UpdateState = .notFound(.init(acknowledgement: {}))
        let state2: UpdateState = .notFound(.init(acknowledgement: {}))
        #expect(state1 == state2)
    }

    @Test func installingEquality() {
        let state1: UpdateState = .installing(.init(retryTerminatingApplication: {}))
        let state2: UpdateState = .installing(.init(retryTerminatingApplication: {}))
        #expect(state1 == state2)
    }

    @Test func permissionRequestEquality() {
        let request1 = SPUUpdatePermissionRequest(systemProfile: [])
        let request2 = SPUUpdatePermissionRequest(systemProfile: [])
        let state1: UpdateState = .permissionRequest(.init(request: request1, reply: { _ in }))
        let state2: UpdateState = .permissionRequest(.init(request: request2, reply: { _ in }))
        #expect(state1 == state2)
    }

    @Test func downloadingEqualityWithSameProgress() {
        let state1: UpdateState = .downloading(.init(cancel: {}, expectedLength: 1000, progress: 500))
        let state2: UpdateState = .downloading(.init(cancel: {}, expectedLength: 1000, progress: 500))
        #expect(state1 == state2)
    }

    @Test func downloadingInequalityWithDifferentProgress() {
        let state1: UpdateState = .downloading(.init(cancel: {}, expectedLength: 1000, progress: 500))
        let state2: UpdateState = .downloading(.init(cancel: {}, expectedLength: 1000, progress: 600))
        #expect(state1 != state2)
    }

    @Test func downloadingInequalityWithDifferentExpectedLength() {
        let state1: UpdateState = .downloading(.init(cancel: {}, expectedLength: 1000, progress: 500))
        let state2: UpdateState = .downloading(.init(cancel: {}, expectedLength: 2000, progress: 500))
        #expect(state1 != state2)
    }

    @Test func downloadingEqualityWithNilExpectedLength() {
        let state1: UpdateState = .downloading(.init(cancel: {}, expectedLength: nil, progress: 500))
        let state2: UpdateState = .downloading(.init(cancel: {}, expectedLength: nil, progress: 500))
        #expect(state1 == state2)
    }

    @Test func extractingEqualityWithSameProgress() {
        let state1: UpdateState = .extracting(.init(progress: 0.5))
        let state2: UpdateState = .extracting(.init(progress: 0.5))
        #expect(state1 == state2)
    }

    @Test func extractingInequalityWithDifferentProgress() {
        let state1: UpdateState = .extracting(.init(progress: 0.5))
        let state2: UpdateState = .extracting(.init(progress: 0.6))
        #expect(state1 != state2)
    }

    @Test func errorEqualityWithSameDescription() {
        let error1 = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Error message"])
        let error2 = NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Error message"])
        let state1: UpdateState = .error(.init(error: error1, retry: {}, dismiss: {}))
        let state2: UpdateState = .error(.init(error: error2, retry: {}, dismiss: {}))
        #expect(state1 == state2)
    }

    @Test func errorInequalityWithDifferentDescription() {
        let error1 = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Error 1"])
        let error2 = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Error 2"])
        let state1: UpdateState = .error(.init(error: error1, retry: {}, dismiss: {}))
        let state2: UpdateState = .error(.init(error: error2, retry: {}, dismiss: {}))
        #expect(state1 != state2)
    }

    @Test func differentStatesAreNotEqual() {
        let state1: UpdateState = .idle
        let state2: UpdateState = .checking(.init(cancel: {}))
        #expect(state1 != state2)
    }

    @Test(
        arguments: [
            (UpdateState.idle, true),
            (.installing(.init(appcastItem: .empty(), retryTerminatingApplication: {})), true),
            (.checking(.init(cancel: {})), false),
            (.installing(.init(retryTerminatingApplication: {})), false)
        ]
    )
    func isHidden(_ state: UpdateState, expected: Bool) {
        #expect(state.isHidden == expected)
    }

    // A silently auto-installed update (carrying an appcastItem) must NOT
    // terminate without warning; only a manually-triggered install may.
    @Test(
        arguments: [
            (UpdateState.idle, false),
            (.installing(.init(appcastItem: .empty(), retryTerminatingApplication: {})), false),
            (.installing(.init(retryTerminatingApplication: {})), true)
        ]
    )
    func shouldTerminateWithoutWarning(_ state: UpdateState, expected: Bool) {
        #expect(state.shouldTerminateWithoutWarning == expected)
    }

    @Test func isCancellableReflectsCancelAction() {
        #expect(!UpdateState.idle.isCancellable)
        #expect(UpdateState.checking(.init(cancel: {})).isCancellable)
        #expect(!UpdateState.extracting(.init(progress: 0.5)).isCancellable)
    }
}
