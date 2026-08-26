import CoreGraphics
import Foundation

enum ArrowGeometry {
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
        let headHalfWidth = min(headLength * 0.55, max(9, lineWidth * 2.2))
        let tailHalfWidth = min(
            max(1.2, lineWidth * 0.38),
            max(0.75, headHalfWidth * 0.45)
        )
        let neckHalfWidth = min(
            max(tailHalfWidth * 1.35, lineWidth * 0.65),
            headHalfWidth * 0.58
        )
        let wingCenter = CGPoint(
            x: end.x - direction.x * headLength,
            y: end.y - direction.y * headLength
        )
        let neckInset = min(headLength * 0.20, max(3, lineWidth * 0.8))
        let neckCenter = CGPoint(
            x: wingCenter.x + direction.x * neckInset,
            y: wingCenter.y + direction.y * neckInset
        )

        func offset(_ point: CGPoint, by amount: CGFloat) -> CGPoint {
            CGPoint(x: point.x + normal.x * amount, y: point.y + normal.y * amount)
        }

        return [
            offset(start, by: tailHalfWidth),
            offset(neckCenter, by: neckHalfWidth),
            offset(wingCenter, by: headHalfWidth),
            end,
            offset(wingCenter, by: -headHalfWidth),
            offset(neckCenter, by: -neckHalfWidth),
            offset(start, by: -tailHalfWidth),
        ]
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
