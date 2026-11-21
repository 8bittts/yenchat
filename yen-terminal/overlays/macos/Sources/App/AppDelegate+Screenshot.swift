#if os(macOS)
import AppKit
import Darwin
import ScreenCaptureKit

struct ScreenshotPixelDimensions: Equatable, Sendable {
    let width: Int
    let height: Int
}

enum ScreenshotCaptureConfiguration {
    static func pixelDimensions(
        contentRect: CGRect,
        pointPixelScale: CGFloat
    ) -> ScreenshotPixelDimensions {
        let scale = pointPixelScale.isFinite && pointPixelScale > 0 ? pointPixelScale : 1

        func pixelLength(for pointLength: CGFloat) -> Int {
            guard pointLength.isFinite, pointLength > 0 else { return 1 }
            let pixelLength = (pointLength * scale).rounded()
            guard pixelLength.isFinite else { return 1 }
            guard pixelLength <= CGFloat(Int32.max) else { return Int(Int32.max) }
            return max(1, Int(pixelLength))
        }

        return ScreenshotPixelDimensions(
            width: pixelLength(for: contentRect.width),
            height: pixelLength(for: contentRect.height)
        )
    }

    @available(macOS 14.0, *)
    @discardableResult
    static func apply(
        to configuration: SCStreamConfiguration,
        contentRect: CGRect,
        pointPixelScale: CGFloat
    ) -> ScreenshotPixelDimensions {
        let dimensions = pixelDimensions(
            contentRect: contentRect,
            pointPixelScale: pointPixelScale
        )
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.scalesToFit = false
        configuration.preservesAspectRatio = true
        return dimensions
    }
}

@MainActor
protocol ScreenshotPasteboardWriting: AnyObject {
    @discardableResult
    func clearContents() -> Int
    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: ScreenshotPasteboardWriting {}

@MainActor
enum ScreenshotClipboardWriter {
    static func writePNG(
        _ data: Data,
        to pasteboard: any ScreenshotPasteboardWriting
    ) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }
}

enum ScreenshotOutputWriter {
    static func write(
        _ data: Data,
        to directory: URL,
        baseName: String,
        fileExtension: String
    ) throws -> URL {
        var counter = 1

        while true {
            let suffix = counter == 1 ? "" : " \(counter)"
            let candidate = directory.appendingPathComponent(
                "\(baseName)\(suffix).\(fileExtension)",
                isDirectory: false
            )
            let fileDescriptor = Darwin.open(
                candidate.path,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
                S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
            )

            if fileDescriptor >= 0 {
                let fileHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
                do {
                    try fileHandle.write(contentsOf: data)
                    try fileHandle.close()
                    return candidate
                } catch {
                    try? fileHandle.close()
                    _ = Darwin.unlink(candidate.path)
                    throw error
                }
            }

            let openError = errno
            guard openError == EEXIST else {
                throw POSIXError(POSIXErrorCode(rawValue: openError) ?? .EIO)
            }
            counter += 1
        }
    }
}

/// Extension to capture the terminal window as a screenshot.
/// Connected via MainMenu.xib overlay with Cmd + Shift + S shortcut.
///
/// Saves to the user's configured screenshot location with their naming
/// preferences (reads com.apple.screencapture defaults). Also copies PNG
/// to clipboard. Uses permission-free current-process ScreenCaptureKit on
/// macOS 14.4 and newer, with the legacy own-window Core Graphics capture API
/// retained for older supported releases and as a capture failure fallback.
extension AppDelegate {
    @IBAction func takeScreenshot(_ sender: Any?) {
        let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow

        guard let window = targetWindow else {
            postScreenshotStatus(
                targetWindow: nil,
                fileSaved: false,
                copiedToClipboard: false,
                filePath: nil,
                failureReason: "No active terminal window"
            )
            return
        }
        Task { @MainActor in
            await captureAndSaveScreenshot(of: window)
        }
    }

    @MainActor
    private func captureAndSaveScreenshot(of window: NSWindow) async {
        guard let image = await Self.captureImage(windowID: CGWindowID(window.windowNumber)) else {
            postScreenshotStatus(
                targetWindow: window,
                fileSaved: false,
                copiedToClipboard: false,
                filePath: nil,
                failureReason: "Unable to capture terminal window"
            )
            return
        }

        // Read macOS screenshot preferences (com.apple.screencapture domain)
        let prefs = UserDefaults(suiteName: "com.apple.screencapture")
        let saveDir = (prefs?.string(forKey: "location") as NSString?)?.expandingTildeInPath
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
        let namePrefix = prefs?.string(forKey: "name") ?? "Screenshot"
        let fileType = prefs?.string(forKey: "type") ?? "png"
        let includeDate = prefs?.object(forKey: "include-date") as? Bool ?? true

        // Generate filename matching macOS screenshot naming convention
        let baseName: String
        if includeDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss\u{202f}a"
            baseName = "\(namePrefix) \(formatter.string(from: Date()))"
        } else {
            baseName = namePrefix
        }

        let result = await Task.detached(priority: .utility) {
            Self.encodeAndSaveScreenshot(
                image: image,
                saveDirectory: saveDir,
                baseName: baseName,
                fileType: fileType
            )
        }.value

        // Always copy to clipboard as PNG (best compatibility)
        var copiedToClipboard = false
        var failureReason = result.failureReason
        if let pngData = result.pngData {
            copiedToClipboard = ScreenshotClipboardWriter.writePNG(
                pngData,
                to: NSPasteboard.general
            )
            if !copiedToClipboard, failureReason == nil {
                failureReason = "Unable to copy screenshot to clipboard"
            }
        } else if failureReason == nil {
            failureReason = "Unable to copy screenshot to clipboard"
        }

        postScreenshotStatus(
            targetWindow: window,
            fileSaved: result.fileSaved,
            copiedToClipboard: copiedToClipboard,
            filePath: result.filePath,
            failureReason: failureReason
        )
    }

    private struct ScreenshotWriteResult: @unchecked Sendable {
        let fileSaved: Bool
        let filePath: String?
        let pngData: Data?
        let failureReason: String?
    }

    private static func captureImage(windowID: CGWindowID) async -> CGImage? {
        if #available(macOS 14.4, *),
           let image = await captureCurrentProcessImage(windowID: windowID)
        {
            return image
        }

        return captureLegacyOwnWindowImage(windowID: windowID)
    }

    @available(macOS 14.4, *)
    static func captureCurrentProcessImage(windowID: CGWindowID) async -> CGImage? {
        do {
            let content = try await SCShareableContent.currentProcess
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let dimensions = ScreenshotCaptureConfiguration.apply(
                to: configuration,
                contentRect: filter.contentRect,
                pointPixelScale: CGFloat(filter.pointPixelScale)
            )
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            guard image.width == dimensions.width, image.height == dimensions.height else {
                return nil
            }
            return image
        } catch {
            return nil
        }
    }

    private static func captureLegacyOwnWindowImage(windowID: CGWindowID) -> CGImage? {
        return CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming]
        )
    }

    private static func encodeAndSaveScreenshot(
        image: CGImage,
        saveDirectory: String,
        baseName: String,
        fileType: String
    ) -> ScreenshotWriteResult {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let pngData = bitmap.representation(using: .png, properties: [:])
        let (bitmapType, ext) = screenshotBitmapFormat(for: fileType)
        // The default screenshot format is PNG and pngData (for the clipboard copy)
        // is already the PNG encoding of the same bitmap, so reuse it instead of
        // encoding a second identical multi-megapixel PNG buffer on the common path.
        let encodedFileData = bitmapType == .png
            ? pngData
            : bitmap.representation(
                using: bitmapType,
                properties: bitmapType == .jpeg ? [.compressionFactor: 0.9] : [:]
            )
        guard let fileData = encodedFileData else {
            return ScreenshotWriteResult(
                fileSaved: false,
                filePath: nil,
                pngData: pngData,
                failureReason: "Unable to encode screenshot image"
            )
        }

        do {
            try FileManager.default.createDirectory(
                atPath: saveDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return ScreenshotWriteResult(
                fileSaved: false,
                filePath: nil,
                pngData: pngData,
                failureReason: "Unable to create screenshot directory"
            )
        }

        do {
            let fileURL = try ScreenshotOutputWriter.write(
                fileData,
                to: URL(fileURLWithPath: saveDirectory, isDirectory: true),
                baseName: baseName,
                fileExtension: ext
            )
            return ScreenshotWriteResult(
                fileSaved: true,
                filePath: fileURL.path,
                pngData: pngData,
                failureReason: nil
            )
        } catch {
            return ScreenshotWriteResult(
                fileSaved: false,
                filePath: nil,
                pngData: pngData,
                failureReason: "Unable to save screenshot file"
            )
        }
    }

    private static func screenshotBitmapFormat(for type: String) -> (NSBitmapImageRep.FileType, String) {
        switch type.lowercased() {
        case "jpg", "jpeg": return (.jpeg, "jpg")
        case "tiff", "tif": return (.tiff, "tiff")
        case "gif": return (.gif, "gif")
        case "bmp": return (.bmp, "bmp")
        default: return (.png, "png")
        }
    }

    private func postScreenshotStatus(
        targetWindow: NSWindow?,
        fileSaved: Bool,
        copiedToClipboard: Bool,
        filePath: String?,
        failureReason: String?
    ) {
        let outcome = ScreenshotToastOutcome.resolve(
            fileSaved: fileSaved,
            copiedToClipboard: copiedToClipboard
        )
        let message = Self.screenshotToastMessage(
            fileSaved: fileSaved,
            copiedToClipboard: copiedToClipboard,
            filePath: filePath,
            failureReason: failureReason
        )
        var userInfo: [AnyHashable: Any] = [
            Notification.Name.yenScreenshotToastMessageKey: message,
            Notification.Name.yenScreenshotOutcomeKey: outcome.rawValue,
            Notification.Name.yenScreenshotSavedKey: fileSaved,
            Notification.Name.yenScreenshotClipboardCopiedKey: copiedToClipboard,
        ]
        if let targetWindow {
            userInfo[Notification.Name.yenScreenshotWindowNumberKey] = targetWindow.windowNumber
        }
        if let filePath, !filePath.isEmpty {
            let fileName = (filePath as NSString).lastPathComponent
            if !fileName.isEmpty {
                userInfo[Notification.Name.yenScreenshotFilenameKey] = fileName
            }
        }
        NotificationCenter.default.post(name: .yenScreenshotCopied, object: targetWindow, userInfo: userInfo)
    }

    static func screenshotToastMessage(
        fileSaved: Bool,
        copiedToClipboard: Bool,
        filePath: String?,
        failureReason: String?
    ) -> String {
        let fileName = filePath.map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }

        if fileSaved && copiedToClipboard {
            if let fileName {
                return "Saved \(fileName) and copied to clipboard"
            }
            return "Screenshot saved and copied to clipboard"
        }

        if fileSaved {
            if let fileName {
                return "Saved \(fileName)"
            }
            return "Screenshot saved"
        }

        if copiedToClipboard {
            if let fileName {
                return "Copied to clipboard (save failed: \(fileName))"
            }
            return "Copied screenshot to clipboard (save failed)"
        }

        if let failureReason = failureReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !failureReason.isEmpty
        {
            return "Screenshot failed: \(failureReason)"
        }
        return "Screenshot failed"
    }
}
#endif
