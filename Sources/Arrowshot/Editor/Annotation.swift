import AppKit

enum EditorTool: Int, CaseIterable, Hashable {
    case arrow
    case text
    case rectangle
    case ellipse
    case line
    case mosaic
    case crop

    var title: String {
        switch self {
        case .arrow: NSLocalizedString("Arrow", comment: "")
        case .text: NSLocalizedString("Text", comment: "")
        case .rectangle: NSLocalizedString("Rectangle", comment: "")
        case .ellipse: NSLocalizedString("Ellipse", comment: "")
        case .line: NSLocalizedString("Line", comment: "")
        case .mosaic: NSLocalizedString("Pixelate", comment: "")
        case .crop: NSLocalizedString("Crop", comment: "")
        }
    }

    /// Single-key shortcut, matching CanvasView's keyDown handling.
    var shortcutLabel: String {
        switch self {
        case .arrow: "A"
        case .text: "T"
        case .rectangle: "R"
        case .ellipse: "O"
        case .line: "L"
        case .mosaic: "M"
        case .crop: "C"
        }
    }
}

enum AnnotationKind {
    case arrow
    case text
    case rectangle
    case ellipse
    case line
    case mosaic
}

enum AnnotationEndpoint {
    case start
    case end
}

enum AnnotationCorner: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var opposite: AnnotationCorner {
        switch self {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        }
    }

    var horizontalSign: CGFloat {
        switch self {
        case .topLeft, .bottomLeft: -1
        case .topRight, .bottomRight: 1
        }
    }

    var verticalSign: CGFloat {
        switch self {
        case .topLeft, .topRight: -1
        case .bottomLeft, .bottomRight: 1
        }
    }
}

struct Annotation {
    let id: UUID
    var kind: AnnotationKind
    var rect: CGRect
    var start: CGPoint
    var end: CGPoint
    var rotation: CGFloat
    var color: NSColor
    var lineWidth: CGFloat
    var text: String
    var textSize: CGFloat
    /// Rectangles and ellipses only: fill the shape instead of stroking its outline.
    var filled: Bool

    init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        rect: CGRect = .zero,
        start: CGPoint = .zero,
        end: CGPoint = .zero,
        rotation: CGFloat = 0,
        color: NSColor,
        lineWidth: CGFloat,
        text: String = "",
        textSize: CGFloat = 0,
        filled: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.rect = rect.standardized
        self.start = start
        self.end = end
        self.rotation = rotation
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.textSize = kind == .text && textSize <= 0 ? 16 + lineWidth * 3 : textSize
        self.filled = filled
    }

    var center: CGPoint {
        switch kind {
        case .arrow, .line:
            CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        default:
            CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    var bounds: CGRect {
        switch kind {
        case .arrow:
            let margin = max(12, lineWidth * 2.5)
            return Geometry.normalizedRect(from: start, to: end).insetBy(dx: -margin, dy: -margin)
        case .line:
            return Geometry.normalizedRect(from: start, to: end).insetBy(dx: -10, dy: -10)
        default:
            return rect
        }
    }

    var displayedStart: CGPoint {
        Geometry.rotate(start, around: center, by: rotation)
    }

    var displayedEnd: CGPoint {
        Geometry.rotate(end, around: center, by: rotation)
    }

    var displayedVisualBounds: CGRect {
        switch kind {
        case .arrow:
            return ArrowGeometry.boundingRect(
                for: ArrowGeometry.points(
                    from: displayedStart,
                    to: displayedEnd,
                    lineWidth: lineWidth
                )
            )
        case .line:
            let strokeMargin = max(0.5, lineWidth / 2)
            return Geometry.normalizedRect(from: displayedStart, to: displayedEnd)
                .insetBy(dx: -strokeMargin, dy: -strokeMargin)
        case .rectangle, .ellipse:
            let bounds = ArrowGeometry.boundingRect(
                for: AnnotationCorner.allCases.map(displayedCorner)
            )
            let strokeMargin = max(0.5, lineWidth / 2)
            return bounds.insetBy(dx: -strokeMargin, dy: -strokeMargin)
        case .text, .mosaic:
            return rect
        }
    }

    func constrainedTranslation(_ proposed: CGPoint, within imageSize: CGSize) -> CGPoint {
        let bounds = displayedVisualBounds
        let allowsTrailingOverflow = kind == .text

        func constrain(
            _ value: CGFloat,
            minimum: CGFloat,
            maximum: CGFloat,
            containerMaximum: CGFloat
        ) -> CGFloat {
            let lowerBound = -minimum
            if allowsTrailingOverflow {
                return max(value, lowerBound)
            }
            let upperBound = containerMaximum - maximum
            guard lowerBound <= upperBound else {
                // An already oversized object cannot fit on this axis. Keeping it
                // stationary prevents dragging from increasing the overflow.
                return 0
            }
            return min(max(value, lowerBound), upperBound)
        }

        return CGPoint(
            x: constrain(
                proposed.x,
                minimum: bounds.minX,
                maximum: bounds.maxX,
                containerMaximum: imageSize.width
            ),
            y: constrain(
                proposed.y,
                minimum: bounds.minY,
                maximum: bounds.maxY,
                containerMaximum: imageSize.height
            )
        )
    }

    mutating func flattenLineRotation() {
        guard kind == .arrow || kind == .line, rotation != 0 else { return }
        let visibleStart = displayedStart
        let visibleEnd = displayedEnd
        start = visibleStart
        end = visibleEnd
        rotation = 0
    }

    mutating func moveEndpoint(_ endpoint: AnnotationEndpoint, to point: CGPoint) {
        flattenLineRotation()
        switch endpoint {
        case .start:
            start = point
        case .end:
            end = point
        }
    }

    func displayedCorner(_ corner: AnnotationCorner) -> CGPoint {
        let point: CGPoint
        switch corner {
        case .topLeft:
            point = CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            point = CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            point = CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            point = CGPoint(x: rect.maxX, y: rect.maxY)
        }
        return Geometry.rotate(point, around: center, by: rotation)
    }

    mutating func resize(from corner: AnnotationCorner, to displayedPoint: CGPoint, minimumSize: CGFloat = 4) {
        guard kind == .rectangle || kind == .ellipse else { return }
        let fixedPoint = displayedCorner(corner.opposite)
        let localPoint = Geometry.rotate(displayedPoint, around: fixedPoint, by: -rotation)
        var localX = localPoint.x - fixedPoint.x
        var localY = localPoint.y - fixedPoint.y
        localX = corner.horizontalSign * max(minimumSize, localX * corner.horizontalSign)
        localY = corner.verticalSign * max(minimumSize, localY * corner.verticalSign)

        let clampedLocalPoint = CGPoint(x: fixedPoint.x + localX, y: fixedPoint.y + localY)
        let clampedDisplayedPoint = Geometry.rotate(clampedLocalPoint, around: fixedPoint, by: rotation)
        let newCenter = CGPoint(
            x: (fixedPoint.x + clampedDisplayedPoint.x) / 2,
            y: (fixedPoint.y + clampedDisplayedPoint.y) / 2
        )
        rect = CGRect(
            x: newCenter.x - abs(localX) / 2,
            y: newCenter.y - abs(localY) / 2,
            width: abs(localX),
            height: abs(localY)
        )
    }

    mutating func resizeText(to point: CGPoint, minimumScale: CGFloat = 0.25) {
        guard kind == .text, rect.width > 0, rect.height > 0 else { return }
        rotation = 0
        let diagonal = CGPoint(x: rect.width, y: rect.height)
        let dragged = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
        let denominator = diagonal.x * diagonal.x + diagonal.y * diagonal.y
        let projectedScale = (dragged.x * diagonal.x + dragged.y * diagonal.y) / denominator
        let scale = max(minimumScale, projectedScale)
        rect.size = CGSize(width: rect.width * scale, height: rect.height * scale)
        textSize = max(8, textSize * scale)
    }

    mutating func move(by offset: CGPoint) {
        rect = rect.offsetBy(dx: offset.x, dy: offset.y)
        start.x += offset.x
        start.y += offset.y
        end.x += offset.x
        end.y += offset.y
    }
}
