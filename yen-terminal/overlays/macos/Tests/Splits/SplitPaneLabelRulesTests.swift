import AppKit
import Testing
@testable import YEN

struct SplitPaneLabelRulesTests {
    @Test func meaningfulSurfaceTitleWins() {
        #expect(
            SplitPaneLabelRules.displayTitle(
                explicitLabel: nil,
                surfaceTitle: "backend-worker",
                workingDirectory: "/Users/dev/project"
            ) == "backend-worker"
        )
    }

    @Test func explicitLabelWinsEvenWhenItMatchesTheOldPlaceholder() {
        #expect(
            SplitPaneLabelRules.displayTitle(
                explicitLabel: "YEN",
                surfaceTitle: "backend-worker",
                workingDirectory: "/Users/dev/project"
            ) == "YEN"
        )
    }

    @Test func placeholderTitleFallsBackToWorkingDirectoryLeaf() {
        #expect(
            SplitPaneLabelRules.displayTitle(
                explicitLabel: nil,
                surfaceTitle: "YEN",
                workingDirectory: "/Users/dev/project"
            ) == "project"
        )
    }

    @Test func worktreeLabelOutranksTheSurfaceTitle() {
        #expect(
            SplitPaneLabelRules.displayTitle(
                explicitLabel: nil,
                worktreeLabel: "split-labels-7f3a",
                surfaceTitle: "backend-worker",
                workingDirectory: "/Users/dev/project"
            ) == "split-labels-7f3a"
        )
    }

    @Test func handTypedLabelOutranksTheWorktreeLabel() {
        #expect(
            SplitPaneLabelRules.displayTitle(
                explicitLabel: "tests",
                worktreeLabel: "split-labels-7f3a",
                surfaceTitle: "backend-worker",
                workingDirectory: "/Users/dev/project"
            ) == "tests"
        )
    }

    @Test func blankWorktreeLabelKeepsTheExistingFallbackChain() {
        #expect(
            SplitPaneLabelRules.displayTitle(
                explicitLabel: nil,
                worktreeLabel: "   ",
                surfaceTitle: "backend-worker",
                workingDirectory: "/Users/dev/project"
            ) == "backend-worker"
        )
    }

    @Test func placeholderTitleFallsBackToGenericLabelWithoutWorkingDirectory() {
        #expect(
            SplitPaneLabelRules.displayTitle(
                explicitLabel: nil,
                surfaceTitle: "YEN",
                workingDirectory: nil
            ) == "Terminal"
        )
    }

    @Test func headersRequireEnabledLabelsAndEnoughRoomInASplit() {
        let size = CGSize(width: 220, height: 120)
        #expect(SplitPaneLabelRules.isVisible(enabled: true, isSplit: true, availableSize: size))
        #expect(!SplitPaneLabelRules.isVisible(enabled: false, isSplit: true, availableSize: size))
        #expect(!SplitPaneLabelRules.isVisible(enabled: true, isSplit: false, availableSize: size))
        #expect(!SplitPaneLabelRules.isVisible(enabled: true, isSplit: true, availableSize: .init(width: 100, height: 120)))
        #expect(!SplitPaneLabelRules.isVisible(enabled: true, isSplit: true, availableSize: .init(width: 220, height: 60)))
    }

    @Test func paneIconsRecognizeForegroundToolsAndWrappedTitles() {
        #expect(PaneActivity.resolve(process: "nvim", title: "Codex") == .editor)
        #expect(PaneActivity.resolve(process: "node", title: "OpenAI Codex") == .codex)
        #expect(PaneActivity.resolve(process: "zmx", title: "✳ Claude Code") == .claude)
        #expect(PaneActivity.resolve(process: "zsh", title: "~/work/codex") == .terminal)
        #expect(PaneActivity.resolve(process: "git", title: "project") == .git)
    }

    @Test func foregroundRoleTracksBackgroundLuminance() {
        #expect(SplitPaneLabelRules.foregroundRole(backgroundColor: .white) == .dark)
        #expect(SplitPaneLabelRules.foregroundRole(backgroundColor: .black) == .light)
    }

    @Test func splitPaneLabelNormalizationTrimsAndClearsBlankValues() {
        #expect(YEN.SurfaceView.normalizedSplitPaneLabel("  Team Ops  ") == "Team Ops")
        #expect(YEN.SurfaceView.normalizedSplitPaneLabel("   ") == nil)
        #expect(YEN.SurfaceView.normalizedSplitPaneLabel(nil) == nil)
    }

}
