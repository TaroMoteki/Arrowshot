import AppKit

enum PixelExactImageRenderer {
    /// Creates a bitmap whose pixel dimensions exactly match `size`, independent
    /// of the current display's Retina backing scale.
    static func render(size: CGSize, drawing: (_ bounds: CGRect) -> Void) -> NSImage? {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let bitmapContext = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }

        representation.size = CGSize(width: width, height: height)
        let cgContext = bitmapContext.cgContext
        cgContext.saveGState()
        cgContext.translateBy(x: 0, y: CGFloat(height))
        cgContext.scaleBy(x: 1, y: -1)

        let flippedContext = NSGraphicsContext(cgContext: cgContext, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = flippedContext
        drawing(CGRect(x: 0, y: 0, width: width, height: height))
        flippedContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        cgContext.restoreGState()

        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
