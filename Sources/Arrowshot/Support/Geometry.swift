import CoreGraphics

enum Geometry {
    static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    static func rotate(_ point: CGPoint, around center: CGPoint, by angle: CGFloat) -> CGPoint {
        let translatedX = point.x - center.x
        let translatedY = point.y - center.y
        let cosine = cos(angle)
        let sine = sin(angle)
        return CGPoint(
            x: center.x + translatedX * cosine - translatedY * sine,
            y: center.y + translatedX * sine + translatedY * cosine
        )
    }

    static func distance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let amount = min(1, max(0, projection))
        let nearest = CGPoint(x: start.x + amount * dx, y: start.y + amount * dy)
        return hypot(point.x - nearest.x, point.y - nearest.y)
    }
}
