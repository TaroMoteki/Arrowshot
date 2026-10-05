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
