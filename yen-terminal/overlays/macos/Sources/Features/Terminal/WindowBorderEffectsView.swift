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

    func makeNSView(context: Context) -> WindowBorderSparkLayerView {
        WindowBorderSparkLayerView()
    }

    func updateNSView(_ view: WindowBorderSparkLayerView, context: Context) {
        view.configure(geometry: geometry, color: color)
    }
}

/// The glow around the outline.
struct WindowBorderAuraView: NSViewRepresentable {
    let geometry: WindowBorderEffectGeometry
    let color: NSColor
    let pulses: Bool

    func makeNSView(context: Context) -> WindowBorderAuraLayerView {
        WindowBorderAuraLayerView()
    }

    func updateNSView(_ view: WindowBorderAuraLayerView, context: Context) {
        view.configure(geometry: geometry, color: color, pulses: pulses)
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
        let color: NSColor
    }

    private static let travelKey = "yen.windowBorder.spark.travel"

    private let trail = CAReplicatorLayer()
    private let segment = CALayer()
    private let headGlow = CAGradientLayer()
    private var geometry: WindowBorderEffectGeometry?
    private var color = NSColor.white
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

    func configure(geometry: WindowBorderEffectGeometry, color: NSColor) {
        self.geometry = geometry
        self.color = color
        refresh()
    }

    var isTraveling: Bool {
        segment.animation(forKey: Self.travelKey) != nil
    }

    var segmentCountForTesting: Int { trail.instanceCount }
    var segmentSizeForTesting: CGSize { segment.bounds.size }

    override func refresh() {
        guard let geometry, window != nil, bounds.width > 1, bounds.height > 1 else {
            stop()
            return
        }
        let signature = Signature(size: bounds.size, geometry: geometry, color: color)
        if signature == applied, isTraveling { return }

        let path = clockwisePath(for: geometry)
        let metrics = WindowBorderRenderingPolicy.pathMetrics(of: path)
        guard let model = WindowBorderRenderingPolicy.sparkModel(
            perimeter: metrics.perimeter,
            lineWidth: geometry.lineWidth
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
            segment.backgroundColor = color.cgColor

            headGlow.bounds = CGRect(x: 0, y: 0, width: model.headGlowDiameter, height: model.headGlowDiameter)
            headGlow.colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor]

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
    private func clockwisePath(for geometry: WindowBorderEffectGeometry) -> CGPath {
        let path = geometry.path(in: bounds)
        let area = WindowBorderRenderingPolicy.pathMetrics(of: path).signedArea
        let yAxisPointsDown = trail.contentsAreFlipped()
        guard (area > 0) != yAxisPointsDown else { return path }
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
        let color: NSColor
        let scale: CGFloat
    }

    private static let pulseKey = "yen.windowBorder.aura.pulse"

    private let glow = CALayer()
    private var geometry: WindowBorderEffectGeometry?
    private var color = NSColor.white
    private var pulses = false
    private var applied: Signature?
    private var glowMargin: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glow.contentsGravity = .resize
        layer?.addSublayer(glow)
    }

    func configure(geometry: WindowBorderEffectGeometry, color: NSColor, pulses: Bool) {
        self.geometry = geometry
        self.color = color
        self.pulses = pulses
        refresh()
    }

    var isPulsing: Bool {
        glow.animation(forKey: Self.pulseKey) != nil
    }

    var hasGlowForTesting: Bool { glow.contents != nil }

    override func refresh() {
        guard let geometry, let window, bounds.width > 1, bounds.height > 1 else {
            glow.removeAnimation(forKey: Self.pulseKey)
            return
        }
        let model = WindowBorderRenderingPolicy.auraModel(lineWidth: geometry.lineWidth)
        let signature = Signature(geometry: geometry, color: color, scale: window.backingScaleFactor)

        Self.withoutImplicitAnimations {
            if signature != applied {
                applyGlowImage(signature: signature, model: model)
                applied = signature
            }
            // The image stretches between its corners, so a resize moves a frame and redraws nothing.
            glow.frame = bounds.insetBy(dx: -glowMargin, dy: -glowMargin)
            glow.opacity = model.restingOpacity
        }

        guard pulses else {
            glow.removeAnimation(forKey: Self.pulseKey)
            return
        }
        guard !isPulsing else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = model.pulseLowOpacity
        pulse.toValue = model.pulseHighOpacity
        pulse.duration = model.pulseHalfPeriod
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.isRemovedOnCompletion = false
        pulse.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        glow.add(pulse, forKey: Self.pulseKey)
    }

    /// Draw the glow once for a small outline, and let the layer stretch the
    /// straight runs between its corners.
    private func applyGlowImage(signature: Signature, model: WindowBorderAuraModel) {
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
        let stroke = signature.color.usingColorSpace(.sRGB) ?? signature.color
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
