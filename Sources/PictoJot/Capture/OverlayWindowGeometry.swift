import CoreGraphics

enum OverlayWindowGeometry {
    /// `NSWindow.init(..., screen:)` expects its origin relative to the supplied
    /// screen. Passing `NSScreen.frame.origin` offsets secondary screens twice.
    static func contentRect(forScreenFrame screenFrame: CGRect) -> CGRect {
        CGRect(origin: .zero, size: screenFrame.size)
    }
}
