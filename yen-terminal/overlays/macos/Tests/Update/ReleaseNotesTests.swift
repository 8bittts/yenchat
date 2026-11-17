import Foundation
import Testing
@testable import YEN

struct ReleaseNotesTests {
    @Test func taggedRelease() {
        let notes = UpdateState.ReleaseNotes(
            displayVersionString: "1.2.3",
            currentCommit: nil
        )

        #expect(notes != nil)
        if case .tagged(let url) = notes {
            #expect(url.absoluteString == "https://yen.chat/docs/install/release-notes/1-2-3")
            #expect(notes?.label == "View Release Notes")
        } else {
            Issue.record("Expected tagged case")
        }
    }

    @Test func tipReleaseComparison() {
        let notes = UpdateState.ReleaseNotes(
            displayVersionString: "tip-abc1234",
            currentCommit: "def5678"
        )

        #expect(notes != nil)
        if case .compareTip(let url) = notes {
            #expect(url.absoluteString == "https://github.com/yen-org/yen/compare/def5678...abc1234")
            #expect(notes?.label == "Changes Since This Tip Release")
        } else {
            Issue.record("Expected compareTip case")
        }
    }

    @Test func tipReleaseWithoutCurrentCommit() {
        let notes = UpdateState.ReleaseNotes(
            displayVersionString: "tip-abc1234",
            currentCommit: nil
        )

        #expect(notes != nil)
        if case .commit(let url) = notes {
            #expect(url.absoluteString == "https://github.com/yen-org/yen/commit/abc1234")
            #expect(notes?.label == "View GitHub Commit")
        } else {
            Issue.record("Expected commit case")
        }
    }

    @Test func tipReleaseWithEmptyCurrentCommit() {
        let notes = UpdateState.ReleaseNotes(
            displayVersionString: "tip-abc1234",
            currentCommit: ""
        )

        #expect(notes != nil)
        if case .commit(let url) = notes {
            #expect(url.absoluteString == "https://github.com/yen-org/yen/commit/abc1234")
        } else {
            Issue.record("Expected commit case")
        }
    }

    @Test func fullGitHash() {
        let notes = UpdateState.ReleaseNotes(
            displayVersionString: "tip-1234567890abcdef1234567890abcdef12345678",
            currentCommit: nil
        )

        #expect(notes != nil)
        if case .commit(let url) = notes {
            #expect(url.absoluteString == "https://github.com/yen-org/yen/commit/1234567890abcdef1234567890abcdef12345678")
        } else {
            Issue.record("Expected commit case")
        }
    }

    @Test func invalidVersion() {
        let notes = UpdateState.ReleaseNotes(
            displayVersionString: "unknown-version",
            currentCommit: nil
        )

        #expect(notes == nil)
    }

    @Test func semanticVersionWithSuffix() {
        let notes = UpdateState.ReleaseNotes(
            displayVersionString: "1.2.3-beta",
            currentCommit: nil
        )

        #expect(notes == nil)
    }

    @Test func semanticVersionFourComponents() {
        let notes = UpdateState.ReleaseNotes(
            displayVersionString: "1.2.3.4",
            currentCommit: nil
        )

        #expect(notes == nil)
    }

    @Test func versionWithEmbeddedHash() {
        let notes = UpdateState.ReleaseNotes(
            displayVersionString: "v2024.01.15-abc1234",
            currentCommit: "def5678"
        )

        #expect(notes != nil)
        if case .compareTip(let url) = notes {
            #expect(url.absoluteString == "https://github.com/yen-org/yen/compare/def5678...abc1234")
        } else {
            Issue.record("Expected compareTip case")
        }
    }
}
