#if os(macOS)
import Darwin
import Foundation

/// Shared working-directory normalization for the Review workspaces (merge-conflict + PR review).
/// Expands `~`, requires the path to exist on disk, and standardizes it. Carries no per-site
/// difference, so both workspaces call it instead of keeping byte-identical local copies.
enum ReviewWorkingDirectory {
    static func normalized(for workingDirectory: String?) -> String? {
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        let expanded = NSString(string: workingDirectory).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
}

struct ReviewCommandOutput: Sendable {
    let stdout: String
}

enum ReviewIDEStateDirectory {
    static var defaultPath: String {
        resolved()
    }

    static func resolved(override: String? = nil) -> String {
        let environment = ProcessInfo.processInfo.environment
        let path = override ?? environment["YEN_IDE_STATE_DIR"] ?? "~/.config/yen/ide"
        return NSString(string: path).expandingTildeInPath
    }
}

enum ReviewWorkspaceTimestamps {
    private static let isoDisplayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let compactFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()

    static func isoNow(date: Date = Date()) -> String {
        isoDisplayFormatter.string(from: date)
    }

    static func compactTimestamp(date: Date = Date()) -> String {
        compactFormatter.string(from: date)
    }
}

enum ReviewTimelineWriter {
    static func append(
        event: String,
        projectRoot: String,
        status: String,
        detail: String,
        ideStateDirectory: String,
        now: Date = Date()
    ) throws {
        try FileManager.default.createDirectory(
            atPath: ideStateDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let sanitizedDetail = detail.replacingOccurrences(
            of: "[\t\r\n]+",
            with: " ",
            options: .regularExpression
        )
        let line = [
            ReviewWorkspaceTimestamps.isoNow(date: now),
            event,
            projectRoot,
            status,
            sanitizedDetail,
        ].joined(separator: "\t") + "\n"
        let timelinePath = URL(fileURLWithPath: ideStateDirectory)
            .appendingPathComponent("timeline.log")
            .path

        let descriptor = Darwin.open(
            timelinePath,
            O_WRONLY | O_CREAT | O_APPEND,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }

        let bytes = Data(line.utf8)
        let written = try bytes.withUnsafeBytes { buffer -> Int in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            let result = Darwin.write(descriptor, baseAddress, buffer.count)
            guard result >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return result
        }
        guard written == bytes.count else {
            throw POSIXError(.EIO)
        }
    }
}
#endif
