import AppKit
import UniformTypeIdentifiers

extension NSImage {
    var cgImageValue: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    func pngData() -> Data? {
        guard let cgImage = cgImageValue else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }

    /// JPEG has no alpha, so transparent areas are flattened onto white rather
    /// than turning black. Keeps the full pixel size like `pngData()`.
    func jpegData(quality: CGFloat) -> Data? {
        guard let cgImage = cgImageValue else { return nil }
        let colorSpace = cgImage.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(cgImage, in: bounds)
        guard let flattened = context.makeImage() else { return nil }
        let representation = NSBitmapImageRep(cgImage: flattened)
        return representation.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Rebuilds the image around a single bitmap, keeping every pixel. `size`
    /// stays logical when the bitmap is a whole-number Retina multiple of it
    /// (2x captures, @2x files); otherwise odd DPI metadata is discarded and the
    /// pixel dimensions become the point size.
    func normalizedForEditing() -> NSImage {
        guard let cgImage = cgImageValue else { return self }
        let pixelSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        guard size.width > 0, size.height > 0 else {
            return NSImage(cgImage: cgImage, size: pixelSize)
        }
        let scale = (pixelSize.width / size.width).rounded()
        let matchesBothAxes = scale >= 1 && scale <= 4
            && abs(pixelSize.width / size.width - scale) < 0.01
            && abs(pixelSize.height / size.height - scale) < 0.01
        guard matchesBothAxes else { return NSImage(cgImage: cgImage, size: pixelSize) }
        return NSImage(
            cgImage: cgImage,
            size: CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
        )
    }

    static var supportedDropTypes: [UTType] {
        [.png, .jpeg, .heic, .tiff, .image]
    }
}
