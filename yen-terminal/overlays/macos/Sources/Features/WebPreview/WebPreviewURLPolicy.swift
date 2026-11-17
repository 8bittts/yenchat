#if os(macOS)
import Foundation

enum WebPreviewURLDecision: Equatable, Sendable {
    case load(URL)
    case openExternally(URL)
    case block(String)
}

enum WebPreviewNavigationFrame: Sendable {
    case mainFrame
    case subframe
}

enum WebPreviewNavigationDecision: Equatable, Sendable {
    case allow
    case openExternally(URL)
    case block(String)
}

enum WebPreviewNavigationPolicy {
    static func decision(for rawValue: String, frame: WebPreviewNavigationFrame) -> WebPreviewNavigationDecision {
        switch WebPreviewURLPolicy.decision(for: rawValue) {
        case .load:
            return .allow
        case .openExternally(let url):
            switch frame {
            case .mainFrame:
                return .openExternally(url)
            case .subframe:
                return .block("External URL schemes are not opened from embedded web content.")
            }
        case .block(let message):
            return .block(message)
        }
    }
}

enum WebPreviewURLPolicy {
    static func decision(for rawValue: String) -> WebPreviewURLDecision {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .block("Enter a URL to open.")
        }

        let candidate = normalizedURLString(for: trimmed)
        guard let url = URL(string: candidate),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased()
        else {
            return .block("That URL could not be read.")
        }

        switch scheme {
        case "https":
            return .load(url)
        case "http":
            guard let host = components.host, isLoopbackHost(host) else {
                return .block("Only HTTPS or localhost HTTP URLs can open in YEN.")
            }
            return .load(url)
        case "mailto", "tel":
            return .openExternally(url)
        case "file":
            return .block("File URLs are not opened silently.")
        case "data", "javascript", "blob":
            return .block("That URL scheme is blocked.")
        default:
            return .block("That URL scheme is not opened in YEN.")
        }
    }

    private static func normalizedURLString(for rawValue: String) -> String {
        let lowercased = rawValue.lowercased()
        if lowercased.contains("://") {
            return rawValue
        }
        if isBareLoopbackURL(lowercased) {
            return "http://\(rawValue)"
        }
        if isBareHostPortURL(lowercased) {
            return "https://\(rawValue)"
        }
        if hasExplicitScheme(lowercased) {
            return rawValue
        }
        return "https://\(rawValue)"
    }

    private static func isBareLoopbackURL(_ value: String) -> Bool {
        let authorityEnd = value.firstIndex { character in
            character == "/" || character == "?" || character == "#"
        } ?? value.endIndex
        let authority = String(value[..<authorityEnd])
        guard !authority.isEmpty else { return false }
        return isLoopbackHost(hostFromBareAuthority(authority))
    }

    private static func isBareHostPortURL(_ value: String) -> Bool {
        let authorityEnd = value.firstIndex { character in
            character == "/" || character == "?" || character == "#"
        } ?? value.endIndex
        let authority = String(value[..<authorityEnd])
        guard let portSeparator = authority.lastIndex(of: ":") else { return false }
        let host = String(authority[..<portSeparator])
        let port = String(authority[authority.index(after: portSeparator)...])
        guard !host.isEmpty, UInt16(port) != nil else { return false }
        guard !hasIPv4LoopbackLookalikePrefix(host) else { return false }
        return host.contains(".") || host.allSatisfy { $0.isNumber }
    }

    private static func hasIPv4LoopbackLookalikePrefix(_ host: String) -> Bool {
        let labels = host.lowercased().split(separator: ".")
        guard labels.first == "127" else { return false }
        return !isLoopbackHost(host)
    }

    private static func hostFromBareAuthority(_ authority: String) -> String {
        if authority.hasPrefix("["),
           let closingBracket = authority.firstIndex(of: "]") {
            return String(authority[authority.startIndex...closingBracket])
        }
        if let portSeparator = authority.firstIndex(of: ":") {
            return String(authority[..<portSeparator])
        }
        return authority
    }

    private static func hasExplicitScheme(_ value: String) -> Bool {
        guard let colonIndex = value.firstIndex(of: ":") else { return false }
        let prefix = value[..<colonIndex]
        guard !prefix.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789+-.")
        return prefix.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let lowercased = host.lowercased()
        if lowercased == "localhost" || lowercased.hasSuffix(".localhost") {
            return true
        }
        if lowercased == "::1" || lowercased == "[::1]" {
            return true
        }
        let octets = lowercased.split(separator: ".")
        if octets.count == 4, octets.first == "127" {
            return octets.allSatisfy { UInt8($0) != nil }
        }
        return false
    }
}
#endif
