#if os(macOS)
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BackgroundImageImportError: LocalizedError, Equatable {
    case symlinkNotAllowed
    case unsupportedFileType
    case fileTooLarge(maxBytes: UInt64)
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .symlinkNotAllowed:
            return "Choose an image file instead of a symlink."
        case .unsupportedFileType:
            return "Choose a PNG or JPEG image."
        case .fileTooLarge(let maxBytes):
            let maxMegabytes = Int(maxBytes / 1_048_576)
            return "Choose an image under \(maxMegabytes) MB."
        case .unreadableImage:
            return "YEN couldn't decode that image. Try a PNG or JPEG file."
        }
    }
}

enum TerminalBackgroundImageStore {
    static let maximumFileSizeBytes: UInt64 = 32 * 1_048_576
    static let supportedContentTypes: [UTType] = [.png, .jpeg]

    private static let managedFilenamePrefix = "terminal-background-"
    private static let backgroundsDirectoryName = "backgrounds"

    static func normalizedConfigPath(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let unquoted: String
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
            || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            unquoted = String(trimmed.dropFirst().dropLast())
        } else {
            unquoted = trimmed
        }

        let unescaped = unquoted
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        return (unescaped as NSString).expandingTildeInPath
    }

    static func quotedConfigPath(_ path: String) -> String {
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func previewImage(for path: String) -> NSImage? {
        let normalizedPath = normalizedConfigPath(path)
        guard !normalizedPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: normalizedPath)
        guard let image = NSImage(contentsOf: url), image.isValid else { return nil }
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return image
    }

    static func isSupportedRenderableImage(at path: String) -> Bool {
        let normalizedPath = normalizedConfigPath(path)
        guard !normalizedPath.isEmpty else { return false }
        guard let detectedContentType = detectedRenderableContentType(
            for: URL(fileURLWithPath: normalizedPath)
        ) else {
            return false
        }
        return isSupportedRenderableContentType(detectedContentType)
    }

    static func displayName(for path: String) -> String {
        let normalizedPath = normalizedConfigPath(path)
        guard !normalizedPath.isEmpty else { return "" }
        return URL(fileURLWithPath: normalizedPath).lastPathComponent
    }

    static func appSupportRootURL(fileManager: FileManager = .default) -> URL {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        return homeURL.appendingPathComponent(
            "Library/Application Support/com.yenchat.yen",
            isDirectory: true
        )
    }

    static func backgroundsDirectoryURL(
        fileManager: FileManager = .default,
        appSupportRootOverride: URL? = nil
    ) -> URL {
        (appSupportRootOverride ?? appSupportRootURL(fileManager: fileManager))
            .appendingPathComponent(backgroundsDirectoryName, isDirectory: true)
    }

    static func isManagedBackgroundImagePath(
        _ path: String,
        fileManager: FileManager = .default,
        appSupportRootOverride: URL? = nil
    ) -> Bool {
        let normalizedPath = normalizedConfigPath(path)
        guard !normalizedPath.isEmpty else { return false }

        let candidateURL = URL(fileURLWithPath: normalizedPath).standardizedFileURL
        let directoryURL = backgroundsDirectoryURL(
            fileManager: fileManager,
            appSupportRootOverride: appSupportRootOverride
        ).standardizedFileURL

        guard candidateURL.deletingLastPathComponent() == directoryURL else { return false }
        return candidateURL.lastPathComponent.hasPrefix(managedFilenamePrefix)
    }

    static func importImage(
        from sourceURL: URL,
        fileManager: FileManager = .default,
        appSupportRootOverride: URL? = nil
    ) throws -> URL {
        let normalizedSourceURL = sourceURL.standardizedFileURL
        let resourceValues = try normalizedSourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey]
        )

        if resourceValues.isSymbolicLink == true {
            throw BackgroundImageImportError.symlinkNotAllowed
        }
        if resourceValues.isRegularFile == false {
            throw BackgroundImageImportError.unsupportedFileType
        }
        if let contentType = resourceValues.contentType, !contentType.conforms(to: .image) {
            throw BackgroundImageImportError.unsupportedFileType
        }

        let attributes = try fileManager.attributesOfItem(atPath: normalizedSourceURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        if fileSize > maximumFileSizeBytes {
            throw BackgroundImageImportError.fileTooLarge(maxBytes: maximumFileSizeBytes)
        }

        guard let detectedContentType = detectedRenderableContentType(for: normalizedSourceURL) else {
            throw BackgroundImageImportError.unreadableImage
        }
        guard isSupportedRenderableContentType(detectedContentType) else {
            throw BackgroundImageImportError.unsupportedFileType
        }
        guard previewImage(for: normalizedSourceURL.path) != nil else {
            throw BackgroundImageImportError.unreadableImage
        }

        if isManagedBackgroundImagePath(
            normalizedSourceURL.path,
            fileManager: fileManager,
            appSupportRootOverride: appSupportRootOverride
        ) {
            return normalizedSourceURL
        }

        let directoryURL = backgroundsDirectoryURL(
            fileManager: fileManager,
            appSupportRootOverride: appSupportRootOverride
        )
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let filenameExtension = preferredImportedExtension(
            sourceURL: normalizedSourceURL,
            contentType: detectedContentType
        )
        let suffix = UUID().uuidString.lowercased()
        let filename = filenameExtension.isEmpty
            ? "\(managedFilenamePrefix)\(suffix)"
            : "\(managedFilenamePrefix)\(suffix).\(filenameExtension)"
        let destinationURL = directoryURL.appendingPathComponent(filename, isDirectory: false)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: normalizedSourceURL, to: destinationURL)

        // Anything that throws AFTER the copy must take the file with it. `copyItem`
        // cleans up its own partial destination, but `setAttributes` does not — a
        // failure there used to strand `terminal-background-<uuid>[.ext]` in
        // Application Support forever, and strand it with default permissions rather
        // than the 0o600 this import requires. The caller only sees "Import failed",
        // so nothing downstream knows the file exists.
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destinationURL.path
            )
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
        return destinationURL
    }

    static func cleanupManagedImages(
        fileManager: FileManager = .default,
        appSupportRootOverride: URL? = nil,
        retaining retainedPaths: Set<String> = []
    ) throws {
        let directoryURL = backgroundsDirectoryURL(
            fileManager: fileManager,
            appSupportRootOverride: appSupportRootOverride
        )
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }

        let retainedNormalizedPaths = Set(retainedPaths.map {
            URL(fileURLWithPath: normalizedConfigPath($0)).standardizedFileURL.path
        })
        let entries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        for entryURL in entries {
            let standardizedURL = entryURL.standardizedFileURL
            guard standardizedURL.lastPathComponent.hasPrefix(managedFilenamePrefix) else { continue }

            let resourceValues = try standardizedURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            guard !retainedNormalizedPaths.contains(standardizedURL.path) else { continue }

            try fileManager.removeItem(at: standardizedURL)
        }
    }

    private static func detectedRenderableContentType(for sourceURL: URL) -> UTType? {
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let typeIdentifier = CGImageSourceGetType(imageSource) as String? else {
            return nil
        }
        return UTType(typeIdentifier)
    }

    private static func isSupportedRenderableContentType(_ contentType: UTType) -> Bool {
        supportedContentTypes.contains { contentType.conforms(to: $0) }
    }

    private static func preferredImportedExtension(
        sourceURL: URL,
        contentType: UTType?
    ) -> String {
        if let preferred = contentType?.preferredFilenameExtension,
           !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preferred.lowercased()
        }

        let pathExtension = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pathExtension.isEmpty {
            return pathExtension.lowercased()
        }

        return ""
    }
}
#endif
