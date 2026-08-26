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

    func normalizedToPixelSize() -> NSImage {
        guard let cgImage = cgImageValue else { return self }
        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }

    static var supportedDropTypes: [UTType] {
        [.png, .jpeg, .heic, .tiff, .image]
    }
}
