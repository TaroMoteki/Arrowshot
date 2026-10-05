import AppKit
import Foundation

private struct IconVariant {
    let filename: String
    let pixels: Int
}

@main
private enum IconGenerator {
    private static let variants = [
        IconVariant(filename: "icon_16x16.png", pixels: 16),
        IconVariant(filename: "icon_16x16@2x.png", pixels: 32),
        IconVariant(filename: "icon_32x32.png", pixels: 32),
        IconVariant(filename: "icon_32x32@2x.png", pixels: 64),
        IconVariant(filename: "icon_128x128.png", pixels: 128),
        IconVariant(filename: "icon_128x128@2x.png", pixels: 256),
        IconVariant(filename: "icon_256x256.png", pixels: 256),
        IconVariant(filename: "icon_256x256@2x.png", pixels: 512),
        IconVariant(filename: "icon_512x512.png", pixels: 512),
        IconVariant(filename: "icon_512x512@2x.png", pixels: 1_024),
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw GeneratorError.usage
        }

        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var renderedImages: [Int: Data] = [:]
        for variant in variants {
            let data: Data
            if let existingData = renderedImages[variant.pixels] {
                data = existingData
            } else {
                data = try renderIcon(pixels: variant.pixels)
                renderedImages[variant.pixels] = data
            }
            try data.write(to: outputDirectory.appendingPathComponent(variant.filename), options: .atomic)
        }
    }

    private static func renderIcon(pixels: Int) throws -> Data {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixels * 4,
            bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
            throw GeneratorError.renderingFailed
        }

        representation.size = NSSize(width: pixels, height: pixels)
        let size = CGFloat(pixels)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()

        // Rounded-square (squircle) background, macOS Big Sur style, filling
        // most of the canvas with a small margin.
        let tileRect = NSRect(
            x: size * 0.085,
            y: size * 0.085,
            width: size * 0.83,
            height: size * 0.83
        )
        let tilePath = NSBezierPath(
            roundedRect: tileRect,
            xRadius: size * 0.2237,
            yRadius: size * 0.2237
        )

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.28)
        shadow.shadowBlurRadius = max(1.0, size * 0.03)
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.02)
        shadow.set()
        NSColor(srgbRed: 0.85, green: 0.11, blue: 0.38, alpha: 1.0).setFill()
        tilePath.fill()

        // Pink gradient fill (brighter at the top).
        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        let pinkGradient = NSGradient(
            starting: NSColor(srgbRed: 0.847, green: 0.106, blue: 0.376, alpha: 1.0), // bottom
            ending: NSColor(srgbRed: 1.0, green: 0.435, blue: 0.631, alpha: 1.0)       // top
        )
        pinkGradient?.draw(in: tileRect, angle: 90)

        // Subtle glossy highlight across the top half.
        let glossRect = NSRect(
            x: tileRect.minX,
            y: tileRect.midY,
            width: tileRect.width,
            height: tileRect.height / 2
        )
        let gloss = NSGradient(
            starting: NSColor(calibratedWhite: 1.0, alpha: 0.20),
            ending: NSColor(calibratedWhite: 1.0, alpha: 0.0)
        )
        gloss?.draw(in: glossRect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        drawViewfinder(in: NSRect(x: 0, y: 0, width: size, height: size), size: size)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw GeneratorError.encodingFailed
        }
        return data
    }

    /// Draws a white viewfinder: four rounded corner brackets framing a center
    /// crosshair — the classic "capture / screenshot" motif.
    private static func drawViewfinder(in canvas: NSRect, size: CGFloat) {
        let side = size * 0.46
        let frame = NSRect(
            x: canvas.midX - side / 2,
            y: canvas.midY - side / 2,
            width: side,
            height: side
        )
        let arm = side * 0.32
        let lineWidth = size * 0.062

        // Soft shadow to lift the marks off the pink background.
        NSGraphicsContext.saveGraphicsState()
        let markShadow = NSShadow()
        markShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.18)
        markShadow.shadowBlurRadius = max(0.5, size * 0.02)
        markShadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
        markShadow.set()

        NSColor.white.setStroke()

        let corners = NSBezierPath()
        corners.lineWidth = lineWidth
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round

        // Top-left
        corners.move(to: NSPoint(x: frame.minX, y: frame.maxY - arm))
        corners.line(to: NSPoint(x: frame.minX, y: frame.maxY))
        corners.line(to: NSPoint(x: frame.minX + arm, y: frame.maxY))
        // Top-right
        corners.move(to: NSPoint(x: frame.maxX - arm, y: frame.maxY))
        corners.line(to: NSPoint(x: frame.maxX, y: frame.maxY))
        corners.line(to: NSPoint(x: frame.maxX, y: frame.maxY - arm))
        // Bottom-right
        corners.move(to: NSPoint(x: frame.maxX, y: frame.minY + arm))
        corners.line(to: NSPoint(x: frame.maxX, y: frame.minY))
        corners.line(to: NSPoint(x: frame.maxX - arm, y: frame.minY))
        // Bottom-left
        corners.move(to: NSPoint(x: frame.minX + arm, y: frame.minY))
        corners.line(to: NSPoint(x: frame.minX, y: frame.minY))
        corners.line(to: NSPoint(x: frame.minX, y: frame.minY + arm))
        corners.stroke()

        // Center crosshair.
        let crossHalf = size * 0.075
        let crosshair = NSBezierPath()
        crosshair.lineWidth = size * 0.05
        crosshair.lineCapStyle = .round
        crosshair.move(to: NSPoint(x: canvas.midX - crossHalf, y: canvas.midY))
        crosshair.line(to: NSPoint(x: canvas.midX + crossHalf, y: canvas.midY))
        crosshair.move(to: NSPoint(x: canvas.midX, y: canvas.midY - crossHalf))
        crosshair.line(to: NSPoint(x: canvas.midX, y: canvas.midY + crossHalf))
        crosshair.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }
}

private enum GeneratorError: LocalizedError {
    case usage
    case renderingFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: IconGenerator <output-iconset-directory>"
        case .renderingFailed:
            return "Could not create an AppKit bitmap context."
        case .encodingFailed:
            return "Could not encode the generated icon as PNG."
        }
    }
}
