import AppKit
import Foundation

@main
struct CoreLogicSmokeTests {
    @MainActor
    static func main() {
        precondition(EditorTool.allCases.first == .arrow)
        precondition(!EditorTool.allCases.map(\.title).contains("選択"))
        for symbolName in [
            "arrow.down.left",
            "rectangle",
            "circle",
            "line.diagonal",
            "crop",
            "arrow.uturn.backward",
            "arrow.uturn.forward",
            "doc.on.doc",
            "square.and.arrow.down"
        ] {
            precondition(NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil)
        }

        let reverseDrag = Geometry.normalizedRect(
            from: CGPoint(x: 90, y: 80),
            to: CGPoint(x: 20, y: 10)
        )
        precondition(reverseDrag == CGRect(x: 20, y: 10, width: 70, height: 70))

        let rotated = Geometry.rotate(
            CGPoint(x: 20, y: 10),
            around: CGPoint(x: 10, y: 10),
            by: .pi / 2
        )
        precondition(abs(rotated.x - 10) < 0.0001)
        precondition(abs(rotated.y - 20) < 0.0001)

        let original = CGRect(x: -500, y: 120, width: 320, height: 240)
        let quartz = ScreenCoordinates.cocoaRectToQuartz(original, primaryScreenHeight: 982)
        let roundTrip = ScreenCoordinates.quartzRectToCocoa(quartz, primaryScreenHeight: 982)
        precondition(roundTrip == original)

        let secondaryScreen = CGRect(x: 1920, y: -240, width: 2560, height: 1440)
        let overlayContent = OverlayWindowGeometry.contentRect(forScreenFrame: secondaryScreen)
        precondition(overlayContent == CGRect(x: 0, y: 0, width: 2560, height: 1440))

        let outputSize = CaptureOutputSizing.pixels(
            forLogicalSize: CGSize(width: 1475, height: 1007)
        )
        precondition(outputSize.width == 1475)
        precondition(outputSize.height == 1007)

        let nativeSize = CaptureOutputSizing.nativePixels(
            forLogicalSize: CGSize(width: 1022, height: 659),
            pointPixelScale: 2
        )
        precondition(nativeSize.width == 2044)
        precondition(nativeSize.height == 1318)

        let referenceColor = PictoJotStyle.defaultAnnotationColor.usingColorSpace(.sRGB)!
        precondition(abs(referenceColor.redComponent - 1) < 0.0001)
        precondition(abs(referenceColor.greenComponent - 59 / 255) < 0.0001)
        precondition(abs(referenceColor.blueComponent - 48 / 255) < 0.0001)
        let outlineColor = PictoJotStyle.textOutlineColor.usingColorSpace(.sRGB)!
        precondition(outlineColor.redComponent == 1)
        precondition(outlineColor.greenComponent == 1)
        precondition(outlineColor.blueComponent == 1)
        precondition(PictoJotStyle.textOutlineWidth > 0)

        var arrow = Annotation(
            kind: .arrow,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 10, y: 0),
            rotation: .pi / 2,
            color: referenceColor,
            lineWidth: 4
        )
        let fixedEndpoint = arrow.displayedEnd
        arrow.moveEndpoint(.start, to: CGPoint(x: 2, y: 8))
        precondition(hypot(arrow.end.x - fixedEndpoint.x, arrow.end.y - fixedEndpoint.y) < 0.0001)
        precondition(arrow.rotation == 0)

        let arrowPoints = ArrowGeometry.points(
            from: CGPoint(x: 10, y: 30),
            to: CGPoint(x: 110, y: 30),
            lineWidth: 6
        )
        precondition(ArrowGeometry.boundingRect(for: arrowPoints).maxX == 110)
        // Skitch-style silhouette: widest at the head, tapering to a thin tail.
        let arrowBounds = ArrowGeometry.boundingRect(for: arrowPoints)
        let tailHalfWidth = arrowPoints.map { abs($0.y - 30) }.min()!
        let headHalfWidth = arrowBounds.height / 2
        precondition(headHalfWidth > tailHalfWidth * 6)
        precondition(abs(headHalfWidth - 0.49 * max(18, 6 * 5)) < 0.5)

        var rectangle = Annotation(
            kind: .rectangle,
            rect: CGRect(x: 20, y: 30, width: 100, height: 60),
            rotation: .pi / 4,
            color: referenceColor,
            lineWidth: 4
        )
        let fixedCorner = rectangle.displayedCorner(.bottomRight)
        rectangle.resize(from: .topLeft, to: CGPoint(x: 5, y: 10))
        let resizedFixedCorner = rectangle.displayedCorner(.bottomRight)
        precondition(hypot(resizedFixedCorner.x - fixedCorner.x, resizedFixedCorner.y - fixedCorner.y) < 0.0001)

        var text = Annotation(
            kind: .text,
            rect: CGRect(x: 40, y: 50, width: 120, height: 48),
            rotation: .pi / 3,
            color: referenceColor,
            lineWidth: 6,
            text: "PictoJot",
            textSize: 34
        )
        text.resizeText(to: CGPoint(x: 280, y: 146))
        precondition(text.rect.origin == CGPoint(x: 40, y: 50))
        precondition(abs(text.rect.width - 240) < 0.0001)
        precondition(abs(text.rect.height - 96) < 0.0001)
        precondition(abs(text.textSize - 68) < 0.0001)
        precondition(text.rotation == 0)

        let textLeadingConstraint = text.constrainedTranslation(
            CGPoint(x: -100, y: -100),
            within: CGSize(width: 200, height: 100)
        )
        let constrainedTextBounds = text.displayedVisualBounds.offsetBy(
            dx: textLeadingConstraint.x,
            dy: textLeadingConstraint.y
        )
        precondition(constrainedTextBounds.minX >= 0)
        precondition(constrainedTextBounds.minY >= 0)
        let textTrailingOverflow = text.constrainedTranslation(
            CGPoint(x: 300, y: 300),
            within: CGSize(width: 200, height: 100)
        )
        precondition(textTrailingOverflow == CGPoint(x: 300, y: 300))

        let rectangleTranslation = rectangle.constrainedTranslation(
            CGPoint(x: 500, y: 500),
            within: CGSize(width: 300, height: 240)
        )
        let constrainedRectangleBounds = rectangle.displayedVisualBounds.offsetBy(
            dx: rectangleTranslation.x,
            dy: rectangleTranslation.y
        )
        precondition(constrainedRectangleBounds.maxX <= 300.0001)
        precondition(constrainedRectangleBounds.maxY <= 240.0001)

        precondition(EditorCursors.fourWayResize.image.size == CGSize(width: 28, height: 28))
        precondition(EditorCursors.rotation(angle: .pi / 3).image.size == CGSize(width: 28, height: 28))

        let highResolutionRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 20,
            pixelsHigh: 12,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        // A 2x capture keeps all of its pixels while reporting a logical size.
        let retinaCapture = NSImage(cgImage: highResolutionRep.cgImage!, size: CGSize(width: 10, height: 6))
        let normalizedRetina = retinaCapture.normalizedForEditing()
        precondition(normalizedRetina.size == CGSize(width: 10, height: 6))
        precondition(normalizedRetina.representations.first?.pixelsWide == 20)
        precondition(normalizedRetina.representations.first?.pixelsHigh == 12)

        // An image with no meaningful point size falls back to its pixel size.
        let oddScaleImage = NSImage(cgImage: highResolutionRep.cgImage!, size: CGSize(width: 13, height: 7))
        precondition(oddScaleImage.normalizedForEditing().size == CGSize(width: 20, height: 12))

        let expectedExportSize = CGSize(width: 1022, height: 659)
        guard let rendered = PixelExactImageRenderer.render(size: expectedExportSize, drawing: { bounds in
            NSColor.systemBlue.setFill()
            bounds.fill()
        }), let pngData = rendered.pngData(), let representation = NSBitmapImageRep(data: pngData) else {
            preconditionFailure("Could not render the export regression fixture")
        }
        precondition(representation.pixelsWide == 1022)
        precondition(representation.pixelsHigh == 659)

        print("Core logic smoke tests passed")
    }
}
