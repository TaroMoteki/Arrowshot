import AppKit
import CoreText

/// Draws one countdown digit as a black number with a thin white outline.
/// The outline is stroked from the glyph path with round joins so sharp glyph
/// corners (like "2") don't produce spikes.
private final class CountdownDigitView: NSView {
    var value: Int = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 96, weight: .heavy)
        let attributed = NSAttributedString(string: "\(value)", attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)

        let glyphPath = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let runFont = font as CTFont
            for index in 0..<count {
                guard let letter = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
                let transform = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                glyphPath.addPath(letter, transform: transform)
            }
        }

        let box = glyphPath.boundingBoxOfPath
        guard box.width > 0, box.height > 0 else { return }
        let centered = CGMutablePath()
        centered.addPath(
            glyphPath,
            transform: CGAffineTransform(
                translationX: bounds.midX - box.midX,
                y: bounds.midY - box.midY
            )
        )

        context.setLineJoin(.round)
        context.setLineCap(.round)
        // White outline (round joins avoid spikes), then black fill on top.
        context.addPath(centered)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(5)
        context.strokePath()
        context.addPath(centered)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
    }
}

@MainActor
final class CountdownPresenter {
    private var window: NSWindow?
    private let digitView = CountdownDigitView()

    func run(centeredOn quartzRect: CGRect, seconds: Int = 5) async throws {
        let total = max(1, seconds)
        let cocoaRect = ScreenCoordinates.quartzRectToCocoa(quartzRect)
        let size = CGSize(width: 140, height: 140)
        let frame = CGRect(
            x: cocoaRect.midX - size.width / 2,
            y: cocoaRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        digitView.frame = CGRect(origin: .zero, size: size)
        digitView.value = total
        window.contentView = digitView
        self.window = window
        window.orderFrontRegardless()

        do {
            for count in stride(from: total, through: 1, by: -1) {
                digitView.value = count
                try await Task.sleep(for: .seconds(1))
            }
            window.orderOut(nil)
            self.window = nil
        } catch {
            window.orderOut(nil)
            self.window = nil
            throw error
        }
    }
}
