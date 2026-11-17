import AppKit

enum YENGeometryClamp {
    static func sanitize(size: NSSize, visibleSize: NSSize) -> NSSize {
        NSSize(
            width: min(size.width, visibleSize.width),
            height: min(size.height, visibleSize.height)
        )
    }

    static func clampedLength(_ proposed: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(proposed, minimum), maximum)
    }

    static func sanitize(frame: NSRect, visibleFrame: NSRect) -> NSRect {
        guard frame.width > 0, frame.height > 0 else {
            return NSRect(origin: visibleFrame.origin, size: .zero)
        }

        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let maxX = visibleFrame.maxX - width
        let maxY = visibleFrame.maxY - height
        let x = maxX >= visibleFrame.minX ? min(max(frame.origin.x, visibleFrame.minX), maxX) : visibleFrame.minX
        let y = maxY >= visibleFrame.minY ? min(max(frame.origin.y, visibleFrame.minY), maxY) : visibleFrame.minY

        return NSRect(x: x, y: y, width: width, height: height)
    }
}

enum TerminalAuxiliaryAnchorPolicy {
    struct Candidate<Window> {
        let identity: ObjectIdentifier
        let window: Window
        let isEligible: Bool
    }

    nonisolated static func canAnchor(
        windowControllerIsTerminal: Bool,
        isQuickTerminal: Bool,
        isFullscreen: Bool,
        isMiniaturized: Bool,
        isVisible: Bool
    ) -> Bool {
        windowControllerIsTerminal && !isQuickTerminal && !isFullscreen && !isMiniaturized && isVisible
    }

    static func firstEligible<Window>(in candidates: [Candidate<Window>]) -> Window? {
        var seenCandidateIDs = Set<ObjectIdentifier>()
        for candidate in candidates {
            guard seenCandidateIDs.insert(candidate.identity).inserted else { continue }
            guard candidate.isEligible else { continue }
            return candidate.window
        }

        return nil
    }
}
