import AppKit
import CoreVideo
import ImageIO
import IOSurface

/// AppKit view that renders animated GIF frames into a `CALayer`.
///
/// Frames are decoded into IOSurfaces on a background task, so presenting one
/// on the main thread only hands Core Animation a surface. In a terminal the
/// main thread handles typing, and `CGAnimateImageAtURLWithBlock` decodes
/// there: a 1080p GIF held it for 11 to 13 ms per frame.
@MainActor
final class GIFWallpaperView: NSView, WallpaperContentView {
    private var imageLayer: CALayer?
    /// The GIF currently loaded, so a resume can restart it.
    private var currentURL: URL?
    /// Decodes and times the frames. Canceling it stops the animation.
    private var animation: Task<Void, Never>?
    var onFailure: ((URL, String) -> Void)?

    var isPlaybackPaused = false {
        didSet {
            guard isPlaybackPaused != oldValue else { return }
            if isPlaybackPaused {
                // Keep the last frame up so a pause does not flash the desktop
                // through an empty layer.
                animation?.cancel()
            } else if let currentURL {
                // A resumed GIF restarts from the first frame; the last frame
                // stays visible until then.
                loadGIF(url: currentURL)
            }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let layer = CALayer()
        layer.contentsGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.layer?.addSublayer(layer)
        self.imageLayer = layer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
    }

    /// A layer the view creates itself does not follow the backing scale, so
    /// update it when the window moves to a display with a different scale.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    private func updateContentsScale() {
        imageLayer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer?.frame = bounds
        CATransaction.commit()
    }

    /// Loop the GIF, or show only its first frame while playback is paused.
    /// Wallpaper GIFs loop even when the file's own loop count is 1.
    func loadGIF(url: URL) {
        currentURL = url
        animation?.cancel()
        let firstFrameOnly = isPlaybackPaused
        animation = Task.detached(priority: .utility) { [weak self] in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                await self?.fail(url)
                return
            }
            let frameCount = CGImageSourceGetCount(source)
            let clock = ContinuousClock()
            var nextFrame = clock.now
            var index = 0
            while !Task.isCancelled {
                // ImageIO's decode buffers are autoreleased; free them per frame.
                let surface = autoreleasepool {
                    CGImageSourceCreateImageAtIndex(source, index, nil).flatMap(Self.surface(drawing:))
                }
                guard let surface else {
                    await self?.fail(url)
                    return
                }
                guard await self?.present(surface) == true, !firstFrameOnly, frameCount > 1 else { return }
                // Time frames from a running deadline so decode time does not
                // slow the animation; start over after falling behind.
                nextFrame = max(nextFrame + .seconds(Self.frameDelay(of: source, at: index)), clock.now)
                try? await clock.sleep(until: nextFrame)
                index = (index + 1) % frameCount
            }
        }
    }

    /// The frame drawn into a new IOSurface. An ImageIO image decodes lazily,
    /// when Core Animation commits it on the main thread, and a bitmap image is
    /// still copied and color-matched there; a surface is neither.
    private nonisolated static func surface(drawing frame: CGImage) -> IOSurface? {
        let space = frame.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
        guard let surface = IOSurface(properties: [
            .width: frame.width,
            .height: frame.height,
            .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32BGRA,
        ]) else { return nil }
        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }
        guard let context = CGContext(
            data: surface.baseAddress,
            width: frame.width,
            height: frame.height,
            bitsPerComponent: 8,
            bytesPerRow: surface.bytesPerRow,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.setBlendMode(.copy)
        context.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        if let tag = space.copyPropertyList() {
            surface.setAttachment(tag, forKey: kIOSurfaceColorSpace as String)
        }
        return surface
    }

    /// The frame's delay in seconds. Like browsers, a delay too short to be
    /// intended plays at 10 frames per second.
    private nonisolated static func frameDelay(of source: CGImageSource, at index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] ?? gif?[kCGImagePropertyGIFDelayTime]) as? Double
        guard let delay, delay >= 0.011 else { return 0.1 }
        return delay
    }

    /// Show a decoded frame. Returns false once this animation was canceled,
    /// so a frame decoded for an old GIF never replaces the new one.
    private func present(_ surface: IOSurface) -> Bool {
        guard !Task.isCancelled else { return false }
        // No implicit CALayer fade between frames (it looks like tearing).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer?.contents = surface
        CATransaction.commit()
        return true
    }

    private func fail(_ url: URL) {
        guard !Task.isCancelled else { return }
        currentURL = nil
        onFailure?(url, "The GIF couldn't be played.")
    }

    override func removeFromSuperview() {
        animation?.cancel()
        super.removeFromSuperview()
    }
}
