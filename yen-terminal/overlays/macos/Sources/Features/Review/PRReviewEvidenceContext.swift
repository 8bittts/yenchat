#if os(macOS)
import AppKit
import Foundation
import SwiftUI

enum PullRequestReviewLocalEvidenceContextLoader {
    private struct VerifyDetailSection {
        let category: String
        let result: String
        let command: String
        let outputLines: [String]
        let outputExcerpt: [String]
    }

    private struct VerifyStep {
        let id: String
        let exitCode: Int
        let result: String
        let category: String
        let summary: String
    }

    static var defaultIDEStateDirectory: String {
        ReviewIDEStateDirectory.defaultPath
    }

    static func load(repoRoot: String, ideStateDirectoryOverride: String? = nil) -> PullRequestReviewEvidenceContext {
        let ideStateDirectory = resolvedIDEStateDirectory(override: ideStateDirectoryOverride)
        let timelinePath = URL(fileURLWithPath: ideStateDirectory)
            .appendingPathComponent("timeline.log")
            .path

        let timelineLines = readLines(at: timelinePath)
        let verifyTimelineEntry = latestVerifyTimelineEntry(
            repoRoot: repoRoot,
            lines: Array(timelineLines.suffix(400))
        )
        let latestVerifySummaryPath = latestVerifyArtifactPath(
            repoRoot: repoRoot,
            lines: Array(timelineLines.suffix(400)),
            key: "summary"
        )
        let latestVerifySummaryContents = latestVerifySummaryPath.flatMap { readText(at: $0) }
        let latestVerifyDetailsPath = latestVerifySummaryPath.flatMap { detailsPath(forSummaryPath: $0) }
        let latestVerifySemanticPath = latestVerifyArtifactPath(
            repoRoot: repoRoot,
            lines: Array(timelineLines.suffix(400)),
            key: "semantic"
        )
        let latestVerifySemanticContents = latestVerifySemanticPath.flatMap { readText(at: $0) }
        let latestVerifyStatus = latestVerifyStatusSnapshot(
            timelineEntry: verifyTimelineEntry,
            summaryPath: latestVerifySummaryPath,
            detailsPath: latestVerifyDetailsPath,
            semanticPath: latestVerifySemanticPath
        )
        let recentTimelineEvents = recentTimelineEvents(
            repoRoot: repoRoot,
            lines: Array(timelineLines.suffix(120))
        )

        return PullRequestReviewEvidenceContext(
            ideStateDirectory: ideStateDirectory,
            latestVerifySummaryPath: latestVerifySummaryPath,
            latestVerifySummaryContents: latestVerifySummaryContents,
            latestVerifySemanticPath: latestVerifySemanticPath,
            latestVerifySemanticContents: latestVerifySemanticContents,
            latestVerifyStatus: latestVerifyStatus,
            recentTimelineEvents: recentTimelineEvents
        )
    }

    private static func resolvedIDEStateDirectory(override: String?) -> String {
        ReviewIDEStateDirectory.resolved(override: override)
    }

    private static func readLines(at path: String) -> [String] {
        guard let text = readText(at: path), !text.isEmpty else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private static func readText(at path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let ascii = String(data: data, encoding: .ascii) {
            return ascii.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func detailsPath(forSummaryPath summaryPath: String) -> String? {
        guard summaryPath.hasSuffix(".tsv") else { return nil }
        return String(summaryPath.dropLast(4)) + ".log"
    }

    private static func latestVerifyArtifactPath(repoRoot: String, lines: [String], key: String) -> String? {
        for line in lines.reversed() {
            guard let timelineLine = parseTimelineLine(line),
                  timelineLine.event == "verify",
                  timelineLine.projectRoot == repoRoot else {
                continue
            }

            if let value = detailValue(named: key, detail: timelineLine.detail) {
                return value
            }
        }

        return nil
    }

    private static func latestVerifyTimelineEntry(
        repoRoot: String,
        lines: [String]
    ) -> (timestamp: String, event: String, projectRoot: String, status: String, detail: String)? {
        for line in lines.reversed() {
            guard let timelineLine = parseTimelineLine(line),
                  timelineLine.event == "verify",
                  timelineLine.projectRoot == repoRoot else {
                continue
            }
            return timelineLine
        }

        return nil
    }

    private static func latestVerifyStatusSnapshot(
        timelineEntry: (timestamp: String, event: String, projectRoot: String, status: String, detail: String)?,
        summaryPath: String?,
        detailsPath: String?,
        semanticPath: String?
    ) -> PullRequestReviewVerifyStatusSnapshot {
        let failureCount = Int(statusValue(named: "failures", status: timelineEntry?.status ?? "") ?? "0") ?? 0
        let warningCount = Int(statusValue(named: "warns", status: timelineEntry?.status ?? "") ?? "0") ?? 0

        let latestStatus: String
        if timelineEntry == nil {
            latestStatus = "never-run"
        } else if let summaryPath, FileManager.default.fileExists(atPath: summaryPath) == false {
            latestStatus = "report-missing"
        } else if failureCount > 0 {
            latestStatus = "failing"
        } else if warningCount > 0 {
            latestStatus = "warnings"
        } else {
            latestStatus = "passing"
        }

        let steps = loadVerifySteps(summaryPath: summaryPath, detailsPath: detailsPath)
        let securitySteps = steps
            .filter { $0.category == "security" }
            .map {
                PullRequestReviewVerifySecurityStep(
                    id: $0.id,
                    result: $0.result,
                    exitCode: $0.exitCode,
                    summary: $0.summary
                )
            }

        let readinessStatus: String
        let readinessReason: String
        let mergeReady: Bool
        switch latestStatus {
        case "passing":
            readinessStatus = "ready"
            readinessReason = "Latest local verify run passed."
            mergeReady = true
        case "warnings":
            readinessStatus = "warning"
            readinessReason = "Latest local verify run has warnings."
            mergeReady = false
        case "failing":
            readinessStatus = "blocked"
            readinessReason = "Latest local verify run has failures."
            mergeReady = false
        case "report-missing":
            readinessStatus = "blocked"
            readinessReason = "Latest local verify report is missing."
            mergeReady = false
        default:
            readinessStatus = "unavailable"
            readinessReason = "Run yen ide verify --quick to establish a local verify baseline."
            mergeReady = false
        }

        let securityFailingSteps = securitySteps.filter { $0.result == "fail" }.count
        let securityWarningSteps = securitySteps.filter { $0.result == "warn" }.count
        let securityStatus: String
        let securityReason: String
        if securitySteps.isEmpty {
            securityStatus = "unavailable"
            securityReason = "No security steps were recorded in the latest local verify report."
        } else if securityFailingSteps > 0 {
            securityStatus = "blocked"
            securityReason = "Latest local security checks contain blocking failures."
        } else if securityWarningSteps > 0 {
            securityStatus = "warning"
            securityReason = "Latest local security checks contain warnings or missing tools."
        } else {
            securityStatus = "ready"
            securityReason = "Latest local security checks passed."
        }

        return PullRequestReviewVerifyStatusSnapshot(
            latestStatus: latestStatus,
            lastRunAt: timelineEntry?.timestamp ?? "",
            summaryReportPath: summaryPath,
            detailsReportPath: detailsPath,
            semanticReportPath: semanticPath,
            readinessStatus: readinessStatus,
            readinessReason: readinessReason,
            mergeReady: mergeReady,
            securityStatus: securityStatus,
            securityReason: securityReason,
            securityStepCount: securitySteps.count,
            securityWarningSteps: securityWarningSteps,
            securityFailingSteps: securityFailingSteps,
            securitySteps: securitySteps
        )
    }

    private static func loadVerifySteps(summaryPath: String?, detailsPath: String?) -> [VerifyStep] {
        guard let summaryPath,
              FileManager.default.fileExists(atPath: summaryPath),
              let summaryText = readText(at: summaryPath),
              !summaryText.isEmpty else {
            return []
        }

        let detailSections = loadDetailSections(at: detailsPath)
        return summaryText
            .split(whereSeparator: \.isNewline)
            .compactMap { row in
                let parts = String(row).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 2 else { return nil }
                let padded = parts + Array(repeating: "", count: max(0, 9 - parts.count))
                let stepName = padded[1]
                guard !stepName.isEmpty else { return nil }

                let exitCode = Int(padded[2]) ?? 0
                let command = padded[6]
                let detail = detailSections[stepName]
                let category = inferCategory(
                    stepName: stepName,
                    command: command.isEmpty ? detail?.command ?? "" : command,
                    explicit: padded[8].isEmpty ? detail?.category ?? "" : padded[8]
                )
                let result = inferResult(
                    stepName: stepName,
                    command: command.isEmpty ? detail?.command ?? "" : command,
                    exitCode: exitCode,
                    explicit: padded[7].isEmpty ? detail?.result ?? "" : padded[7]
                )

                var summary = detail?.outputExcerpt.first ?? ""
                if stepName == "osv-scanner",
                   let osvSummary = parseOSVSummary(outputLines: detail?.outputLines ?? []) {
                    summary = osvSummary
                }

                return VerifyStep(
                    id: stepName,
                    exitCode: exitCode,
                    result: result,
                    category: category,
                    summary: summary
                )
            }
    }

    private static func loadDetailSections(at path: String?) -> [String: VerifyDetailSection] {
        guard let path,
              FileManager.default.fileExists(atPath: path),
              let text = readText(at: path),
              !text.isEmpty else {
            return [:]
        }

        var sections: [String: VerifyDetailSection] = [:]
        var currentStepName: String?
        var category = ""
        var result = ""
        var command = ""
        var outputLines: [String] = []
        var readingOutput = false

        func commitCurrentSection() {
            guard let currentStepName else { return }
            let excerpt = outputLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            sections[currentStepName] = VerifyDetailSection(
                category: category,
                result: result,
                command: command,
                outputLines: outputLines,
                outputExcerpt: Array(excerpt.prefix(3))
            )
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("=== "), line.hasSuffix(" ===") {
                commitCurrentSection()
                currentStepName = String(line.dropFirst(4).dropLast(4))
                category = ""
                result = ""
                command = ""
                outputLines = []
                readingOutput = false
                continue
            }

            guard currentStepName != nil else { continue }
            if line == "--- output ---" {
                readingOutput = true
                continue
            }
            if readingOutput {
                outputLines.append(line)
                continue
            }
            if line.hasPrefix("category: ") {
                category = String(line.dropFirst("category: ".count))
            } else if line.hasPrefix("result: ") {
                result = String(line.dropFirst("result: ".count))
            } else if line.hasPrefix("command: ") {
                command = String(line.dropFirst("command: ".count))
            }
        }

        commitCurrentSection()
        return sections
    }

    private static func recentTimelineEvents(repoRoot: String, lines: [String]) -> [String] {
        let filtered = lines.filter { line in
            guard let parsed = parseTimelineLine(line) else { return false }
            return parsed.projectRoot == repoRoot
        }
        return Array(filtered.suffix(20))
    }

    private static func parseTimelineLine(_ line: String) -> (timestamp: String, event: String, projectRoot: String, status: String, detail: String)? {
        let components = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard components.count >= 5 else { return nil }
        return (
            timestamp: String(components[0]),
            event: String(components[1]),
            projectRoot: String(components[2]),
            status: String(components[3]),
            detail: String(components[4])
        )
    }

    private static func detailValue(named key: String, detail: String) -> String? {
        for part in detail.split(separator: ";", omittingEmptySubsequences: true) {
            let trimmed = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("\(key)=") {
                return String(trimmed.dropFirst(key.count + 1))
            }
        }
        return nil
    }

    private static func statusValue(named key: String, status: String) -> String? {
        for part in status.split(separator: ";", omittingEmptySubsequences: true) {
            let trimmed = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("\(key)=") {
                return String(trimmed.dropFirst(key.count + 1))
            }
        }
        return nil
    }

    private static func inferCategory(stepName: String, command: String, explicit: String) -> String {
        if !explicit.isEmpty {
            return explicit
        }
        if ["gitleaks", "node-audit", "osv-scanner"].contains(stepName) {
            return "security"
        }
        if stepName.contains("audit") || stepName.contains("gitleaks") || stepName.contains("osv") {
            return "security"
        }
        if ["node-toolchain", "tsc-noemit", "lint", "lint-check"].contains(stepName) {
            return "quality"
        }
        if stepName.hasSuffix("-build") || stepName == "node-build" {
            return "build"
        }
        if stepName.hasSuffix("-test")
            || ["pytest", "swift-test", "zig-test", "make-test"].contains(stepName)
            || command.contains("test") {
            return "test"
        }
        return "general"
    }

    private static func inferResult(stepName: String, command: String, exitCode: Int, explicit: String) -> String {
        if ["pass", "warn", "fail"].contains(explicit) {
            return explicit
        }
        if exitCode == 0 {
            return "pass"
        }

        let loweredName = stepName.lowercased()
        let loweredCommand = command.lowercased()
        if exitCode == 127 {
            return "warn"
        }
        if loweredName == "node-audit" || loweredName.contains("audit") {
            return "warn"
        }
        if loweredCommand.contains("missing-")
            || loweredCommand.contains("missing ")
            || loweredCommand.contains("tool missing") {
            return "warn"
        }
        return "fail"
    }

    private static func parseOSVSummary(outputLines: [String]) -> String? {
        let text = outputLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = payload["results"] as? [[String: Any]] else {
            return nil
        }

        var sourceCount = 0
        var packageCount = 0
        var vulnerabilityCount = 0
        var seenGroups = Set<String>()

        for result in results {
            sourceCount += 1
            for packageEntry in (result["packages"] as? [[String: Any]]) ?? [] {
                packageCount += 1
                let groups = (packageEntry["groups"] as? [[String: Any]]) ?? []
                if !groups.isEmpty {
                    for group in groups {
                        let ids = ((group["ids"] as? [String]) ?? []).sorted()
                        guard !ids.isEmpty else { continue }
                        if seenGroups.insert(ids.joined(separator: ",")).inserted {
                            vulnerabilityCount += 1
                        }
                    }
                    continue
                }

                let vulnerabilities = (packageEntry["vulnerabilities"] as? [[String: Any]]) ?? []
                vulnerabilityCount += vulnerabilities.count
            }
        }

        return "\(vulnerabilityCount) vulnerability group(s) across \(packageCount) package(s) from \(sourceCount) source(s)"
    }
}

#endif
