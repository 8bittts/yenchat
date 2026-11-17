#if os(macOS)
import AppKit
import Foundation
import SwiftUI

enum PullRequestReviewAuditPaths {
    static func evidenceDirectory(ideStateDirectory: String) -> String {
        URL(fileURLWithPath: ideStateDirectory)
            .appendingPathComponent("evidence", isDirectory: true)
            .path
    }

    static func evidenceFilePath(ideStateDirectory: String, suggestedFileName: String) -> String {
        URL(fileURLWithPath: evidenceDirectory(ideStateDirectory: ideStateDirectory))
            .appendingPathComponent(suggestedFileName)
            .path
    }

    static func timelineFilePath(ideStateDirectory: String) -> String {
        URL(fileURLWithPath: ideStateDirectory)
            .appendingPathComponent("timeline.log")
            .path
    }
}

enum PullRequestReviewAuditWriter {
    static func ensureStateDirectories(ideStateDirectory: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            atPath: ideStateDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try fileManager.createDirectory(
            atPath: PullRequestReviewAuditPaths.evidenceDirectory(ideStateDirectory: ideStateDirectory),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    static func write(text: String, to path: String) throws {
        let fileManager = FileManager.default
        let parentDirectory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        try fileManager.createDirectory(
            atPath: parentDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }

    static func appendTimeline(
        event: String,
        projectRoot: String,
        status: String,
        detail: String,
        ideStateDirectory: String,
        now: Date = Date()
    ) throws {
        try ensureStateDirectories(ideStateDirectory: ideStateDirectory)
        try ReviewTimelineWriter.append(
            event: event,
            projectRoot: projectRoot,
            status: status,
            detail: detail,
            ideStateDirectory: ideStateDirectory,
            now: now
        )
    }
}

#endif
