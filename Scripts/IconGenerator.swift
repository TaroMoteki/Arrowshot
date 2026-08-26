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

        let tileRect = NSRect(
            x: size * 0.065,
            y: size * 0.075,
            width: size * 0.87,
            height: size * 0.87
        )
        let tilePath = NSBezierPath(
            roundedRect: tileRect,
            xRadius: size * 0.20,
            yRadius: size * 0.20
        )

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.28)
        shadow.shadowBlurRadius = max(1.0, size * 0.035)
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.025)
        shadow.set()
        NSColor(calibratedWhite: 0.68, alpha: 1.0).setFill()
        tilePath.fill()

        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        let tileGradient = NSGradient(
            starting: NSColor(calibratedWhite: 0.96, alpha: 1.0),
            ending: NSColor(calibratedWhite: 0.77, alpha: 1.0)
        )
        tileGradient?.draw(in: tileRect, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        let circleRect = NSRect(
            x: size * 0.195,
            y: size * 0.205,
            width: size * 0.61,
            height: size * 0.61
        )
        let circlePath = NSBezierPath(ovalIn: circleRect)
        let circleShadow = NSShadow()
        circleShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.20)
        circleShadow.shadowBlurRadius = max(0.5, size * 0.018)
        circleShadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
        circleShadow.set()
        NSColor(calibratedRed: 1.0, green: 0.22, blue: 0.43, alpha: 1.0).setFill()
        circlePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        circlePath.addClip()
        let pinkGradient = NSGradient(
            starting: NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.55, alpha: 1.0),
            ending: NSColor(calibratedRed: 0.88, green: 0.08, blue: 0.31, alpha: 1.0)
        )
        pinkGradient?.draw(in: circleRect, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        drawLetter(in: NSRect(x: 0, y: 0, width: size, height: size), size: size)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw GeneratorError.encodingFailed
        }
        return data
    }

    private static func drawLetter(in canvas: NSRect, size: CGFloat) {
        let baseFont = NSFont.systemFont(ofSize: size * 0.47, weight: .heavy)
        let descriptor = baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor
        let font = NSFont(descriptor: descriptor, size: size * 0.47) ?? baseFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let letter = NSAttributedString(string: "p", attributes: attributes)
        let bounds = letter.boundingRect(
            with: NSSize(width: size, height: size),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let origin = NSPoint(
            x: canvas.midX - bounds.width / 2 - bounds.minX + size * 0.018,
            y: canvas.midY - bounds.height / 2 - bounds.minY + size * 0.060
        )
        letter.draw(at: origin)
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
