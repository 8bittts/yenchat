import Foundation
import Testing
@testable import YEN

struct TerminalSplitDropZoneTests {
    private let standardSize = CGSize(width: 100, height: 100)

    @Test func topEdge() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: 5), in: standardSize)
        #expect(zone == .top)
    }

    @Test func bottomEdge() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: 95), in: standardSize)
        #expect(zone == .bottom)
    }

    @Test func leftEdge() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 5, y: 50), in: standardSize)
        #expect(zone == .left)
    }

    @Test func rightEdge() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 95, y: 50), in: standardSize)
        #expect(zone == .right)
    }

    @Test func topLeftCornerSelectsLeft() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 0, y: 0), in: standardSize)
        #expect(zone == .left)
    }

    @Test func topRightCornerSelectsRight() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 100, y: 0), in: standardSize)
        #expect(zone == .right)
    }

    @Test func bottomLeftCornerSelectsLeft() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 0, y: 100), in: standardSize)
        #expect(zone == .left)
    }

    @Test func bottomRightCornerSelectsRight() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 100, y: 100), in: standardSize)
        #expect(zone == .right)
    }

    @Test func centerSelectsLeft() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: 50), in: standardSize)
        #expect(zone == .left)
    }

    @Test func rectangularViewTopEdge() {
        let size = CGSize(width: 200, height: 100)
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 100, y: 10), in: size)
        #expect(zone == .top)
    }

    @Test func rectangularViewLeftEdge() {
        let size = CGSize(width: 200, height: 100)
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 10, y: 50), in: size)
        #expect(zone == .left)
    }

    @Test func tallRectangleTopEdge() {
        let size = CGSize(width: 100, height: 200)
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: 10), in: size)
        #expect(zone == .top)
    }

    @Test func pointLeftOfViewSelectsLeft() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: -10, y: 50), in: standardSize)
        #expect(zone == .left)
    }

    @Test func pointAboveViewSelectsTop() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: -10), in: standardSize)
        #expect(zone == .top)
    }

    @Test func pointRightOfViewSelectsRight() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 110, y: 50), in: standardSize)
        #expect(zone == .right)
    }

    @Test func pointBelowViewSelectsBottom() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 50, y: 110), in: standardSize)
        #expect(zone == .bottom)
    }

    @Test func upperLeftTriangleSelectsLeft() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 20, y: 30), in: standardSize)
        #expect(zone == .left)
    }

    @Test func upperRightTriangleSelectsRight() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 80, y: 30), in: standardSize)
        #expect(zone == .right)
    }

    @Test func lowerLeftTriangleSelectsLeft() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 20, y: 70), in: standardSize)
        #expect(zone == .left)
    }

    @Test func lowerRightTriangleSelectsRight() {
        let zone = TerminalSplitDropZone.calculate(at: CGPoint(x: 80, y: 70), in: standardSize)
        #expect(zone == .right)
    }
}
