import Foundation
import Testing
@testable import YEN

struct WebPreviewURLPolicyTests {
    @Test func allowsHTTPS() {
        #expect(WebPreviewURLPolicy.decision(for: "https://yen.chat/docs") == .load(URL(string: "https://yen.chat/docs")!))
    }

    @Test func normalizesBareHostsToHTTPS() {
        #expect(WebPreviewURLPolicy.decision(for: "yen.chat/docs") == .load(URL(string: "https://yen.chat/docs")!))
        #expect(WebPreviewURLPolicy.decision(for: "yen.chat:443/docs") == .load(URL(string: "https://yen.chat:443/docs")!))
    }

    @Test func allowsLocalhostHTTP() {
        #expect(WebPreviewURLPolicy.decision(for: "http://localhost:3000") == .load(URL(string: "http://localhost:3000")!))
        #expect(WebPreviewURLPolicy.decision(for: "127.0.0.1:5173") == .load(URL(string: "http://127.0.0.1:5173")!))
        #expect(WebPreviewURLPolicy.decision(for: "localhost/docs") == .load(URL(string: "http://localhost/docs")!))
        #expect(WebPreviewURLPolicy.decision(for: "[::1]:8080") == .load(URL(string: "http://[::1]:8080")!))
        #expect(WebPreviewURLPolicy.decision(for: "http://[::1]:8080") == .load(URL(string: "http://[::1]:8080")!))
    }

    @Test func preservesLocalhostSubdomainsButBlocksLookalikeIPv4Hosts() {
        #expect(WebPreviewURLPolicy.decision(for: "http://app.localhost:3000") == .load(URL(string: "http://app.localhost:3000")!))
        #expect(WebPreviewURLPolicy.decision(for: "app.localhost:3000") == .load(URL(string: "http://app.localhost:3000")!))

        if case .block = WebPreviewURLPolicy.decision(for: "127.example.test:8080") {
        } else {
            Issue.record("Expected 127.example.test to be blocked")
        }

        if case .block = WebPreviewURLPolicy.decision(for: "127.0.0.256:8080") {
        } else {
            Issue.record("Expected invalid 127.* host to be blocked")
        }

        if case .block = WebPreviewURLPolicy.decision(for: "http://localhost.evil.test:3000") {
        } else {
            Issue.record("Expected http://localhost.evil.test to be blocked")
        }
    }

    @Test func blocksNonLoopbackHTTP() {
        if case .block(let message) = WebPreviewURLPolicy.decision(for: "http://example.com") {
            #expect(message.contains("HTTPS"))
        } else {
            Issue.record("Expected non-loopback HTTP to be blocked")
        }
    }

    @Test func handsOffMailAndTelephoneSchemes() {
        #expect(WebPreviewURLPolicy.decision(for: "mailto:hello@yen.chat") == .openExternally(URL(string: "mailto:hello@yen.chat")!))
        #expect(WebPreviewURLPolicy.decision(for: "tel:+15555550100") == .openExternally(URL(string: "tel:+15555550100")!))
    }

    @Test func navigationPolicyAppliesURLRulesToSubframes() {
        #expect(WebPreviewNavigationPolicy.decision(for: "https://yen.chat/frame", frame: .subframe) == .allow)
        #expect(WebPreviewNavigationPolicy.decision(for: "mailto:hello@yen.chat", frame: .mainFrame) == .openExternally(URL(string: "mailto:hello@yen.chat")!))

        if case .block(let message) = WebPreviewNavigationPolicy.decision(for: "http://example.com", frame: .subframe) {
            #expect(message.contains("HTTPS"))
        } else {
            Issue.record("Expected non-loopback HTTP subframe navigation to be blocked")
        }

        if case .block(let message) = WebPreviewNavigationPolicy.decision(for: "mailto:hello@yen.chat", frame: .subframe) {
            #expect(message.contains("embedded web content"))
        } else {
            Issue.record("Expected external subframe navigation to be blocked")
        }
    }

    @Test func blocksUnsafeSchemes() {
        let blockedInputs = [
            "file:///Users/dev/secrets.txt",
            "data:text/plain,hello",
            "javascript:alert(1)",
            "blob:https://yen.chat/abc",
        ]

        for input in blockedInputs {
            if case .block = WebPreviewURLPolicy.decision(for: input) {
                continue
            }
            Issue.record("Expected \(input) to be blocked")
        }
    }
}
