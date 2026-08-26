import CoreGraphics
import XCTest
@testable import PictoJot

final class GeometryTests: XCTestCase {
    func testRotatedRectangleResizeKeepsOppositeCornerFixed() {
        var rectangle = Annotation(
            kind: .rectangle,
            rect: CGRect(x: 20, y: 30, width: 100, height: 60),
            rotation: .pi / 4,
            color: .red,
            lineWidth: 4
        )
        let fixedCorner = rectangle.displayedCorner(.bottomRight)
        let target = CGPoint(x: 5, y: 10)

        rectangle.resize(from: .topLeft, to: target)

        let resizedFixedCorner = rectangle.displayedCorner(.bottomRight)
        XCTAssertEqual(resizedFixedCorner.x, fixedCorner.x, accuracy: 0.0001)
        XCTAssertEqual(resizedFixedCorner.y, fixedCorner.y, accuracy: 0.0001)
    }

    func testMovingArrowEndpointKeepsOppositeVisibleEndpointFixed() {
        var arrow = Annotation(
            kind: .arrow,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 10, y: 0),
            rotation: .pi / 2,
            color: .red,
            lineWidth: 4
        )
        let fixedEndpoint = arrow.displayedEnd

        arrow.moveEndpoint(.start, to: CGPoint(x: 2, y: 8))

        XCTAssertEqual(arrow.end.x, fixedEndpoint.x, accuracy: 0.0001)
        XCTAssertEqual(arrow.end.y, fixedEndpoint.y, accuracy: 0.0001)
        XCTAssertEqual(arrow.rotation, 0, accuracy: 0.0001)
    }

    func testTextResizeScalesFromTopLeftAndRemovesRotation() {
        var text = Annotation(
            kind: .text,
            rect: CGRect(x: 40, y: 50, width: 120, height: 48),
            rotation: .pi / 3,
            color: .red,
            lineWidth: 6,
            text: "PictoJot",
            textSize: 34
        )

        text.resizeText(to: CGPoint(x: 280, y: 146))

        XCTAssertEqual(text.rect.origin, CGPoint(x: 40, y: 50))
        XCTAssertEqual(text.rect.width, 240, accuracy: 0.0001)
        XCTAssertEqual(text.rect.height, 96, accuracy: 0.0001)
        XCTAssertEqual(text.textSize, 68, accuracy: 0.0001)
        XCTAssertEqual(text.rotation, 0, accuracy: 0.0001)
    }

    func testShapeTranslationKeepsRotatedVisualBoundsInsideImage() {
        let rectangle = Annotation(
            kind: .rectangle,
            rect: CGRect(x: 30, y: 40, width: 100, height: 60),
            rotation: .pi / 4,
            color: .red,
            lineWidth: 6
        )

        let translation = rectangle.constrainedTranslation(
            CGPoint(x: 500, y: 500),
            within: CGSize(width: 240, height: 180)
        )
        let movedBounds = rectangle.displayedVisualBounds.offsetBy(
            dx: translation.x,
            dy: translation.y
        )

        XCTAssertLessThanOrEqual(movedBounds.maxX, 240.0001)
        XCTAssertLessThanOrEqual(movedBounds.maxY, 180.0001)
    }

    func testTextTranslationConstrainsTopAndLeftButAllowsRightAndBottomOverflow() {
        let text = Annotation(
            kind: .text,
            rect: CGRect(x: 20, y: 30, width: 180, height: 80),
            color: .red,
            lineWidth: 6,
            text: "PictoJot",
            textSize: 34
        )

        let leadingTranslation = text.constrainedTranslation(
            CGPoint(x: -100, y: -100),
            within: CGSize(width: 120, height: 70)
        )
        XCTAssertEqual(leadingTranslation, CGPoint(x: -20, y: -30))

        let trailingTranslation = text.constrainedTranslation(
            CGPoint(x: 300, y: 300),
            within: CGSize(width: 120, height: 70)
        )
        XCTAssertEqual(trailingTranslation, CGPoint(x: 300, y: 300))
    }

    func testNormalizedRectHandlesReverseDrag() {
        let result = Geometry.normalizedRect(
            from: CGPoint(x: 90, y: 80),
            to: CGPoint(x: 20, y: 10)
        )

        XCTAssertEqual(result, CGRect(x: 20, y: 10, width: 70, height: 70))
    }

    func testRotatingPointQuarterTurn() {
        let result = Geometry.rotate(
            CGPoint(x: 20, y: 10),
            around: CGPoint(x: 10, y: 10),
            by: .pi / 2
        )

        XCTAssertEqual(result.x, 10, accuracy: 0.0001)
        XCTAssertEqual(result.y, 20, accuracy: 0.0001)
    }

    func testDistanceToSegmentUsesNearestPoint() {
        let result = Geometry.distance(
            from: CGPoint(x: 5, y: 5),
            toSegmentStart: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 10, y: 0)
        )

        XCTAssertEqual(result, 5, accuracy: 0.0001)
    }
}
