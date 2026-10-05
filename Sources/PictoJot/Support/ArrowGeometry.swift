import CoreGraphics
import Foundation

enum ArrowGeometry {
    /// Proportions measured from Skitch's arrow: a triangular head with a flat
    /// base, and a shaft that tapers smoothly (exponentially) from the head's
    /// base down to a thin tail. No barbs — the head's rear edge is straight.
    private static let headHalfWidthPerLength: CGFloat = 0.49
    private static let neckRatio: CGFloat = 0.44
    private static let tailRatio: CGFloat = 0.075
    private static let shaftSamples = 16

    static func points(
        from start: CGPoint,
        to end: CGPoint,
        lineWidth: CGFloat
    ) -> [CGPoint] {
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let arrowLength = hypot(delta.x, delta.y)
        guard arrowLength > 0.5 else { return [] }

        let direction = CGPoint(x: delta.x / arrowLength, y: delta.y / arrowLength)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let headLength = min(arrowLength * 0.52, max(18, lineWidth * 5))
        let headHalfWidth = headLength * headHalfWidthPerLength
        let neckHalfWidth = max(0.5, headHalfWidth * neckRatio)
        let tailHalfWidth = max(0.3, headHalfWidth * tailRatio)
        let wingCenter = CGPoint(
            x: end.x - direction.x * headLength,
            y: end.y - direction.y * headLength
        )

        func offset(_ point: CGPoint, by amount: CGFloat) -> CGPoint {
            CGPoint(x: point.x + normal.x * amount, y: point.y + normal.y * amount)
        }

        /// One side of the shaft, from the tail to the head's base. The width
        /// decays by a constant factor per step, which is what gives Skitch's
        /// arrow its slightly hollowed taper rather than a straight wedge.
        func shaftEdge(sign: CGFloat) -> [CGPoint] {
            (0...shaftSamples).map { index in
                let progress = CGFloat(index) / CGFloat(shaftSamples)
                let halfWidth = tailHalfWidth * pow(neckHalfWidth / tailHalfWidth, progress)
                let center = CGPoint(
                    x: start.x + (wingCenter.x - start.x) * progress,
                    y: start.y + (wingCenter.y - start.y) * progress
                )
                return offset(center, by: halfWidth * sign)
            }
        }

        return shaftEdge(sign: 1)
            + [offset(wingCenter, by: headHalfWidth), end, offset(wingCenter, by: -headHalfWidth)]
            + shaftEdge(sign: -1).reversed()
    }

    static func boundingRect(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
