import AppKit
import Testing
@testable import YEN

struct NSScreenExtensionTests {
    @Test func nativeWindowResizeCannotExceedVisibleScreen() {
        let visibleSize = NSSize(width: 2056, height: 1289)

        #expect(
            YENGeometryClamp.sanitize(
                size: NSSize(width: 2057, height: 1290),
                visibleSize: visibleSize
            ) == visibleSize
        )
        #expect(
            YENGeometryClamp.sanitize(
                size: NSSize(width: 1000, height: 700),
                visibleSize: visibleSize
            ) == NSSize(width: 1000, height: 700)
        )
    }

    @Test func positiveCoordinateConversion() {
        let mockScreenFrame = NSRect(x: 0, y: 100, width: 1000, height: 800)
        let mockScreen = MockNSScreen(visibleFrame: mockScreenFrame)
        let windowSize = CGSize(width: 400, height: 300)

        let origin = mockScreen.origin(
            fromTopLeftOffsetX: 15,
            offsetY: 15,
            windowSize: windowSize
        )

        #expect(origin.x == 15)
        #expect(origin.y == 585)
    }

    @Test func zeroCoordinates() {
        let mockScreenFrame = NSRect(x: 0, y: 100, width: 1000, height: 800)
        let mockScreen = MockNSScreen(visibleFrame: mockScreenFrame)
        let windowSize = CGSize(width: 400, height: 300)

        let origin = mockScreen.origin(
            fromTopLeftOffsetX: 0,
            offsetY: 0,
            windowSize: windowSize
        )

        #expect(origin.x == 0)
        #expect(origin.y == 600)
    }

    @Test func offsetScreen() {
        let mockScreenFrame = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let mockScreen = MockNSScreen(visibleFrame: mockScreenFrame)
        let windowSize = CGSize(width: 600, height: 400)

        let origin = mockScreen.origin(
            fromTopLeftOffsetX: 100,
            offsetY: 50,
            windowSize: windowSize
        )

        #expect(origin.x == 1540)
        #expect(origin.y == 630)
    }

    @Test func largeCoordinates() {
        let mockScreenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let mockScreen = MockNSScreen(visibleFrame: mockScreenFrame)
        let windowSize = CGSize(width: 400, height: 300)

        let origin = mockScreen.origin(
            fromTopLeftOffsetX: 500,
            offsetY: 200,
            windowSize: windowSize
        )

        #expect(origin.x == 500)
        #expect(origin.y == 580)
    }
}

private class MockNSScreen: NSScreen {
    private let mockVisibleFrame: NSRect

    init(visibleFrame: NSRect) {
        self.mockVisibleFrame = visibleFrame
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var visibleFrame: NSRect {
        mockVisibleFrame
    }
}
