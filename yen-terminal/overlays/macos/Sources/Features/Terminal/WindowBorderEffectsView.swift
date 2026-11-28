import AppKit
import QuartzCore
import SwiftUI

/// The stroke an effect follows: the same shape `WindowBorderOverlay` strokes.
struct WindowBorderEffectGeometry: Equatable {
    let cornerRadius: CGFloat
    let inset: CGFloat
    let lineWidth: CGFloat

    func path(in bounds: CGRect) -> CGPath {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .inset(by: inset)
            .path(in: bounds)
            .cgPath
    }
}

/// The light that travels around the outline.
struct WindowBorderSparkView: NSViewRepresentable {
    let geometry: WindowBorderEffectGeometry
    let color: NSColor
    let speed: WindowBorderSparkSpeed

    func makeNSView(context: Context) -> WindowBorderSparkLayerView {
        WindowBorderSparkLayerView()
    }

    func updateNSView(_ view: WindowBorderSparkLayerView, context: Context) {
        view.configure(geometry: geometry, color: color, speed: speed)
    }
}

/// The glow around the outline.
struct WindowBorderAuraView: NSViewRepresentable {
    let geometry: WindowBorderEffectGeometry
    let color: NSColor
    /// The speed of the pulse, or nil to hold the glow still.
    let pulse: WindowBorderAuraPulse?

    func makeNSView(context: Context) -> WindowBorderAuraLayerView {
        WindowBorderAuraLayerView()
    }

    func updateNSView(_ view: WindowBorderAuraLayerView, context: Context) {
        view.configure(geometry: geometry, color: color, pulse: pulse)
    }
}

/// Publishes Low Power Mode, so decorative motion can stop while it is on.
@MainActor
final class LowPowerModeMonitor: ObservableObject {
    static let shared = LowPowerModeMonitor()

    @Published private(set) var isLowPowerModeEnabled: Bool

    private let readState: () -> Bool

    init(
        readState: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        center: NotificationCenter = .default
    ) {
        self.readState = readState
        isLowPowerModeEnabled = readState()
        // The observer holds the monitor weakly and lives as long as the center.
        _ = center.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let enabled = self.readState()
                if enabled != self.isLowPowerModeEnabled {
                    self.isLowPowerModeEnabled = enabled
                }
            }
        }
    }
}

/// A layer host that never takes a click.
///
/// Both effects run as Core Animation animations in the render server, so a
/// moving outline costs the app no per-frame work.
class WindowBorderEffectLayerView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        clipsToBounds = false
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        refresh()
    }

    // A layer drops its animations when its view leaves a window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refresh()
    }

    /// Bring the layers in line with the current bounds and configuration.
    func refresh() {}

    /// A color as eight-bit sRGB, so two colors that draw alike compare equal
    /// whatever color space each one came in.
    static func colorKey(_ color: NSColor) -> [Int] {
        guard let rgb = color.usingColorSpace(.sRGB) else { return [] }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
            .map { Int(($0 * 255).rounded()) }
    }

    static func withoutImplicitAnimations(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}

final class WindowBorderSparkLayerView: WindowBorderEffectLayerView {
    private struct Signature: Equatable {
        let size: CGSize
        let geometry: WindowBorderEffectGeometry
        let speed: WindowBorderSparkSpeed
    }

    private static let travelKey = "yen.windowBorder.spark.travel"

    private let trail = CAReplicatorLayer()
    private let segment = CALayer()
    private let headGlow = CAGradientLayer()
    private var geometry: WindowBorderEffectGeometry?
    private var appliedColor: [Int]?
    private var speed = WindowBorderSparkSpeed.medium
    private var applied: Signature?
    /// When the current lap started, in `CACurrentMediaTime` seconds.
    private var lapStart: CFTimeInterval?
    private var lapDuration: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        headGlow.type = .radial
        headGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
        headGlow.endPoint = CGPoint(x: 1, y: 1)
        trail.addSublayer(segment)
        layer?.addSublayer(headGlow)
        layer?.addSublayer(trail)
    }

    func configure(geometry: WindowBorderEffectGeometry, color: NSColor, speed: WindowBorderSparkSpeed) {
        self.geometry = geometry
        self.speed = speed
        let colorKey = Self.colorKey(color)
        if appliedColor != colorKey {
            appliedColor = colorKey
            Self.withoutImplicitAnimations {
                segment.backgroundColor = color.cgColor
                headGlow.colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor]
            }
        }
        refresh()
    }

    var isTraveling: Bool {
        segment.animation(forKey: Self.travelKey) != nil
    }

    var segmentCountForTesting: Int { trail.instanceCount }
    var segmentSizeForTesting: CGSize { segment.bounds.size }
    var lapDurationForTesting: Double { lapDuration }
    /// How many times the travel animation was built. An update that changes
    /// nothing must not build it again.
    private(set) var travelBuildCount = 0

    override func refresh() {
        guard let geometry, window != nil, bounds.width > 1, bounds.height > 1 else {
            stop()
            return
        }
        let signature = Signature(size: bounds.size, geometry: geometry, speed: speed)
        if signature == applied, isTraveling { return }
        travelBuildCount += 1

        let outline = geometry.path(in: bounds)
        let metrics = WindowBorderRenderingPolicy.pathMetrics(of: outline)
        let path = clockwisePath(outline, signedArea: metrics.signedArea)
        guard let model = WindowBorderRenderingPolicy.sparkModel(
            perimeter: metrics.perimeter,
            lineWidth: geometry.lineWidth,
            speed: speed
        ) else {
            stop()
            return
        }

        // Keep the head where it is on the outline when the outline changes,
        // so a resize does not send it back to the start.
        let now = CACurrentMediaTime()
        var progress = 0.0
        if let lapStart, lapDuration > 0 {
            progress = (now - lapStart).truncatingRemainder(dividingBy: lapDuration) / lapDuration
        }
        let newLapStart = now - progress * model.lapDuration
        lapStart = newLapStart
        lapDuration = model.lapDuration
        applied = signature

        Self.withoutImplicitAnimations {
            trail.frame = bounds
            trail.instanceCount = model.segmentCount
            trail.instanceDelay = model.segmentDelay
            trail.instanceColor = NSColor.white.cgColor
            trail.instanceAlphaOffset = -1 / Float(model.segmentCount)

            // Square ends: two segments cover every point of the tail, so it fades without bands.
            segment.bounds = CGRect(x: 0, y: 0, width: model.segmentLength, height: geometry.lineWidth)
            // Segments turn with the outline at a corner.
            segment.allowsEdgeAntialiasing = true

            headGlow.bounds = CGRect(x: 0, y: 0, width: model.headGlowDiameter, height: model.headGlowDiameter)

            // Start one lap in the past, so every tail segment is already moving.
            let begin = newLapStart - model.lapDuration
            segment.add(
                travelAnimation(path: path, model: model, begin: segment.convertTime(begin, from: nil), follows: true),
                forKey: Self.travelKey
            )
            headGlow.add(
                travelAnimation(path: path, model: model, begin: headGlow.convertTime(begin, from: nil), follows: false),
                forKey: Self.travelKey
            )
        }
    }

    private func stop() {
        guard applied != nil else { return }
        applied = nil
        lapStart = nil
        segment.removeAnimation(forKey: Self.travelKey)
        headGlow.removeAnimation(forKey: Self.travelKey)
    }

    /// The outline path, running clockwise on screen.
    private func clockwisePath(_ path: CGPath, signedArea: CGFloat) -> CGPath {
        let yAxisPointsDown = trail.contentsAreFlipped()
        guard (signedArea > 0) != yAxisPointsDown else { return path }
        var mirror = CGAffineTransform(translationX: bounds.minX + bounds.maxX, y: 0).scaledBy(x: -1, y: 1)
        return path.copy(using: &mirror) ?? path
    }

    private func travelAnimation(
        path: CGPath,
        model: WindowBorderSparkModel,
        begin: CFTimeInterval,
        follows: Bool
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.path = path
        animation.calculationMode = .paced
        animation.rotationMode = follows ? .rotateAuto : nil
        animation.duration = model.lapDuration
        animation.repeatCount = .infinity
        animation.beginTime = begin
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        return animation
    }
}

final class WindowBorderAuraLayerView: WindowBorderEffectLayerView {
    private struct Signature: Equatable {
        let geometry: WindowBorderEffectGeometry
        let color: [Int]
        let scale: CGFloat
    }

    private static let pulseKey = "yen.windowBorder.aura.pulse"

    private let glow = CALayer()
    private var geometry: WindowBorderEffectGeometry?
    private var color = NSColor.white
    private var pulse: WindowBorderAuraPulse?
    private var applied: Signature?
    private var appliedPulse: WindowBorderAuraPulse?
    private var glowMargin: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glow.contentsGravity = .resize
        layer?.addSublayer(glow)
    }

    func configure(geometry: WindowBorderEffectGeometry, color: NSColor, pulse: WindowBorderAuraPulse?) {
        self.geometry = geometry
        self.color = color
        self.pulse = pulse
        refresh()
    }

    var isPulsing: Bool {
        glow.animation(forKey: Self.pulseKey) != nil
    }

    /// Seconds from dim to bright in the running pulse, or nil when the glow is still.
    var pulseHalfPeriod: Double? {
        glow.animation(forKey: Self.pulseKey)?.duration
    }

    var hasGlowForTesting: Bool { glow.contents != nil }
    /// How many times the glow image was drawn. Only a new shape, color or
    /// display scale draws it again.
    private(set) var glowDrawCount = 0

    override func refresh() {
        guard let geometry, let window, bounds.width > 1, bounds.height > 1 else {
            stopPulse()
            return
        }
        let model = WindowBorderRenderingPolicy.auraModel(lineWidth: geometry.lineWidth, pulse: pulse ?? .medium)
        let signature = Signature(
            geometry: geometry,
            color: Self.colorKey(color),
            scale: window.backingScaleFactor
        )

        Self.withoutImplicitAnimations {
            if signature != applied {
                applyGlowImage(signature: signature, model: model)
                applied = signature
            }
            // The image stretches between its corners, so a resize moves a frame and redraws nothing.
            glow.frame = bounds.insetBy(dx: -glowMargin, dy: -glowMargin)
            glow.opacity = model.restingOpacity
        }

        guard let pulse else {
            stopPulse()
            return
        }
        if isPulsing, appliedPulse == pulse { return }
        appliedPulse = pulse
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = model.pulseLowOpacity
        animation.toValue = model.pulseHighOpacity
        animation.duration = model.pulseHalfPeriod
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        glow.add(animation, forKey: Self.pulseKey)
    }

    private func stopPulse() {
        appliedPulse = nil
        glow.removeAnimation(forKey: Self.pulseKey)
    }

    /// Draw the glow once for a small outline, and let the layer stretch the
    /// straight runs between its corners.
    private func applyGlowImage(signature: Signature, model: WindowBorderAuraModel) {
        glowDrawCount += 1
        let geometry = signature.geometry
        let margin = ceil(model.blurRadius * 2)
        // A continuous corner runs about 1.53 radii along each edge.
        let cap = ceil(geometry.inset + geometry.cornerRadius * 1.6 + geometry.lineWidth) + 2
        let tile = cap * 2 + 2
        let side = tile + margin * 2
        let scale = signature.scale
        let pixels = Int((side * scale).rounded(.up))
        guard pixels > 0,
              let context = CGContext(
                data: nil,
                width: pixels,
                height: pixels,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            glow.contents = nil
            return
        }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: margin, y: margin)
        let path = geometry.path(in: CGRect(x: 0, y: 0, width: tile, height: tile))
        let stroke = color.usingColorSpace(.sRGB) ?? color
        context.setLineWidth(geometry.lineWidth)
        context.setStrokeColor(stroke.cgColor)
        // Shadow blur is in pixels, not points. Two wide soft passes and a tight
        // bright one read as a glow that is strongest at the stroke.
        for blur in [model.blurRadius, model.blurRadius, model.blurRadius / 3] {
            context.setShadow(offset: .zero, blur: blur * scale, color: stroke.cgColor)
            context.addPath(path)
            context.strokePath()
        }

        glowMargin = margin
        glow.contents = context.makeImage()
        glow.contentsScale = scale
        let stretchStart = (margin + cap) / side
        glow.contentsCenter = CGRect(x: stretchStart, y: stretchStart, width: 2 / side, height: 2 / side)
    }
}
