import AppKit
import Testing
@testable import YEN

@MainActor
struct TerminalSurfaceCommandLauncherTests {
    @Test func fileBrowserLaunchEventsEstablishCommandBoundary() {
        let events = TerminalSurfaceCommandLauncher.launchEvents(
            for: TerminalSurfaceCommandLauncher.fileBrowserCommand
        )

        #expect(events.count == 3)
        #expect(events[0].key == .c)
        #expect(events[0].mods == .ctrl)
        #expect(events[0].text == nil)
        #expect(events[1].key == .y)
        #expect(events[1].text == "y")
        #expect(events[2].key == .enter)
        #expect(events[2].text == "\r")
    }

    @Test func gitTUILaunchEventsUseBundledWrapperCommand() {
        let rendered = TerminalSurfaceCommandLauncher
            .launchEvents(for: TerminalSurfaceCommandLauncher.gitTUICommand)
            .compactMap(\.text)
            .joined()

        #expect(rendered == "yengit\r")
    }

    @Test func commandInputStepsPreserveExpectedCharacters() {
        let rendered = TerminalSurfaceCommandLauncher
            .commandInputSteps(for: "yen ide share host --read-only")
            .map(\.text)
            .joined()

        #expect(rendered == "yen ide share host --read-only")
    }

    @Test func responderChainTargetWinsOverFallback() {
        let fallback = TestTargetResponder()
        let target = TestTargetResponder()
        let intermediate = TestResponder(next: target)
        let chain = TestResponder(next: intermediate)

        let resolved = TerminalSurfaceCommandLauncher.resolvedTarget(
            firstResponder: chain,
            fallback: fallback
        )

        #expect(resolved === target)
    }

    @Test func fallbackIsUsedWhenResponderChainHasNoTarget() {
        let fallback = TestTargetResponder()
        let chain = TestResponder(next: TestResponder())

        let resolved = TerminalSurfaceCommandLauncher.resolvedTarget(
            firstResponder: chain,
            fallback: fallback
        )

        #expect(resolved === fallback)
    }

    @Test func unresolvedTargetFailsClosed() {
        let resolved: TestTargetResponder? = TerminalSurfaceCommandLauncher.resolvedTarget(
            firstResponder: TestResponder(next: TestResponder()),
            fallback: nil
        )

        #expect(resolved == nil)
    }
}

@MainActor
private final class TestResponder: NSResponder {
    init(next: NSResponder? = nil) {
        super.init()
        self.nextResponder = next
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class TestTargetResponder: NSResponder {
    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
