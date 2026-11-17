import AppKit
import Testing
@testable import YEN

@MainActor
struct SplitFocusClickHitTestingTests {
    @Test func contentViewCoordinatesPickTheClickedSiblingSurface() {
        let contentView = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let leftSurface = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let rightSurface = NSView(frame: CGRect(x: 400, y: 0, width: 400, height: 600))

        contentView.addSubview(leftSurface)
        contentView.addSubview(rightSurface)

        let pointInRightSurface = NSPoint(x: 650, y: 240)
        #expect(
            SplitFocusClickHitTesting.surfaceOwnsContentViewHit(
                surfaceView: rightSurface,
                contentView: contentView,
                locationInContentView: pointInRightSurface
            )
        )
        #expect(
            !SplitFocusClickHitTesting.surfaceOwnsContentViewHit(
                surfaceView: leftSurface,
                contentView: contentView,
                locationInContentView: pointInRightSurface
            )
        )
    }

    @Test func descendantHitsStillBelongToTheSurface() {
        let contentView = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let surface = NSView(frame: CGRect(x: 200, y: 120, width: 320, height: 240))
        let child = NSView(frame: CGRect(x: 40, y: 30, width: 80, height: 60))

        surface.addSubview(child)
        contentView.addSubview(surface)

        let pointInChild = NSPoint(
            x: surface.frame.minX + child.frame.midX,
            y: surface.frame.minY + child.frame.midY
        )
        #expect(
            SplitFocusClickHitTesting.surfaceOwnsContentViewHit(
                surfaceView: surface,
                contentView: contentView,
                locationInContentView: pointInChild
            )
        )
    }

    @Test func siblingOverlayHitsDoNotBelongToTheSurface() {
        let contentView = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let surface = NSView(frame: CGRect(x: 160, y: 100, width: 360, height: 260))
        let overlay = NSView(frame: CGRect(x: 180, y: 120, width: 140, height: 80))

        contentView.addSubview(surface)
        contentView.addSubview(overlay)

        let pointInOverlay = NSPoint(x: overlay.frame.midX, y: overlay.frame.midY)
        #expect(
            !SplitFocusClickHitTesting.surfaceOwnsContentViewHit(
                surfaceView: surface,
                contentView: contentView,
                locationInContentView: pointInOverlay
            )
        )
    }
}
