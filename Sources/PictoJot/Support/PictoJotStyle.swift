import AppKit

enum PictoJotStyle {
    /// Default annotation color: #FF4B7F.
    static let defaultAnnotationColor = NSColor(
        srgbRed: 1,
        green: 75 / 255,
        blue: 127 / 255,
        alpha: 1
    )

    static let selectionHandleColor = NSColor(
        srgbRed: 28 / 255,
        green: 168 / 255,
        blue: 214 / 255,
        alpha: 1
    )

    static let textOutlineColor = NSColor.white
    /// Positive values draw only the outline. The original fill is drawn over it separately.
    static let textOutlineWidth: CGFloat = 7
}
