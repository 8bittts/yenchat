import AppKit
import ImageIO
import SwiftUI
import YENKit
import os

struct WholeWindowBackgroundView: View {
    let imagePath: String
    let backgroundColor: Color
    let backgroundOpacity: Double

    @State private var image: NSImage?
    @State private var retryTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(backgroundColor)

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .opacity(backgroundOpacity)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { loadImage() }
        .onChange(of: imagePath) { _ in
            // Path changed — always load the new image.
            loadImage()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
            retryTask?.cancel()
            retryTask = nil
        }
    }

    private func loadImage() {
        loadTask?.cancel()
        loadTask = nil
        retryTask?.cancel()
        retryTask = nil

        let normalizedPath = TerminalBackgroundImageStore.normalizedConfigPath(imagePath)
        guard !normalizedPath.isEmpty else {
            image = nil
            return
        }

        let pathSnapshot = normalizedPath
        loadTask = Task { @MainActor in
            let fileURL = URL(fileURLWithPath: pathSnapshot)
            if let loaded = await TerminalBackgroundImageLoader.shared.image(at: fileURL) {
                guard !Task.isCancelled, imagePathMatches(pathSnapshot) else { return }
                image = loaded
                return
            }

            guard FileManager.default.isUbiquitousItem(at: fileURL) ||
                  FileManager.default.fileExists(atPath: pathSnapshot) else {
                image = nil
                return
            }

            try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            scheduleUbiquitousRetry(pathSnapshot: pathSnapshot)
        }
    }

    @MainActor
    private func scheduleUbiquitousRetry(pathSnapshot: String) {
        retryTask = Task { @MainActor in
            for seconds: UInt64 in [1, 2, 4, 8] {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                let retryURL = URL(fileURLWithPath: pathSnapshot)
                if let loaded = await TerminalBackgroundImageLoader.shared.image(at: retryURL) {
                    guard !Task.isCancelled, imagePathMatches(pathSnapshot) else { return }
                    image = loaded
                    return
                }
            }
        }
    }

    @MainActor
    private func imagePathMatches(_ path: String) -> Bool {
        TerminalBackgroundImageStore.normalizedConfigPath(imagePath) == path
    }
}
