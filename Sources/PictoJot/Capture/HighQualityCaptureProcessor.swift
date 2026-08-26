import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
enum HighQualityCaptureProcessor {
    private static let context = CIContext(options: [
        .cacheIntermediates: false
    ])

    /// Captures at the display's native backing resolution, then performs the
    /// logical-size conversion explicitly with a Lanczos filter. This is sharper
    /// than asking ScreenCaptureKit to emit the logical size directly.
    static func downsample(_ image: CGImage, toLogicalSize size: CGSize) -> NSImage {
        let target = CaptureOutputSizing.pixels(forLogicalSize: size)
        guard image.width != target.width || image.height != target.height else {
            return NSImage(cgImage: image, size: CGSize(width: target.width, height: target.height))
        }

        let scaleX = CGFloat(target.width) / CGFloat(image.width)
        let scaleY = CGFloat(target.height) / CGFloat(image.height)
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = CIImage(cgImage: image)
        filter.scale = Float(scaleY)
        filter.aspectRatio = Float(scaleX / scaleY)

        let targetRect = CGRect(x: 0, y: 0, width: target.width, height: target.height)
        guard let output = filter.outputImage?.cropped(to: targetRect),
              let rendered = context.createCGImage(output, from: targetRect) else {
            return quartzDownsample(image, width: target.width, height: target.height)
        }
        return NSImage(cgImage: rendered, size: CGSize(width: target.width, height: target.height))
    }

    private static func quartzDownsample(_ image: CGImage, width: Int, height: Int) -> NSImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let bitmap = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(cgImage: image, size: CGSize(width: width, height: height))
        }
        bitmap.interpolationQuality = .high
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rendered = bitmap.makeImage() else {
            return NSImage(cgImage: image, size: CGSize(width: width, height: height))
        }
        return NSImage(cgImage: rendered, size: CGSize(width: width, height: height))
    }
}
