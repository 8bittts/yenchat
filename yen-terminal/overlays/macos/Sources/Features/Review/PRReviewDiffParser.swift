#if os(macOS)
import AppKit
import Foundation
import SwiftUI

enum PullRequestReviewDiffParser {
    private struct UnifiedDiffHunkHeader {
        let oldStart: Int
        let newStart: Int
        let newCount: Int
        let header: String
    }

    static func parse(_ rawDiff: String) -> [PullRequestReviewDiffBlock] {
        let normalized = rawDiff.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var blocks: [PullRequestReviewDiffBlock] = []
        var currentLines: [String] = []
        var currentOldPath: String?
        var currentNewPath: String?
        var isInsideHunk = false

        func flushCurrentBlock() {
            guard !currentLines.isEmpty else { return }
            var keys: [String] = []
            if let currentNewPath, !keys.contains(currentNewPath) {
                keys.append(currentNewPath)
            }
            if let currentOldPath, !keys.contains(currentOldPath) {
                keys.append(currentOldPath)
            }
            blocks.append(
                PullRequestReviewDiffBlock(
                    keys: keys,
                    diff: currentLines.joined(separator: "\n")
                )
            )
            currentLines = []
            currentOldPath = nil
            currentNewPath = nil
            isInsideHunk = false
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                flushCurrentBlock()
                currentLines = [line]
                if let headerPaths = parseDiffGitHeader(line) {
                    currentOldPath = headerPaths.oldPath
                    currentNewPath = headerPaths.newPath
                }
                continue
            }

            guard !currentLines.isEmpty else { continue }
            currentLines.append(line)

            if line.hasPrefix("@@") {
                isInsideHunk = true
                continue
            }
            // Once a hunk starts, `--- source` and `+++ source` are ordinary
            // deletion/addition lines whose source happens to begin with two
            // more prefix characters. Only the preamble can carry path headers.
            guard !isInsideHunk else { continue }

            if line.hasPrefix("rename from ") {
                currentOldPath = normalizeDiffPath(String(line.dropFirst("rename from ".count)))
                continue
            }
            if line.hasPrefix("rename to ") {
                currentNewPath = normalizeDiffPath(String(line.dropFirst("rename to ".count)))
                continue
            }
            if line.hasPrefix("--- ") {
                currentOldPath = normalizeDiffPath(String(line.dropFirst(4)))
                continue
            }
            if line.hasPrefix("+++ ") {
                currentNewPath = normalizeDiffPath(String(line.dropFirst(4)))
            }
        }

        flushCurrentBlock()
        return blocks
    }

    static func index(_ rawDiff: String) -> PullRequestReviewDiffIndex {
        index(from: parse(rawDiff))
    }

    static func index(from blocks: [PullRequestReviewDiffBlock]) -> PullRequestReviewDiffIndex {
        PullRequestReviewDiffIndex(blocks: blocks)
    }

    static func focusedDiff(for path: String, from blocks: [PullRequestReviewDiffBlock]) -> String? {
        blocks.first(where: { $0.keys.contains(path) })?.diff
    }

    static func focusedDiff(for path: String, from index: PullRequestReviewDiffIndex) -> String? {
        index.focusedDiff(for: path)
    }

    static func hunks(
        for path: String,
        repoRoot: String,
        from blocks: [PullRequestReviewDiffBlock]
    ) -> [PullRequestReviewDiffHunk] {
        guard let diff = focusedDiff(for: path, from: blocks) else { return [] }
        return hunks(
            for: path,
            repoRoot: repoRoot,
            diff: diff
        )
    }

    static func hunks(
        for path: String,
        repoRoot: String,
        from index: PullRequestReviewDiffIndex
    ) -> [PullRequestReviewDiffHunk] {
        guard let diff = index.focusedDiff(for: path) else { return [] }
        return hunks(
            for: path,
            repoRoot: repoRoot,
            diff: diff
        )
    }

    static func hunks(
        for path: String,
        repoRoot: String,
        diff: String
    ) -> [PullRequestReviewDiffHunk] {
        let normalized = diff.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var preamble: [String] = []
        var currentHeader: UnifiedDiffHunkHeader?
        var currentBody: [String] = []
        var currentIndex = 0
        var currentOldLine = 0
        var currentNewLine = 0
        var firstChangedLine: Int?
        var firstDeletedOldLine: Int?
        var firstDeletedNewLine: Int?
        var hunks: [PullRequestReviewDiffHunk] = []

        func flushCurrentHunk() {
            guard let currentHeader else { return }
            let fallbackLine = currentHeader.newCount > 0
                ? currentHeader.newStart
                : currentHeader.oldStart
            let deletionLocationLine: Int? = {
                guard let firstDeletedOldLine else { return nil }
                guard currentHeader.newCount > 0, let firstDeletedNewLine else {
                    return firstDeletedOldLine
                }
                let lastNewLine = currentHeader.newStart + currentHeader.newCount - 1
                return min(firstDeletedNewLine, lastNewLine)
            }()
            let locationLine = max(1, firstChangedLine ?? deletionLocationLine ?? fallbackLine)
            let commentLine = max(1, firstChangedLine ?? firstDeletedOldLine ?? fallbackLine)
            let location = IDESemanticLocation.repositoryLocation(
                repoRoot: repoRoot,
                relativePath: path,
                line: locationLine,
                column: 1
            )
            let diffLines = preamble + [currentHeader.header] + currentBody
            let hunkDiff = diffLines.joined(separator: "\n")
            hunks.append(
                PullRequestReviewDiffHunk(
                    id: "\(path)#\(currentIndex)",
                    index: currentIndex,
                    header: currentHeader.header,
                    location: location,
                    commentLine: commentLine,
                    commentSide: firstChangedLine != nil
                        ? .right
                        : (firstDeletedOldLine != nil || currentHeader.newCount == 0 ? .left : .right),
                    diff: hunkDiff
                )
            )
            selfReset()
        }

        func selfReset() {
            currentHeader = nil
            currentBody = []
            firstChangedLine = nil
            firstDeletedOldLine = nil
            firstDeletedNewLine = nil
            currentOldLine = 0
            currentNewLine = 0
        }

        for line in lines {
            if let parsedHeader = parseHunkHeader(line) {
                flushCurrentHunk()
                currentIndex += 1
                currentHeader = parsedHeader
                currentOldLine = parsedHeader.oldStart
                currentNewLine = parsedHeader.newStart
                continue
            }

            if currentHeader == nil {
                preamble.append(line)
                continue
            }

            currentBody.append(line)

            if firstChangedLine == nil, line.hasPrefix("+") {
                firstChangedLine = currentNewLine
            }
            if firstDeletedOldLine == nil, line.hasPrefix("-") {
                firstDeletedOldLine = currentOldLine
                firstDeletedNewLine = currentNewLine
            }

            if line.hasPrefix(" ") {
                currentOldLine += 1
                currentNewLine += 1
            } else if line.hasPrefix("+") {
                currentNewLine += 1
            } else if line.hasPrefix("-") {
                currentOldLine += 1
            }
        }

        flushCurrentHunk()
        return hunks
    }

    private static func normalizeDiffPath(_ rawPath: String, splitTabMetadata: Bool = true) -> String? {
        var trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if let quotedPath = parseQuotedGitPath(trimmed[...])?.path {
            trimmed = quotedPath
        } else if splitTabMetadata, let tabIndex = trimmed.firstIndex(of: "\t") {
            trimmed = String(trimmed[..<tabIndex])
        }
        guard !trimmed.isEmpty, trimmed != "/dev/null" else { return nil }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    private static func parseDiffGitHeader(_ line: String) -> (oldPath: String?, newPath: String?)? {
        let prefix = "diff --git "
        guard line.hasPrefix(prefix) else { return nil }

        let body = String(line.dropFirst(prefix.count))
        if body.hasPrefix("\"") {
            guard let oldToken = parseQuotedGitPath(body[...]) else { return nil }
            let remainder = oldToken.remainder.trimmingCharacters(in: .whitespaces)
            guard let newToken = parseQuotedGitPath(remainder[...]) else { return nil }
            return (
                oldPath: normalizeDiffPath(oldToken.path, splitTabMetadata: false),
                newPath: normalizeDiffPath(newToken.path, splitTabMetadata: false)
            )
        }

        guard let paths = parseUnquotedDiffGitHeaderBody(body) else { return nil }
        return (
            oldPath: normalizeDiffPath(paths.oldPath),
            newPath: normalizeDiffPath(paths.newPath)
        )
    }

    private static func parseUnquotedDiffGitHeaderBody(_ body: String) -> (oldPath: String, newPath: String)? {
        guard body.hasPrefix("a/") else {
            let tokens = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard tokens.count == 2 else { return nil }
            return (String(tokens[0]), String(tokens[1]))
        }

        var candidates: [(oldPath: String, newPath: String)] = []
        var searchRange = body.index(body.startIndex, offsetBy: 2)..<body.endIndex
        while let delimiterRange = body.range(of: " b/", range: searchRange) {
            let newPathStart = body.index(after: delimiterRange.lowerBound)
            candidates.append((
                oldPath: String(body[..<delimiterRange.lowerBound]),
                newPath: String(body[newPathStart...])
            ))
            searchRange = body.index(after: delimiterRange.lowerBound)..<body.endIndex
        }

        if let samePathCandidate = candidates.first(where: { candidate in
            guard
                let oldPath = normalizeDiffPath(candidate.oldPath),
                let newPath = normalizeDiffPath(candidate.newPath)
            else { return false }
            return oldPath == newPath
        }) {
            return samePathCandidate
        }

        return candidates.last
    }

    private static func parseQuotedGitPath(_ rawText: Substring) -> (path: String, remainder: Substring)? {
        guard rawText.first == "\"" else { return nil }

        var pathBytes: [UInt8] = []
        var cursor = rawText.index(after: rawText.startIndex)
        while cursor < rawText.endIndex {
            let character = rawText[cursor]
            if character == "\"" {
                let path = String(decoding: pathBytes, as: UTF8.self)
                return (path, rawText[rawText.index(after: cursor)...])
            }

            if character == "\\" {
                let escapeStart = rawText.index(after: cursor)
                guard escapeStart < rawText.endIndex else {
                    pathBytes.append(contentsOf: "\\".utf8)
                    let path = String(decoding: pathBytes, as: UTF8.self)
                    return (path, rawText[escapeStart...])
                }

                if let parsedOctal = parseGitOctalEscape(in: rawText, from: escapeStart) {
                    pathBytes.append(parsedOctal.byte)
                    cursor = parsedOctal.endIndex
                    continue
                }

                pathBytes.append(contentsOf: String(unescapeGitPathCharacter(rawText[escapeStart])).utf8)
                cursor = rawText.index(after: escapeStart)
                continue
            }

            pathBytes.append(contentsOf: String(character).utf8)
            cursor = rawText.index(after: cursor)
        }

        return nil
    }

    private static func parseGitOctalEscape(
        in text: Substring,
        from startIndex: Substring.Index
    ) -> (byte: UInt8, endIndex: Substring.Index)? {
        var digits = ""
        var cursor = startIndex
        while cursor < text.endIndex,
              digits.count < 3,
              let value = text[cursor].wholeNumberValue,
              (0...7).contains(value) {
            digits.append(text[cursor])
            cursor = text.index(after: cursor)
        }

        guard
            !digits.isEmpty,
            let byte = UInt8(digits, radix: 8)
        else { return nil }

        return (byte, cursor)
    }

    private static func unescapeGitPathCharacter(_ character: Character) -> Character {
        switch character {
        case "a":
            return "\u{7}"
        case "b":
            return "\u{8}"
        case "f":
            return "\u{c}"
        case "n":
            return "\n"
        case "r":
            return "\r"
        case "t":
            return "\t"
        case "v":
            return "\u{b}"
        default:
            return character
        }
    }

    private static func parseHunkHeader(_ rawLine: String) -> UnifiedDiffHunkHeader? {
        guard rawLine.hasPrefix("@@ -") else { return nil }

        let body = String(rawLine.dropFirst(4))
        guard let markerRange = body.range(of: " @@") else { return nil }
        let rangePart = String(body[..<markerRange.lowerBound])
        let components = rangePart.split(separator: " ", omittingEmptySubsequences: true)
        guard components.count == 2 else { return nil }

        let oldRange = parseRange(String(components[0]))
        var newToken = String(components[1])
        guard newToken.hasPrefix("+") else { return nil }
        newToken.removeFirst()
        let newRange = parseRange(newToken)

        guard let oldRange, let newRange else { return nil }
        return UnifiedDiffHunkHeader(
            oldStart: oldRange.start,
            newStart: newRange.start,
            newCount: newRange.count,
            header: rawLine
        )
    }

    private static func parseRange(_ rawValue: String) -> (start: Int, count: Int)? {
        let pieces = rawValue.split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(pieces[0]) else { return nil }
        if pieces.count == 1 {
            return (start, 1)
        }
        guard let count = Int(pieces[1]) else { return nil }
        return (start, count)
    }
}

#endif
