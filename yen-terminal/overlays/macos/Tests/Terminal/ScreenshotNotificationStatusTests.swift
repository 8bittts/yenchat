import AppKit
import Foundation
import ScreenCaptureKit
import Testing
@testable import YEN

@MainActor
private final class ScreenshotPasteboardStub: ScreenshotPasteboardWriting {
    let acceptsData: Bool
    private(set) var clearCount = 0
    private(set) var writtenData: Data?
    private(set) var writtenType: NSPasteboard.PasteboardType?

    init(acceptsData: Bool) {
        self.acceptsData = acceptsData
    }

    @discardableResult
    func clearContents() -> Int {
        clearCount += 1
        return clearCount
    }

    func setData(_ data: Data?, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        writtenData = data
        writtenType = dataType
        return acceptsData
    }
}

struct ScreenshotNotificationStatusTests {
    @available(macOS 14.4, *)
    @Test @MainActor func capturesAnActualWindowOfTheCurrentProcess() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 240, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.close() }

        let image = try #require(await AppDelegate.captureCurrentProcessImage(windowID: CGWindowID(window.windowNumber)))
        #expect(image.width >= 240)
        #expect(image.height >= 160)
    }

    @Test func sharedToastRoutingPreservesWindowAndMessagePolicies() {
        for (windowKey, messageKey) in [
            (Notification.Name.yenHotkeyDisabledWindowNumberKey, Notification.Name.yenHotkeyDisabledMessageKey),
            (Notification.Name.yenLayoutStatusWindowNumberKey, Notification.Name.yenLayoutStatusMessageKey),
            (Notification.Name.yenScreenshotWindowNumberKey, Notification.Name.yenScreenshotToastMessageKey),
        ] {
            let notification = Notification(name: .yenScreenshotCopied, userInfo: [
                windowKey: NSNumber(value: 17), messageKey: "  Message\n",
            ])
            #expect(TerminalToastPayload.message(from: notification, observedWindowNumbers: [17],
                windowNumberKey: windowKey, messageKey: messageKey) == "Message")
            #expect(TerminalToastPayload.message(from: notification, observedWindowNumbers: [18],
                windowNumberKey: windowKey, messageKey: messageKey) == nil)
            #expect(TerminalToastPayload.message(from: notification, observedWindowNumbers: [],
                windowNumberKey: windowKey, messageKey: messageKey) == nil)
            let blank = Notification(name: .yenScreenshotCopied, userInfo: [windowKey: 17, messageKey: " "])
            #expect(TerminalToastPayload.message(from: blank, observedWindowNumbers: [17],
                windowNumberKey: windowKey, messageKey: messageKey) == nil)
            let malformed = Notification(name: .yenScreenshotCopied, userInfo: [
                windowKey: NSNumber(value: 17.5), messageKey: "Message",
            ])
            #expect(TerminalToastPayload.message(from: malformed, observedWindowNumbers: [17],
                windowNumberKey: windowKey, messageKey: messageKey) == nil)
        }
    }

    @MainActor
    @Test func onlyScreenshotRoutingAllowsWindowObjectAndDefaultMessage() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let notification = Notification(name: .yenScreenshotCopied, object: window)
        #expect(ScreenshotToastEvent.from(notification: notification, observedWindowNumbers: [window.windowNumber])?.message == "Screenshot saved")
        #expect(TerminalToastPayload.message(from: notification, observedWindowNumbers: [window.windowNumber],
            windowNumberKey: Notification.Name.yenHotkeyDisabledWindowNumberKey,
            messageKey: Notification.Name.yenHotkeyDisabledMessageKey) == nil)
    }

    @Test func screenshotCaptureConfigurationUsesExactNativePixelDimensions() {
        if #available(macOS 14.0, *) {
            let configuration = SCStreamConfiguration()
            let dimensions = ScreenshotCaptureConfiguration.apply(
                to: configuration,
                contentRect: CGRect(x: 40, y: 20, width: 640.5, height: 480.25),
                pointPixelScale: 2
            )

            #expect(dimensions == ScreenshotPixelDimensions(width: 1_281, height: 961))
            #expect(configuration.width == 1_281)
            #expect(configuration.height == 961)
            #expect(configuration.captureResolution == .best)
            #expect(configuration.showsCursor == false)
            #expect(configuration.ignoreShadowsSingleWindow)
            #expect(configuration.ignoreGlobalClipSingleWindow)
            #expect(configuration.scalesToFit == false)
            #expect(configuration.preservesAspectRatio)
        }
    }

    @Test func screenshotPixelDimensionsClampInvalidGeometry() {
        let dimensions = ScreenshotCaptureConfiguration.pixelDimensions(
            contentRect: CGRect(x: 0, y: 0, width: 0, height: CGFloat.infinity),
            pointPixelScale: CGFloat.nan
        )

        #expect(dimensions == ScreenshotPixelDimensions(width: 1, height: 1))
    }

    @Test func screenshotOutputWriterAllocatesConcurrentCapturesWithoutOverwrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "yen-screenshot-writer-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let existingURL = directory.appendingPathComponent("Screenshot.png")
        let existingData = Data("existing".utf8)
        try existingData.write(to: existingURL)
        let captureCount = 8

        let captures = try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for index in 0..<captureCount {
                group.addTask {
                    let data = Data("capture-\(index)".utf8)
                    let fileURL = try ScreenshotOutputWriter.write(
                        data,
                        to: directory,
                        baseName: "Screenshot",
                        fileExtension: "png"
                    )
                    return (index, fileURL)
                }
            }

            var results: [(Int, URL)] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        #expect(captures.count == captureCount)
        #expect(Set(captures.map(\.1)).count == captureCount)
        #expect(try Data(contentsOf: existingURL) == existingData)
        for (index, fileURL) in captures {
            #expect(try Data(contentsOf: fileURL) == Data("capture-\(index)".utf8))
        }
    }

    @Test @MainActor func screenshotClipboardWriterReportsPasteboardRejection() {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let pasteboard = ScreenshotPasteboardStub(acceptsData: false)

        let copied = ScreenshotClipboardWriter.writePNG(data, to: pasteboard)

        #expect(copied == false)
        #expect(pasteboard.clearCount == 1)
        #expect(pasteboard.writtenData == data)
        #expect(pasteboard.writtenType == .png)
    }

    @Test func screenshotOutcomeResolutionCoversAllPresentationStates() {
        #expect(ScreenshotToastOutcome.resolve(fileSaved: true, copiedToClipboard: true) == .savedAndCopied)
        #expect(ScreenshotToastOutcome.resolve(fileSaved: true, copiedToClipboard: false) == .saved)
        #expect(ScreenshotToastOutcome.resolve(fileSaved: false, copiedToClipboard: true) == .copiedOnly)
        #expect(ScreenshotToastOutcome.resolve(fileSaved: false, copiedToClipboard: false) == .failure)
    }

    @Test func screenshotStatusMessageSavedAndCopiedIncludesFileName() {
        let message = AppDelegate.screenshotToastMessage(
            fileSaved: true,
            copiedToClipboard: true,
            filePath: "/Users/me/Desktop/Screenshot 2026-03-01 at 7.45.00 PM.png",
            failureReason: nil
        )

        #expect(message == "Saved Screenshot 2026-03-01 at 7.45.00 PM.png and copied to clipboard")
    }

    @Test func screenshotStatusMessageCopiedOnlyMentionsSaveFailure() {
        let message = AppDelegate.screenshotToastMessage(
            fileSaved: false,
            copiedToClipboard: true,
            filePath: "/Users/me/Desktop/Screenshot.png",
            failureReason: "Unable to save screenshot file"
        )

        #expect(message == "Copied to clipboard (save failed: Screenshot.png)")
    }

    @Test func screenshotStatusMessageFailureIncludesReason() {
        let message = AppDelegate.screenshotToastMessage(
            fileSaved: false,
            copiedToClipboard: false,
            filePath: nil,
            failureReason: "No active terminal window"
        )

        #expect(message == "Screenshot failed: No active terminal window")
    }

    @Test func screenshotToastEventOnlyRoutesToTargetWindow() {
        let notification = Notification(
            name: .yenScreenshotCopied,
            object: nil,
            userInfo: [
                Notification.Name.yenScreenshotToastMessageKey: "Saved Screenshot.png",
                Notification.Name.yenScreenshotOutcomeKey: ScreenshotToastOutcome.saved.rawValue,
                Notification.Name.yenScreenshotWindowNumberKey: 17,
            ]
        )

        let shown = ScreenshotToastEvent.from(notification: notification, observedWindowNumbers: [17])
        let hidden = ScreenshotToastEvent.from(notification: notification, observedWindowNumbers: [18])

        #expect(shown == ScreenshotToastEvent(message: "Saved Screenshot.png", outcome: .saved))
        #expect(hidden == nil)
    }

    @Test func screenshotToastEventFallsBackToSavedAndClipboardFlags() {
        let notification = Notification(
            name: .yenScreenshotCopied,
            object: nil,
            userInfo: [
                Notification.Name.yenScreenshotToastMessageKey: "Copied screenshot to clipboard (save failed)",
                Notification.Name.yenScreenshotSavedKey: false,
                Notification.Name.yenScreenshotClipboardCopiedKey: true,
                Notification.Name.yenScreenshotWindowNumberKey: 7,
            ]
        )

        let event = ScreenshotToastEvent.from(notification: notification, observedWindowNumbers: [7])
        #expect(event == ScreenshotToastEvent(
            message: "Copied screenshot to clipboard (save failed)",
            outcome: .copiedOnly
        ))
    }

    @Test func screenshotToastEventUsesFallbackForWhitespaceOnlyMessage() {
        let notification = Notification(
            name: .yenScreenshotCopied,
            object: nil,
            userInfo: [
                Notification.Name.yenScreenshotToastMessageKey: "   \n\t  ",
                Notification.Name.yenScreenshotOutcomeKey: ScreenshotToastOutcome.saved.rawValue,
                Notification.Name.yenScreenshotWindowNumberKey: 9,
            ]
        )

        let event = ScreenshotToastEvent.from(notification: notification, observedWindowNumbers: [9])
        #expect(event == ScreenshotToastEvent(message: "Screenshot saved", outcome: .saved))
    }
}
