// YEN Overlay: command palette terminal dispatch and pasteboard insertion helpers.

import AppKit
import SwiftUI
import YENKit

extension TerminalCommandPaletteView {
    private struct PasteboardSnapshot {
        private enum Storage {
            case fullItems([NSPasteboardItem])
            case empty
        }

        private let storage: Storage

        static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
            guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
                return PasteboardSnapshot(storage: .empty)
            }

            var copiedItems: [NSPasteboardItem] = []
            copiedItems.reserveCapacity(items.count)

            for item in items {
                let copy = NSPasteboardItem()
                var copiedTypeCount = 0
                for type in item.types {
                    if let data = item.data(forType: type) {
                        copy.setData(data, forType: type)
                        copiedTypeCount += 1
                        continue
                    }

                    if let value = item.string(forType: type) {
                        copy.setString(value, forType: type)
                        copiedTypeCount += 1
                        continue
                    }

                    if let propertyList = item.propertyList(forType: type) {
                        copy.setPropertyList(propertyList, forType: type)
                        copiedTypeCount += 1
                    }
                }

                if copiedTypeCount > 0 {
                    copiedItems.append(copy)
                }
            }

            if copiedItems.isEmpty {
                return PasteboardSnapshot(storage: .empty)
            }

            return PasteboardSnapshot(storage: .fullItems(copiedItems))
        }

        func restore(to pasteboard: NSPasteboard) {
            switch storage {
            case .fullItems(let items):
                pasteboard.clearContents()
                if !items.isEmpty {
                    _ = pasteboard.writeObjects(items)
                }
            case .empty:
                pasteboard.clearContents()
            }
        }
    }


    func launchFileBrowser() {
        _ = TerminalSurfaceCommandLauncher.dispatch(
            command: TerminalSurfaceCommandLauncher.fileBrowserCommand,
            to: surfaceView
        )
    }

    func sendTerminalCommand(_ command: String) {
        _ = TerminalSurfaceCommandLauncher.dispatch(command: command, to: surfaceView)
    }

    func openSearchResultLocation(_ location: TerminalCommandPaletteLocation) {
        Task { _ = await IDEEditorNavigator.open(location) }
    }

    func insertHistoryCommand(_ command: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        // changeCount right after we wrote the command; only restore if nothing else
        // (a newer copy, or the paste path) claimed the pasteboard in the interim, so
        // the restore never clobbers the user's newer clipboard.
        let expectedChangeCount = pasteboard.changeCount
        surfaceView.paste(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard DictationClipboardRestorePolicy.shouldRestorePasteboard(
                currentChangeCount: pasteboard.changeCount,
                expectedChangeCount: expectedChangeCount
            ) else { return }
            snapshot.restore(to: pasteboard)
        }
    }
}
