import AppKit

@MainActor
enum EditorCursors {
    static let fourWayResize = NSCursor(
        image: makeFourWayResizeImage(),
        hotSpot: CGPoint(x: 14, y: 14)
    )

    private static var rotationCache: [Int: NSCursor] = [:]

    static func rotation(angle: CGFloat) -> NSCursor {
        let step = Int((angle * 180 / .pi / 15).rounded())
        if let cached = rotationCache[step] {
            return cached
        }
        let cursor = NSCursor(
            image: makeRotationImage(angle: CGFloat(step) * 15 * .pi / 180),
            hotSpot: CGPoint(x: 14, y: 14)
        )
        rotationCache[step] = cursor
        return cursor
    }

    private static func makeFourWayResizeImage() -> NSImage {
        NSImage(size: CGSize(width: 28, height: 28), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 4, y: 14))
            path.line(to: CGPoint(x: 24, y: 14))
            path.move(to: CGPoint(x: 14, y: 4))
            path.line(to: CGPoint(x: 14, y: 24))
            addArrowHead(to: path, tip: CGPoint(x: 4, y: 14), direction: .pi)
            addArrowHead(to: path, tip: CGPoint(x: 24, y: 14), direction: 0)
            addArrowHead(to: path, tip: CGPoint(x: 14, y: 4), direction: -.pi / 2)
            addArrowHead(to: path, tip: CGPoint(x: 14, y: 24), direction: .pi / 2)
            strokeCursorPath(path)
            return true
        }
    }

    private static func makeRotationImage(angle: CGFloat) -> NSImage {
        NSImage(size: CGSize(width: 28, height: 28), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            if let context = NSGraphicsContext.current?.cgContext {
                context.translateBy(x: 14, y: 14)
                context.rotate(by: angle)
                context.translateBy(x: -14, y: -14)
            }

            let path = NSBezierPath()
            let horizontalTip = CGPoint(x: 6, y: 21)
            let verticalTip = CGPoint(x: 21, y: 6)
            path.move(to: horizontalTip)
            path.line(to: CGPoint(x: 21, y: 21))
            path.line(to: verticalTip)
            addArrowHead(to: path, tip: horizontalTip, direction: .pi, size: 4)
            addArrowHead(to: path, tip: verticalTip, direction: -.pi / 2, size: 4)
            strokeCursorPath(path)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    private static func addArrowHead(
        to path: NSBezierPath,
        tip: CGPoint,
        direction: CGFloat,
        size: CGFloat = 4.5
    ) {
        let spread: CGFloat = .pi / 5
        let first = CGPoint(
            x: tip.x - size * cos(direction - spread),
            y: tip.y - size * sin(direction - spread)
        )
        let second = CGPoint(
            x: tip.x - size * cos(direction + spread),
            y: tip.y - size * sin(direction + spread)
        )
        path.move(to: first)
        path.line(to: tip)
        path.line(to: second)
    }

    private static func strokeCursorPath(_ path: NSBezierPath) {
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = 4
        NSColor.white.setStroke()
        path.stroke()
        path.lineWidth = 2
        NSColor.black.setStroke()
        path.stroke()
    }
}
