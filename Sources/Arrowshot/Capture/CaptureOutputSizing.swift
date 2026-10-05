import CoreGraphics

enum CaptureOutputSizing {
    /// ScreenCaptureKit receives output dimensions in pixels. Use the selected logical
    /// point size so Retina scaling is not applied twice during file export.
    static func pixels(forLogicalSize size: CGSize) -> (width: Int, height: Int) {
        (
            width: max(1, Int(size.width.rounded())),
            height: max(1, Int(size.height.rounded()))
        )
    }

    static func nativePixels(forLogicalSize size: CGSize, pointPixelScale: CGFloat) -> (width: Int, height: Int) {
        let scale = max(1, pointPixelScale)
        return (
            width: max(1, Int((size.width * scale).rounded())),
            height: max(1, Int((size.height * scale).rounded()))
        )
    }
}
