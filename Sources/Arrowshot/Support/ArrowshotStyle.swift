import AppKit

enum ArrowshotStyle {
    /// Default annotation color: red (#FF3B30).
    static let defaultAnnotationColor = NSColor(
        srgbRed: 1,
        green: 59 / 255,
        blue: 48 / 255,
        alpha: 1
    )

    static let selectionHandleColor = NSColor(
        srgbRed: 28 / 255,
        green: 168 / 255,
        blue: 214 / 255,
        alpha: 1
    )

    /// Mosaic block size in points. Small enough to stay legible as a redaction
    /// without reading as a coarse grid.
    static let mosaicBlockSize: CGFloat = 10

    static let textOutlineColor = NSColor.white
    /// Positive values draw only the outline. The original fill is drawn over it separately.
    /// Value is a percentage of the font size, so the halo scales with the text.
    static let textOutlineWidth: CGFloat = 16

    /// Drop shadow under arrows, matching Skitch. Values are in points at 1x
    /// and get multiplied by the render scale. The offset points straight down
    /// on screen.
    static let arrowShadowColor = NSColor.black.withAlphaComponent(0.3)
    static let arrowShadowOffset = CGSize(width: 0, height: 2)
    static let arrowShadowBlurRadius: CGFloat = 3

    /// Text's shadow is bigger and softer than the arrow's, and it scales with
    /// the font size rather than being a fixed number of points. Measured from
    /// Skitch: it falls about 18% of the font size below the glyphs and fades
    /// over roughly the same distance again. It is cast by the glyphs alone —
    /// the white halo is painted over it, which keeps the shadow from reading
    /// as a dark outline.
    static let textShadowColor = NSColor.black.withAlphaComponent(0.35)
    static let textShadowOffsetRatio: CGFloat = 0.18
    static let textShadowBlurRatio: CGFloat = 0.15
}
