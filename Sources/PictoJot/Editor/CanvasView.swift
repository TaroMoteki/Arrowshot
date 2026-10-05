import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

@MainActor
protocol CanvasViewDelegate: AnyObject {
    func canvasView(_ canvasView: CanvasView, didReceiveImageAt url: URL)
    func canvasViewDidChangeContent(_ canvasView: CanvasView)
    func canvasView(_ canvasView: CanvasView, didUpdateCropRect rect: CGRect?)
}

private final class InlineInputTextView: NSTextView {
    var inputDidUpdate: (() -> Void)?
    /// Called for ⌘Return / ⌘Enter to commit the text.
    var onCommitRequested: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleCommitKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleCommitKey(event) { return }
        super.keyDown(with: event)
    }

    private func handleCommitKey(_ event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.keyCode == 36 || event.keyCode == 76,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              !hasMarkedText() else { return false }
        onCommitRequested?()
        return true
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        inputDidUpdate?()
    }

    override func unmarkText() {
        super.unmarkText()
        inputDidUpdate?()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        inputDidUpdate?()
    }
}

private final class InlineTextEditor: NSView {
    let textView = InlineInputTextView(frame: .zero)
    var guideColor: NSColor = PictoJotStyle.selectionHandleColor

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = CGSize(width: 1_000_000, height: 1_000_000)
        textView.insertionPointColor = guideColor
        addSubview(textView)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let font = textView.font {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .strokeColor: PictoJotStyle.textOutlineColor,
                .strokeWidth: PictoJotStyle.textOutlineWidth
            ]
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            for (lineIndex, line) in textView.string.components(separatedBy: "\n").enumerated() {
                (line as NSString).draw(
                    at: CGPoint(x: 6, y: 4 + CGFloat(lineIndex) * lineHeight),
                    withAttributes: attributes
                )
            }
        }
        guideColor.setStroke()
        let guides = NSBezierPath()
        guides.lineWidth = 2
        guides.move(to: CGPoint(x: 1, y: 2))
        guides.line(to: CGPoint(x: 1, y: bounds.maxY - 2))
        guides.move(to: CGPoint(x: bounds.maxX - 1, y: 2))
        guides.line(to: CGPoint(x: bounds.maxX - 1, y: bounds.maxY - 2))
        guides.stroke()
    }
}

final class CanvasView: NSView, NSTextViewDelegate {
    weak var delegate: CanvasViewDelegate?

    private(set) var baseImage: NSImage?
    private(set) var annotations: [Annotation] = []
    private(set) var selectedAnnotationID: UUID?

    var tool: EditorTool = .arrow {
        didSet {
            previewAnnotation = nil
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var currentColor: NSColor = PictoJotStyle.defaultAnnotationColor
    var currentLineWidth: CGFloat = 6
    /// When true, new rectangles/ellipses are filled instead of outlined.
    var currentFilled = false
    /// The most recent text size the user set by dragging a text handle, kept so
    /// the next new text starts at that size. Reset per image (new capture) and
    /// when the width control explicitly changes the size.
    private var currentTextSize: CGFloat?
    let editingUndoManager = UndoManager()

    private var previewAnnotation: Annotation?
    private var dragStart: CGPoint?
    private var dragStartInView: CGPoint?
    private var originalAnnotation: Annotation?
    private var stateBeforeDrag: EditorSnapshot?
    private var selectionDragMode: SelectionDragMode?
    private var didChangeDuringDrag = false
    private var pixelatedImageCache: NSImage?
    private var pointerTrackingArea: NSTrackingArea?
    private var inlineTextEditor: InlineTextEditor?
    private var textEditingSession: TextEditingSession?
    private var cropSelectionRect: CGRect?
    private var cropDragEdges: CropEdges = []
    private var originalCropRect: CGRect?
    /// Frozen image layout during an active crop drag, so the mapping does not
    /// shift under the cursor while the crop grows beyond the image.
    private var frozenImageRect: CGRect?

    /// View zoom (1 = fit to window) and pan offset in view points.
    private var zoomFactor: CGFloat = 1
    private var panOffset: CGPoint = .zero
    private let maxZoomFactor: CGFloat = 8
    /// Reports the current on-screen scale as a percentage of the image's pixels.
    var onZoomChanged: ((Int) -> Void)?

    private enum SelectionDragMode {
        case move
        case rotate(AnnotationCorner?)
        case endpoint(AnnotationEndpoint)
        case resize(AnnotationCorner)
        case textResize
    }

    private struct EditorSnapshot {
        let image: NSImage?
        let annotations: [Annotation]
        let selectedID: UUID?
    }

    private struct TextEditingSession {
        let origin: CGPoint
        let before: EditorSnapshot
        let insertionIndex: Int?
        let originalAnnotation: Annotation?
        let color: NSColor
        let lineWidth: CGFloat
        let fontSize: CGFloat
    }

    private struct CropEdges: OptionSet {
        let rawValue: Int

        static let top = CropEdges(rawValue: 1 << 0)
        static let left = CropEdges(rawValue: 1 << 1)
        static let bottom = CropEdges(rawValue: 1 << 2)
        static let right = CropEdges(rawValue: 1 << 3)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Since the macOS 14 SDK, views no longer clip drawing to their bounds by
        // default. Without this, a zoomed-in image spills over the toolbar and
        // sidebar and hides their buttons.
        clipsToBounds = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    func loadImage(_ image: NSImage) {
        finishInlineTextEditing(commit: false)
        baseImage = image.normalizedForEditing()
        annotations = []
        currentTextSize = nil
        selectedAnnotationID = nil
        previewAnnotation = nil
        pixelatedImageCache = nil
        editingUndoManager.removeAllActions()
        cropSelectionRect = nil
        frozenImageRect = nil
        zoomFactor = 1
        panOffset = .zero
        if tool == .crop {
            beginCropSelection()
        }
        needsDisplay = true
        notifyZoomChanged()
    }

    func clear() {
        finishInlineTextEditing(commit: false)
        baseImage = nil
        annotations = []
        selectedAnnotationID = nil
        pixelatedImageCache = nil
        cropSelectionRect = nil
        delegate?.canvasView(self, didUpdateCropRect: nil)
        editingUndoManager.removeAllActions()
        needsDisplay = true
    }

    func setColor(_ color: NSColor) {
        currentColor = color
        guard let index = selectedIndex, annotations[index].kind != .mosaic else { return }
        let before = snapshot()
        annotations[index].color = color
        registerUndo(to: before, actionName: "色を変更")
        contentDidChange()
    }

    func setLineWidth(_ width: CGFloat) {
        currentLineWidth = width
        // The width control explicitly sets text size, so drop the remembered
        // drag size and let new text follow the width-derived default again.
        currentTextSize = nil
        guard let index = selectedIndex, annotations[index].kind != .mosaic else { return }
        let before = snapshot()
        annotations[index].lineWidth = width
        if annotations[index].kind == .text {
            annotations[index].textSize = defaultTextFontSize(for: width)
            resizeTextBounds(at: index)
        }
        registerUndo(to: before, actionName: "太さを変更")
        contentDidChange()
    }

    func setFilled(_ filled: Bool) {
        currentFilled = filled
        guard let index = selectedIndex,
              annotations[index].kind == .rectangle || annotations[index].kind == .ellipse else { return }
        let before = snapshot()
        annotations[index].filled = filled
        registerUndo(to: before, actionName: "塗りつぶしを変更")
        contentDidChange()
    }

    func selectTool(_ newTool: EditorTool) {
        finishInlineTextEditing(commit: true)
        if newTool == tool {
            if newTool == .crop, cropSelectionRect == nil {
                beginCropSelection()
            }
            window?.makeFirstResponder(self)
            return
        }
        if tool == .crop, newTool != .crop {
            cancelCropSelection()
        }
        tool = newTool
        if newTool == .crop {
            beginCropSelection()
        }
        window?.makeFirstResponder(self)
    }

    func applyCropSelection() {
        guard let crop = cropSelectionRect, baseImage != nil else { return }
        let before = snapshot()
        cropSelectionRect = nil
        cropDragEdges = []
        originalCropRect = nil
        frozenImageRect = nil
        applyCrop(crop)
        registerUndo(to: before, actionName: "画像を切り取り")
        delegate?.canvasView(self, didUpdateCropRect: nil)
        contentDidChange()
    }

    func cancelCropSelection() {
        cropSelectionRect = nil
        cropDragEdges = []
        originalCropRect = nil
        frozenImageRect = nil
        delegate?.canvasView(self, didUpdateCropRect: nil)
        needsDisplay = true
    }

    func undoEdit() {
        editingUndoManager.undo()
    }

    func redoEdit() {
        editingUndoManager.redo()
    }

    /// How many bitmap pixels the base image holds per point (2 for a Retina
    /// capture). Annotations live in points, so exports scale by this.
    private var basePixelScale: CGFloat {
        guard let baseImage, baseImage.size.width > 0, let cgImage = baseImage.cgImageValue else { return 1 }
        return max(1, CGFloat(cgImage.width) / baseImage.size.width)
    }

    func renderedImage() -> NSImage? {
        finishInlineTextEditing(commit: true)
        guard let baseImage else { return nil }
        // Export at the captured resolution, not at the point size, so Retina
        // captures keep every pixel they were taken with.
        let scale = basePixelScale
        let pixelSize = CGSize(
            width: (baseImage.size.width * scale).rounded(),
            height: (baseImage.size.height * scale).rounded()
        )
        return PixelExactImageRenderer.render(size: pixelSize) { targetRect in
            baseImage.draw(in: targetRect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            drawAnnotationLayers(annotations, in: targetRect, imageScale: scale)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        guard let baseImage else {
            drawEmptyState()
            return
        }

        let targetRect = imageRect(for: baseImage)
        let scale = targetRect.width / baseImage.size.width

        // When the crop extends past the image, show the expansion area as white
        // (it becomes white in the final image).
        if let cropSelectionRect {
            let cropView = map(cropSelectionRect, into: targetRect, scale: scale)
            NSColor.shadowColor.withAlphaComponent(0.25).setFill()
            cropView.insetBy(dx: -1, dy: -1).fill()
            NSColor.white.setFill()
            cropView.fill()
        }

        NSColor.shadowColor.withAlphaComponent(0.25).setFill()
        targetRect.insetBy(dx: -1, dy: -1).fill()
        baseImage.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        var displayedAnnotations = annotations
        if let previewAnnotation {
            displayedAnnotations.append(previewAnnotation)
        }
        drawAnnotationLayers(displayedAnnotations, in: targetRect, imageScale: scale)
        if let cropSelectionRect {
            drawCropSelection(cropSelectionRect, in: targetRect, imageScale: scale)
        } else if let index = selectedIndex {
            drawSelection(for: annotations[index], in: targetRect, imageScale: scale)
        }
    }

    private func drawEmptyState() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let message = "画像をここへドロップ\nまたはメニューバーからキャプチャ"
        let rect = CGRect(x: bounds.midX - 220, y: bounds.midY - 35, width: 440, height: 70)
        message.draw(in: rect, withAttributes: attributes)
    }

    private func drawAnnotationLayers(_ values: [Annotation], in targetRect: CGRect, imageScale: CGFloat) {
        for annotation in values where annotation.kind == .mosaic {
            draw(annotation, in: targetRect, imageScale: imageScale)
        }
        for annotation in values where annotation.kind != .mosaic {
            draw(annotation, in: targetRect, imageScale: imageScale)
        }
    }

    private func beginCropSelection() {
        guard let baseImage else {
            cropSelectionRect = nil
            delegate?.canvasView(self, didUpdateCropRect: nil)
            return
        }
        finishInlineTextEditing(commit: true)
        selectedAnnotationID = nil
        previewAnnotation = nil
        cropSelectionRect = CGRect(origin: .zero, size: baseImage.size)
        cropDragEdges = []
        originalCropRect = nil
        frozenImageRect = nil
        delegate?.canvasView(self, didUpdateCropRect: cropSelectionRect)
        needsDisplay = true
    }

    private func drawCropSelection(_ crop: CGRect, in targetRect: CGRect, imageScale: CGFloat) {
        let cropRect = map(crop, into: targetRect, scale: imageScale).intersection(targetRect)
        let shade = NSColor.black.withAlphaComponent(0.48)
        shade.setFill()
        for rect in [
            CGRect(x: targetRect.minX, y: targetRect.minY, width: targetRect.width, height: max(0, cropRect.minY - targetRect.minY)),
            CGRect(x: targetRect.minX, y: cropRect.maxY, width: targetRect.width, height: max(0, targetRect.maxY - cropRect.maxY)),
            CGRect(x: targetRect.minX, y: cropRect.minY, width: max(0, cropRect.minX - targetRect.minX), height: cropRect.height),
            CGRect(x: cropRect.maxX, y: cropRect.minY, width: max(0, targetRect.maxX - cropRect.maxX), height: cropRect.height)
        ] where rect.width > 0 && rect.height > 0 {
            rect.fill()
        }

        let outline = NSBezierPath(rect: cropRect)
        outline.lineWidth = 1
        NSColor.white.setStroke()
        outline.stroke()

        let handlePoints = [
            CGPoint(x: cropRect.minX, y: cropRect.minY),
            CGPoint(x: cropRect.midX, y: cropRect.minY),
            CGPoint(x: cropRect.maxX, y: cropRect.minY),
            CGPoint(x: cropRect.minX, y: cropRect.midY),
            CGPoint(x: cropRect.maxX, y: cropRect.midY),
            CGPoint(x: cropRect.minX, y: cropRect.maxY),
            CGPoint(x: cropRect.midX, y: cropRect.maxY),
            CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        ]
        for point in handlePoints {
            let handleRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            handleRect.fill()
            NSColor.gray.setStroke()
            NSBezierPath(rect: handleRect).stroke()
        }
    }

    private func beginCropResize(at viewPoint: CGPoint) {
        guard let cropSelectionRect else { return }
        let edges = cropEdges(at: viewPoint, crop: cropSelectionRect)
        cropDragEdges = edges
        originalCropRect = edges.isEmpty ? nil : cropSelectionRect
        setCropCursor(for: edges)
    }

    private func updateCropResize(to point: CGPoint) {
        guard !cropDragEdges.isEmpty, let originalCropRect, let baseImage else { return }
        let minimumSize: CGFloat = 12
        // Allow the crop to extend beyond the image (expansion, filled white),
        // capped at one extra image-size of white margin on each side.
        let lowerX = -baseImage.size.width
        let upperX = baseImage.size.width * 2
        let lowerY = -baseImage.size.height
        let upperY = baseImage.size.height * 2
        var minX = originalCropRect.minX
        var maxX = originalCropRect.maxX
        var minY = originalCropRect.minY
        var maxY = originalCropRect.maxY

        if cropDragEdges.contains(.left) {
            minX = min(max(lowerX, point.x), maxX - minimumSize)
        }
        if cropDragEdges.contains(.right) {
            maxX = max(min(upperX, point.x), minX + minimumSize)
        }
        if cropDragEdges.contains(.top) {
            minY = min(max(lowerY, point.y), maxY - minimumSize)
        }
        if cropDragEdges.contains(.bottom) {
            maxY = max(min(upperY, point.y), minY + minimumSize)
        }

        cropSelectionRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        delegate?.canvasView(self, didUpdateCropRect: cropSelectionRect)
        setCropCursor(for: cropDragEdges)
        needsDisplay = true
    }

    private func cropEdges(at viewPoint: CGPoint, crop: CGRect) -> CropEdges {
        guard let baseImage else { return [] }
        let targetRect = imageRect(for: baseImage)
        let scale = targetRect.width / baseImage.size.width
        let rect = map(crop, into: targetRect, scale: scale)
        let tolerance: CGFloat = 9
        var edges: CropEdges = []

        if viewPoint.x >= rect.minX - tolerance, viewPoint.x <= rect.maxX + tolerance {
            if abs(viewPoint.y - rect.minY) <= tolerance { edges.insert(.top) }
            if abs(viewPoint.y - rect.maxY) <= tolerance { edges.insert(.bottom) }
        }
        if viewPoint.y >= rect.minY - tolerance, viewPoint.y <= rect.maxY + tolerance {
            if abs(viewPoint.x - rect.minX) <= tolerance { edges.insert(.left) }
            if abs(viewPoint.x - rect.maxX) <= tolerance { edges.insert(.right) }
        }
        return edges
    }

    private func setCropCursor(for edges: CropEdges) {
        let horizontal = edges.contains(.left) || edges.contains(.right)
        let vertical = edges.contains(.top) || edges.contains(.bottom)
        if horizontal && vertical {
            EditorCursors.fourWayResize.set()
        } else if horizontal {
            NSCursor.resizeLeftRight.set()
        } else if vertical {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func draw(_ annotation: Annotation, in targetRect: CGRect, imageScale: CGFloat) {
        if annotation.kind == .mosaic {
            guard let pixelatedImage = pixelatedBaseImage() else { return }
            NSGraphicsContext.saveGraphicsState()
            let clipRect = map(annotation.rect, into: targetRect, scale: imageScale)
            NSBezierPath(rect: clipRect).addClip()
            pixelatedImage.draw(in: targetRect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        let center = map(annotation.center, into: targetRect, scale: imageScale)
        NSGraphicsContext.saveGraphicsState()
        if annotation.rotation != 0, let context = NSGraphicsContext.current?.cgContext {
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: annotation.rotation)
            context.translateBy(x: -center.x, y: -center.y)
        }

        annotation.color.setStroke()
        annotation.color.setFill()
        let lineWidth = max(1, annotation.lineWidth * imageScale)

        switch annotation.kind {
        case .arrow:
            let start = map(annotation.start, into: targetRect, scale: imageScale)
            let end = map(annotation.end, into: targetRect, scale: imageScale)
            drawFilledArrow(
                from: start,
                to: end,
                color: annotation.color,
                lineWidth: lineWidth,
                shadowScale: imageScale
            )
        case .line:
            let start = map(annotation.start, into: targetRect, scale: imageScale)
            let end = map(annotation.end, into: targetRect, scale: imageScale)
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .rectangle:
            let path = NSBezierPath(rect: map(annotation.rect, into: targetRect, scale: imageScale))
            path.lineWidth = lineWidth
            path.lineJoinStyle = .round
            if annotation.filled {
                path.fill()
            } else {
                path.stroke()
            }
        case .ellipse:
            let path = NSBezierPath(ovalIn: map(annotation.rect, into: targetRect, scale: imageScale))
            path.lineWidth = lineWidth
            if annotation.filled {
                path.fill()
            } else {
                path.stroke()
            }
        case .text:
            let mappedRect = map(annotation.rect, into: targetRect, scale: imageScale)
            let fontSize = max(1, effectiveTextFontSize(for: annotation) * imageScale)
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let outlineAttributes = textOutlineDrawingAttributes(font: font)
            let fillAttributes = textDrawingAttributes(font: font, color: annotation.color)
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            for (lineIndex, line) in annotation.text.components(separatedBy: "\n").enumerated() {
                let point = CGPoint(x: mappedRect.minX, y: mappedRect.minY + CGFloat(lineIndex) * lineHeight)
                // Three passes, as Skitch does it: the glyphs cast the shadow,
                // then the white halo paints over its near edge, then the fill.
                withTextShadow(fontSize: fontSize) {
                    (line as NSString).draw(
                        at: point,
                        withAttributes: fillAttributes
                    )
                }
                (line as NSString).draw(
                    at: point,
                    withAttributes: outlineAttributes
                )
                (line as NSString).draw(
                    at: point,
                    withAttributes: fillAttributes
                )
            }
        case .mosaic:
            break
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawFilledArrow(
        from start: CGPoint,
        to end: CGPoint,
        color: NSColor,
        lineWidth: CGFloat,
        shadowScale: CGFloat
    ) {
        let points = ArrowGeometry.points(from: start, to: end, lineWidth: lineWidth)
        guard let firstPoint = points.first else { return }
        let arrow = NSBezierPath()
        arrow.move(to: firstPoint)
        for point in points.dropFirst() {
            arrow.line(to: point)
        }
        arrow.close()
        arrow.lineJoinStyle = .round
        // Like Skitch: no outline, just the solid shape over a soft drop shadow.
        withArrowShadow(scale: shadowScale) {
            color.setFill()
            arrow.fill()
        }
    }

    /// Runs `body` with the arrow's drop shadow, scaled to the current render
    /// scale so display and export match.
    private func withArrowShadow(scale: CGFloat, _ body: () -> Void) {
        withShadow(
            color: PictoJotStyle.arrowShadowColor,
            offsetDown: PictoJotStyle.arrowShadowOffset.height * scale,
            offsetRight: PictoJotStyle.arrowShadowOffset.width * scale,
            blurRadius: PictoJotStyle.arrowShadowBlurRadius * scale,
            body
        )
    }

    /// Runs `body` with the text's drop shadow. `fontSize` is the already
    /// scaled on-screen size, so the shadow grows with both the text size and
    /// the render scale.
    private func withTextShadow(fontSize: CGFloat, _ body: () -> Void) {
        withShadow(
            color: PictoJotStyle.textShadowColor,
            offsetDown: fontSize * PictoJotStyle.textShadowOffsetRatio,
            offsetRight: 0,
            blurRadius: fontSize * PictoJotStyle.textShadowBlurRatio,
            body
        )
    }

    private func withShadow(
        color: NSColor,
        offsetDown: CGFloat,
        offsetRight: CGFloat,
        blurRadius: CGFloat,
        _ body: () -> Void
    ) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color
        // AppKit keeps shadow offsets in the unflipped base space even inside a
        // flipped context, so "down on screen" is always a negative y here.
        shadow.shadowOffset = CGSize(width: offsetRight, height: -offsetDown)
        shadow.shadowBlurRadius = blurRadius
        shadow.set()
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelection(for annotation: Annotation, in targetRect: CGRect, imageScale: CGFloat) {
        guard annotation.kind != .mosaic else { return }
        if annotation.kind == .arrow || annotation.kind == .line {
            drawEndpointHandle(at: map(annotation.displayedStart, into: targetRect, scale: imageScale))
            drawEndpointHandle(at: map(annotation.displayedEnd, into: targetRect, scale: imageScale))
            return
        }
        if annotation.kind == .rectangle || annotation.kind == .ellipse {
            drawShapeSelection(for: annotation, in: targetRect, imageScale: imageScale)
            return
        }
        if annotation.kind == .text {
            drawTextSelection(for: annotation, in: targetRect, imageScale: imageScale)
            return
        }
        let center = map(annotation.center, into: targetRect, scale: imageScale)
        let mappedBounds = map(annotation.bounds, into: targetRect, scale: imageScale)
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext.current?.cgContext {
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: annotation.rotation)
            context.translateBy(x: -center.x, y: -center.y)
        }

        let outline = NSBezierPath(rect: mappedBounds)
        outline.setLineDash([5, 4], count: 2, phase: 0)
        outline.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        outline.stroke()

        let handleSize: CGFloat = 8
        for point in [
            CGPoint(x: mappedBounds.minX, y: mappedBounds.minY),
            CGPoint(x: mappedBounds.maxX, y: mappedBounds.minY),
            CGPoint(x: mappedBounds.minX, y: mappedBounds.maxY),
            CGPoint(x: mappedBounds.maxX, y: mappedBounds.maxY)
        ] {
            let handle = CGRect(x: point.x - handleSize / 2, y: point.y - handleSize / 2, width: handleSize, height: handleSize)
            NSColor.white.setFill()
            handle.fill()
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(rect: handle).stroke()
        }

        let rotationPoint = CGPoint(x: mappedBounds.midX, y: mappedBounds.minY - 24)
        let stem = NSBezierPath()
        stem.move(to: CGPoint(x: mappedBounds.midX, y: mappedBounds.minY))
        stem.line(to: rotationPoint)
        stem.lineWidth = 1
        stem.stroke()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(x: rotationPoint.x - 5, y: rotationPoint.y - 5, width: 10, height: 10)).fill()
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(ovalIn: CGRect(x: rotationPoint.x - 5, y: rotationPoint.y - 5, width: 10, height: 10)).stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawEndpointHandle(at point: CGPoint) {
        let handleRect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
        NSColor.white.setStroke()
        PictoJotStyle.selectionHandleColor.setFill()
        let handle = NSBezierPath(ovalIn: handleRect)
        handle.lineWidth = 1.5
        handle.fill()
        handle.stroke()
    }

    private func drawShapeSelection(for annotation: Annotation, in targetRect: CGRect, imageScale: CGFloat) {
        let center = map(annotation.center, into: targetRect, scale: imageScale)
        let mappedRect = map(annotation.rect, into: targetRect, scale: imageScale)
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext.current?.cgContext {
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: annotation.rotation)
            context.translateBy(x: -center.x, y: -center.y)
        }
        let outline = annotation.kind == .ellipse
            ? NSBezierPath(ovalIn: mappedRect)
            : NSBezierPath(rect: mappedRect)
        outline.lineWidth = 1.5
        PictoJotStyle.selectionHandleColor.setStroke()
        outline.stroke()
        NSGraphicsContext.restoreGraphicsState()

        for corner in AnnotationCorner.allCases {
            drawEndpointHandle(
                at: map(annotation.displayedCorner(corner), into: targetRect, scale: imageScale)
            )
        }
    }

    private func drawTextSelection(for annotation: Annotation, in targetRect: CGRect, imageScale: CGFloat) {
        let mappedRect = map(annotation.rect, into: targetRect, scale: imageScale)
        let outline = NSBezierPath(rect: mappedRect)
        outline.lineWidth = 1.5
        PictoJotStyle.selectionHandleColor.setStroke()
        outline.stroke()
        drawEndpointHandle(at: CGPoint(x: mappedRect.maxX, y: mappedRect.maxY))
    }

    private func beginAnnotationInteraction(
        at viewPoint: CGPoint,
        imagePoint: CGPoint,
        clickCount: Int
    ) -> Bool {
        if clickCount >= 2,
           let index = hitAnnotation(at: imagePoint),
           annotations[index].kind == .text {
            beginInlineTextEditing(annotationAt: index)
            return true
        }
        if let index = selectedIndex,
           let endpoint = endpointHandleHit(at: viewPoint, annotation: annotations[index]) {
            var flattened = annotations[index]
            flattened.flattenLineRotation()
            annotations[index] = flattened
            originalAnnotation = flattened
            selectionDragMode = .endpoint(endpoint)
            NSCursor.crosshair.set()
            return true
        }
        if let index = selectedIndex,
           textResizeHandleHit(at: viewPoint, annotation: annotations[index]) {
            originalAnnotation = annotations[index]
            selectionDragMode = .textResize
            EditorCursors.fourWayResize.set()
            return true
        }
        if let index = selectedIndex,
           let corner = shapeHandleHit(at: viewPoint, annotation: annotations[index]) {
            originalAnnotation = annotations[index]
            selectionDragMode = .resize(corner)
            EditorCursors.fourWayResize.set()
            return true
        }
        if let index = selectedIndex,
           let corner = shapeRotationZoneHit(at: viewPoint, annotation: annotations[index]) {
            originalAnnotation = annotations[index]
            selectionDragMode = .rotate(corner)
            EditorCursors.rotation(angle: rotationCursorAngle(for: corner, annotation: annotations[index])).set()
            return true
        }
        if let index = selectedIndex, isRotationHandleHit(viewPoint, annotation: annotations[index]) {
            originalAnnotation = annotations[index]
            selectionDragMode = .rotate(nil)
            NSCursor.crosshair.set()
            return true
        }
        guard let index = hitAnnotation(at: imagePoint) else { return false }
        selectedAnnotationID = annotations[index].id
        originalAnnotation = annotations[index]
        selectionDragMode = .move
        EditorCursors.fourWayResize.set()
        needsDisplay = true
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard let baseImage else { return }
        // Clicking away from an open text box only finishes it (like Skitch);
        // the next click starts a new one. Otherwise a fresh empty box would
        // swallow tool shortcut keys such as R.
        // AppKit moves focus to the canvas (ending the edit) before mouseDown
        // runs, so also check whether this very click is what ended it.
        let wasEditingText = inlineTextEditor != nil
            || textEditEndedByMouseDownTimestamp == event.timestamp
        textEditEndedByMouseDownTimestamp = nil
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        if tool == .crop {
            let edges = cropSelectionRect.map { cropEdges(at: viewPoint, crop: $0) } ?? []
            // Allow grabbing a handle even when it sits outside the image (an
            // already-expanded crop); otherwise require a click near the image.
            if edges.isEmpty {
                guard imageRect(for: baseImage).insetBy(dx: -12, dy: -12).contains(viewPoint) else { return }
            }
            // Freeze the layout for the duration of the drag so the mapping is
            // stable while the crop grows beyond the image.
            frozenImageRect = imageRect(for: baseImage)
            dragStart = rawImagePoint(from: viewPoint, image: baseImage)
            dragStartInView = viewPoint
            didChangeDuringDrag = false
            selectionDragMode = nil
            stateBeforeDrag = nil
            beginCropResize(at: viewPoint)
            return
        }
        guard let imagePoint = imagePoint(from: viewPoint, image: baseImage) else { return }
        dragStart = imagePoint
        dragStartInView = viewPoint
        didChangeDuringDrag = false
        selectionDragMode = nil
        stateBeforeDrag = snapshot()

        if beginAnnotationInteraction(
            at: viewPoint,
            imagePoint: imagePoint,
            clickCount: event.clickCount
        ) {
            return
        }

        selectedAnnotationID = nil
        originalAnnotation = nil
        needsDisplay = true
        switch tool {
        case .text:
            if !wasEditingText {
                beginInlineTextEditing(at: imagePoint)
            }
        default:
            previewAnnotation = makeAnnotation(for: tool, from: imagePoint, to: imagePoint)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let baseImage, let dragStart else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)

        if tool == .crop {
            updateCropResize(to: rawImagePoint(from: viewPoint, image: baseImage))
            return
        }
        let imagePoint = unclampedImagePoint(from: viewPoint, image: baseImage)

        if let selectionDragMode {
            guard let index = selectedIndex, let originalAnnotation else { return }
            switch selectionDragMode {
            case .rotate(let corner):
                let center = originalAnnotation.center
                let startAngle = atan2(dragStart.y - center.y, dragStart.x - center.x)
                let currentAngle = atan2(imagePoint.y - center.y, imagePoint.x - center.x)
                annotations[index].rotation = originalAnnotation.rotation + currentAngle - startAngle
                if let corner {
                    EditorCursors.rotation(
                        angle: rotationCursorAngle(for: corner, annotation: annotations[index])
                    ).set()
                }
            case .endpoint(let endpoint):
                annotations[index] = originalAnnotation
                var target = imagePoint
                if originalAnnotation.kind == .arrow || originalAnnotation.kind == .line,
                   event.modifierFlags.contains(.shift) {
                    let anchor = endpoint == .end ? originalAnnotation.start : originalAnnotation.end
                    target = angleConstrainedPoint(from: anchor, to: imagePoint)
                }
                annotations[index].moveEndpoint(endpoint, to: target)
                NSCursor.crosshair.set()
            case .resize(let corner):
                annotations[index] = originalAnnotation
                annotations[index].resize(from: corner, to: imagePoint)
                EditorCursors.fourWayResize.set()
            case .textResize:
                annotations[index] = originalAnnotation
                annotations[index].resizeText(to: imagePoint)
                EditorCursors.fourWayResize.set()
            case .move:
                let proposedOffset = CGPoint(x: imagePoint.x - dragStart.x, y: imagePoint.y - dragStart.y)
                let offset = originalAnnotation.constrainedTranslation(
                    proposedOffset,
                    within: baseImage.size
                )
                annotations[index] = originalAnnotation
                annotations[index].move(by: offset)
                EditorCursors.fourWayResize.set()
            }
            didChangeDuringDrag = true
            needsDisplay = true
            return
        }

        switch tool {
        case .text:
            break
        default:
            var endPoint = imagePoint
            if tool == .line || tool == .arrow, event.modifierFlags.contains(.shift) {
                endPoint = angleConstrainedPoint(from: dragStart, to: endPoint)
            }
            previewAnnotation = makeAnnotation(for: tool, from: dragStart, to: endPoint)
            didChangeDuringDrag = true
            needsDisplay = true
        }
    }

    /// Snaps `end` to the nearest 45° direction from `start` (horizontal,
    /// vertical, or diagonal) — used while Shift is held for lines and arrows.
    private func angleConstrainedPoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return end }
        let step = CGFloat.pi / 4
        let snapped = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: start.x + cos(snapped) * length, y: start.y + sin(snapped) * length)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragStartInView = nil
            originalAnnotation = nil
            stateBeforeDrag = nil
            selectionDragMode = nil
            updateCursor(at: convert(event.locationInWindow, from: nil))
        }

        if inlineTextEditor != nil {
            return
        }
        if tool == .crop {
            cropDragEdges = []
            originalCropRect = nil
            // Unfreeze so the layout re-fits to show the full expanded crop.
            frozenImageRect = nil
            needsDisplay = true
            return
        }
        if let mode = selectionDragMode {
            if didChangeDuringDrag, let stateBeforeDrag {
                // Remember a drag-resized text size so the next new text reuses it.
                if case .textResize = mode, let index = selectedIndex,
                   annotations[index].kind == .text {
                    currentTextSize = annotations[index].textSize
                }
                registerUndo(to: stateBeforeDrag, actionName: selectionActionName)
                contentDidChange()
            }
            return
        }

        switch tool {
        case .text:
            break
        default:
            guard var annotation = previewAnnotation, isLargeEnough(annotation), let stateBeforeDrag else {
                previewAnnotation = nil
                needsDisplay = true
                return
            }
            if let baseImage {
                annotation.move(
                    by: annotation.constrainedTranslation(.zero, within: baseImage.size)
                )
            }
            annotations.append(annotation)
            selectedAnnotationID = annotation.kind == .mosaic ? nil : annotation.id
            previewAnnotation = nil
            registerUndo(to: stateBeforeDrag, actionName: "注釈を追加")
            contentDidChange()
        }
    }

    /// Requests that the current crop selection be applied (Return in crop mode).
    var onCropCommitRequested: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Return / Enter applies the crop while cropping.
        if tool == .crop, cropSelectionRect != nil, event.keyCode == 36 || event.keyCode == 76 {
            onCropCommitRequested?()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelection()
            return
        }
        // Single-key tool shortcuts (only when not editing text and no modifier).
        if inlineTextEditor == nil,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           let tool = CanvasView.toolForShortcut(chars) {
            onToolShortcut?(tool)
            return
        }
        super.keyDown(with: event)
    }

    /// Reports a tool chosen by keyboard so the controller can update the UI too.
    var onToolShortcut: ((EditorTool) -> Void)?

    private static func toolForShortcut(_ key: String) -> EditorTool? {
        switch key {
        case "a", "1": return .arrow
        case "t", "2": return .text
        case "r", "3": return .rectangle
        case "o", "4": return .ellipse
        case "l", "5": return .line
        case "m", "6": return .mosaic
        case "c", "7": return .crop
        default: return nil
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "z" {
            undoEdit()
            return true
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift], event.charactersIgnoringModifiers == "z" {
            redoEdit()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func deleteSelection() {
        guard let index = selectedIndex else { return }
        let before = snapshot()
        annotations.remove(at: index)
        selectedAnnotationID = nil
        registerUndo(to: before, actionName: "注釈を削除")
        contentDidChange()
    }

    private func beginInlineTextEditing(at point: CGPoint) {
        finishInlineTextEditing(commit: true)
        guard baseImage != nil else { return }
        let session = TextEditingSession(
            origin: point,
            before: snapshot(),
            insertionIndex: nil,
            originalAnnotation: nil,
            color: currentColor,
            lineWidth: currentLineWidth,
            fontSize: currentTextSize ?? defaultTextFontSize(for: currentLineWidth)
        )
        presentInlineTextEditor(text: "", session: session)
    }

    private func beginInlineTextEditing(annotationAt index: Int) {
        finishInlineTextEditing(commit: true)
        guard annotations.indices.contains(index), annotations[index].kind == .text else { return }
        let before = snapshot()
        let annotation = annotations.remove(at: index)
        let session = TextEditingSession(
            origin: annotation.rect.origin,
            before: before,
            insertionIndex: index,
            originalAnnotation: annotation,
            color: annotation.color,
            lineWidth: annotation.lineWidth,
            fontSize: effectiveTextFontSize(for: annotation)
        )
        presentInlineTextEditor(text: annotation.text, session: session)
    }

    private func presentInlineTextEditor(text: String, session: TextEditingSession) {
        let editor = InlineTextEditor(frame: .zero)
        editor.textView.delegate = self
        let font = NSFont.systemFont(ofSize: session.fontSize, weight: .bold)
        let attributes = textDrawingAttributes(font: font, color: session.color)
        editor.textView.font = font
        editor.textView.textColor = session.color
        editor.textView.insertionPointColor = PictoJotStyle.selectionHandleColor
        editor.textView.typingAttributes = attributes
        editor.textView.inputDidUpdate = { [weak self, weak editor] in
            guard let self, self.inlineTextEditor === editor else { return }
            self.updateInlineTextEditorFrame()
        }
        editor.textView.onCommitRequested = { [weak self, weak editor] in
            guard let self, self.inlineTextEditor === editor else { return }
            self.finishInlineTextEditing(commit: true)
            self.window?.makeFirstResponder(self)
        }
        editor.textView.string = text
        editor.textView.textStorage?.setAttributes(
            attributes,
            range: NSRange(location: 0, length: (text as NSString).length)
        )
        inlineTextEditor = editor
        textEditingSession = session
        selectedAnnotationID = nil
        addSubview(editor)
        updateInlineTextEditorFrame()
        window?.makeFirstResponder(editor.textView)
        editor.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === inlineTextEditor?.textView else { return }
        updateInlineTextEditorFrame()
    }

    /// Timestamp of the mouse-down that ended inline text editing, so that
    /// click only commits the text instead of starting a new text box.
    private var textEditEndedByMouseDownTimestamp: TimeInterval?

    func textDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextView === inlineTextEditor?.textView else { return }
        if let event = NSApp.currentEvent, event.type == .leftMouseDown {
            textEditEndedByMouseDownTimestamp = event.timestamp
        }
        finishInlineTextEditing(commit: true)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard textView === inlineTextEditor?.textView else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)),
           NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            finishInlineTextEditing(commit: true)
            window?.makeFirstResponder(self)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Esc keeps what was typed and leaves text mode so tool keys work.
            finishInlineTextEditing(commit: true)
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    private func updateInlineTextEditorFrame() {
        guard let editor = inlineTextEditor, let session = textEditingSession, let baseImage else { return }
        let targetRect = imageRect(for: baseImage)
        let scale = targetRect.width / baseImage.size.width
        let fontSize = max(1, session.fontSize * scale)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        editor.textView.font = font
        editor.textView.textColor = session.color
        if !editor.textView.hasMarkedText() {
            let attributes = textDrawingAttributes(font: font, color: session.color)
            editor.textView.typingAttributes = attributes
            editor.textView.textStorage?.setAttributes(
                attributes,
                range: NSRange(location: 0, length: (editor.textView.string as NSString).length)
            )
        }
        let measured = measuredTextSize(editor.textView.string, font: font)
        let viewOrigin = map(session.origin, into: targetRect, scale: scale)
        editor.frame = CGRect(
            x: viewOrigin.x - 5,
            y: viewOrigin.y - 3,
            width: max(24, measured.width + 12),
            height: max(fontSize + 8, measured.height + 8)
        )
        editor.needsDisplay = true
        editor.textView.needsDisplay = true
    }

    private func finishInlineTextEditing(commit: Bool) {
        guard let editor = inlineTextEditor, let session = textEditingSession else { return }
        let text = editor.textView.string
        inlineTextEditor = nil
        textEditingSession = nil
        editor.textView.delegate = nil
        editor.textView.inputDidUpdate = nil
        editor.textView.onCommitRequested = nil
        editor.removeFromSuperview()

        if commit, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let rect = textBounds(for: text, at: session.origin, fontSize: session.fontSize)
            var annotation = Annotation(
                id: session.originalAnnotation?.id ?? UUID(),
                kind: .text,
                rect: rect,
                rotation: 0,
                color: session.color,
                lineWidth: session.lineWidth,
                text: text,
                textSize: session.fontSize
            )
            if let baseImage {
                annotation.move(
                    by: annotation.constrainedTranslation(.zero, within: baseImage.size)
                )
            }
            if let index = session.insertionIndex {
                annotations.insert(annotation, at: min(index, annotations.endIndex))
            } else {
                annotations.append(annotation)
            }
            selectedAnnotationID = annotation.id
            registerUndo(
                to: session.before,
                actionName: session.originalAnnotation == nil ? "テキストを追加" : "テキストを編集"
            )
            contentDidChange()
        } else if commit, session.originalAnnotation != nil {
            selectedAnnotationID = nil
            registerUndo(to: session.before, actionName: "テキストを削除")
            contentDidChange()
        } else {
            annotations = session.before.annotations
            selectedAnnotationID = session.before.selectedID
            needsDisplay = true
        }
        window?.makeFirstResponder(self)
    }

    private func makeAnnotation(for tool: EditorTool, from start: CGPoint, to end: CGPoint) -> Annotation? {
        let rect = Geometry.normalizedRect(from: start, to: end)
        switch tool {
        case .arrow:
            return Annotation(kind: .arrow, start: start, end: end, color: currentColor, lineWidth: currentLineWidth)
        case .rectangle:
            return Annotation(kind: .rectangle, rect: rect, color: currentColor, lineWidth: currentLineWidth, filled: currentFilled)
        case .ellipse:
            return Annotation(kind: .ellipse, rect: rect, color: currentColor, lineWidth: currentLineWidth, filled: currentFilled)
        case .line:
            return Annotation(kind: .line, start: start, end: end, color: currentColor, lineWidth: currentLineWidth)
        case .mosaic:
            return Annotation(kind: .mosaic, rect: rect, color: .clear, lineWidth: currentLineWidth)
        case .text, .crop:
            return nil
        }
    }

    private func isLargeEnough(_ annotation: Annotation) -> Bool {
        switch annotation.kind {
        case .arrow, .line:
            Geometry.distance(from: annotation.start, toSegmentStart: annotation.end, end: annotation.end) >= 4
        default:
            annotation.rect.width >= 4 && annotation.rect.height >= 4
        }
    }

    private func applyCrop(_ cropRect: CGRect) {
        guard let baseImage else { return }
        let imageBounds = CGRect(origin: .zero, size: baseImage.size)
        let crop = cropRect.standardized.integral
        guard crop.width >= 1, crop.height >= 1 else { return }

        if imageBounds.contains(crop), let cgImage = baseImage.cgImageValue {
            // Pure shrink: crop the pixels directly (preserves resolution).
            let scaleX = CGFloat(cgImage.width) / baseImage.size.width
            let scaleY = CGFloat(cgImage.height) / baseImage.size.height
            let pixelCrop = CGRect(
                x: crop.minX * scaleX,
                y: crop.minY * scaleY,
                width: crop.width * scaleX,
                height: crop.height * scaleY
            ).integral
            guard let cropped = cgImage.cropping(to: pixelCrop) else { return }
            self.baseImage = NSImage(cgImage: cropped, size: crop.size)
        } else {
            // Expansion: paint a white canvas and composite the original image at
            // its offset; areas outside the original stay white.
            let pixelScale = basePixelScale
            let canvasSize = CGSize(
                width: (crop.width * pixelScale).rounded(),
                height: (crop.height * pixelScale).rounded()
            )
            guard let expanded = PixelExactImageRenderer.render(size: canvasSize, drawing: { bounds in
                NSColor.white.setFill()
                bounds.fill()
                baseImage.draw(
                    in: CGRect(
                        x: -crop.minX * pixelScale,
                        y: -crop.minY * pixelScale,
                        width: baseImage.size.width * pixelScale,
                        height: baseImage.size.height * pixelScale
                    ),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high.rawValue]
                )
            }), let expandedPixels = expanded.cgImageValue else { return }
            self.baseImage = NSImage(cgImage: expandedPixels, size: crop.size)
        }
        pixelatedImageCache = nil

        annotations = annotations.compactMap { existing in
            guard existing.bounds.intersects(crop) else { return nil }
            var shifted = existing
            shifted.move(by: CGPoint(x: -crop.minX, y: -crop.minY))
            return shifted
        }
        selectedAnnotationID = nil
    }

    private func hitAnnotation(at point: CGPoint) -> Int? {
        for index in annotations.indices.reversed() {
            let annotation = annotations[index]
            let unrotatedPoint = Geometry.rotate(point, around: annotation.center, by: -annotation.rotation)
            let tolerance = max(8, annotation.lineWidth + 4)
            switch annotation.kind {
            case .arrow:
                let arrowTolerance = max(12, annotation.lineWidth * 2.4 + 4)
                if Geometry.distance(from: unrotatedPoint, toSegmentStart: annotation.start, end: annotation.end) <= arrowTolerance {
                    return index
                }
            case .line:
                if Geometry.distance(from: unrotatedPoint, toSegmentStart: annotation.start, end: annotation.end) <= tolerance {
                    return index
                }
            case .rectangle:
                if annotation.filled {
                    if annotation.rect.insetBy(dx: -tolerance, dy: -tolerance).contains(unrotatedPoint) { return index }
                } else {
                    let outer = annotation.rect.insetBy(dx: -tolerance, dy: -tolerance)
                    let inner = annotation.rect.insetBy(dx: tolerance, dy: tolerance)
                    if outer.contains(unrotatedPoint) && !inner.contains(unrotatedPoint) { return index }
                }
            case .ellipse, .text:
                if annotation.rect.insetBy(dx: -tolerance, dy: -tolerance).contains(unrotatedPoint) { return index }
            case .mosaic:
                continue
            }
        }
        return nil
    }

    private func isRotationHandleHit(_ viewPoint: CGPoint, annotation: Annotation) -> Bool {
        guard annotation.kind != .arrow,
              annotation.kind != .line,
              annotation.kind != .rectangle,
              annotation.kind != .ellipse,
              annotation.kind != .text else { return false }
        guard let baseImage else { return false }
        let targetRect = imageRect(for: baseImage)
        let scale = targetRect.width / baseImage.size.width
        let mappedBounds = map(annotation.bounds, into: targetRect, scale: scale)
        let center = map(annotation.center, into: targetRect, scale: scale)
        let unrotated = Geometry.rotate(viewPoint, around: center, by: -annotation.rotation)
        let handle = CGPoint(x: mappedBounds.midX, y: mappedBounds.minY - 24)
        return hypot(unrotated.x - handle.x, unrotated.y - handle.y) <= 10
    }

    private func endpointHandleHit(at viewPoint: CGPoint, annotation: Annotation) -> AnnotationEndpoint? {
        guard annotation.kind == .arrow || annotation.kind == .line, let baseImage else { return nil }
        let targetRect = imageRect(for: baseImage)
        let scale = targetRect.width / baseImage.size.width
        let start = map(annotation.displayedStart, into: targetRect, scale: scale)
        let end = map(annotation.displayedEnd, into: targetRect, scale: scale)
        if hypot(viewPoint.x - start.x, viewPoint.y - start.y) <= 10 {
            return .start
        }
        if hypot(viewPoint.x - end.x, viewPoint.y - end.y) <= 10 {
            return .end
        }
        return nil
    }

    private func shapeHandleHit(at viewPoint: CGPoint, annotation: Annotation) -> AnnotationCorner? {
        guard annotation.kind == .rectangle || annotation.kind == .ellipse, let baseImage else { return nil }
        let targetRect = imageRect(for: baseImage)
        let scale = targetRect.width / baseImage.size.width
        return AnnotationCorner.allCases.first { corner in
            let point = map(annotation.displayedCorner(corner), into: targetRect, scale: scale)
            return hypot(viewPoint.x - point.x, viewPoint.y - point.y) <= 10
        }
    }

    private func textResizeHandleHit(at viewPoint: CGPoint, annotation: Annotation) -> Bool {
        guard annotation.kind == .text, let baseImage else { return false }
        let targetRect = imageRect(for: baseImage)
        let scale = targetRect.width / baseImage.size.width
        let mappedRect = map(annotation.rect, into: targetRect, scale: scale)
        return hypot(viewPoint.x - mappedRect.maxX, viewPoint.y - mappedRect.maxY) <= 10
    }

    private func shapeRotationZoneHit(at viewPoint: CGPoint, annotation: Annotation) -> AnnotationCorner? {
        guard annotation.kind == .rectangle || annotation.kind == .ellipse, let baseImage else { return nil }
        let targetRect = imageRect(for: baseImage)
        let scale = targetRect.width / baseImage.size.width
        let center = map(annotation.center, into: targetRect, scale: scale)
        return AnnotationCorner.allCases.first { corner in
            let point = map(annotation.displayedCorner(corner), into: targetRect, scale: scale)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let length = max(1, hypot(dx, dy))
            let zone = CGPoint(x: point.x + dx / length * 19, y: point.y + dy / length * 19)
            return hypot(viewPoint.x - zone.x, viewPoint.y - zone.y) <= 12
        }
    }

    private func rotationCursorAngle(for corner: AnnotationCorner, annotation: Annotation) -> CGFloat {
        let point = annotation.displayedCorner(corner)
        return -atan2(point.y - annotation.center.y, point.x - annotation.center.x) - .pi / 4
    }

    private var selectionActionName: String {
        switch selectionDragMode {
        case .rotate:
            return "注釈を回転"
        case .endpoint:
            return "線の長さと角度を変更"
        case .resize:
            return "図形のサイズを変更"
        case .textResize:
            return "文字のサイズを変更"
        case .move, .none:
            return "注釈を移動"
        }
    }

    private func updateCursor(at viewPoint: CGPoint) {
        guard let baseImage else {
            NSCursor.arrow.set()
            return
        }

        if tool == .crop, let cropSelectionRect {
            setCropCursor(for: cropEdges(at: viewPoint, crop: cropSelectionRect))
            return
        }

        if let index = selectedIndex {
            let annotation = annotations[index]
            if endpointHandleHit(at: viewPoint, annotation: annotation) != nil {
                NSCursor.crosshair.set()
                return
            }
            if shapeHandleHit(at: viewPoint, annotation: annotation) != nil {
                EditorCursors.fourWayResize.set()
                return
            }
            if textResizeHandleHit(at: viewPoint, annotation: annotation) {
                EditorCursors.fourWayResize.set()
                return
            }
            if let corner = shapeRotationZoneHit(at: viewPoint, annotation: annotation) {
                EditorCursors.rotation(angle: rotationCursorAngle(for: corner, annotation: annotation)).set()
                return
            }
            if isRotationHandleHit(viewPoint, annotation: annotation) {
                NSCursor.crosshair.set()
                return
            }
        }
        if let point = imagePoint(from: viewPoint, image: baseImage), hitAnnotation(at: point) != nil {
            EditorCursors.fourWayResize.set()
            return
        }

        switch tool {
        case .text:
            NSCursor.iBeam.set()
        default:
            NSCursor.crosshair.set()
        }
    }

    private var selectedIndex: Int? {
        guard let selectedAnnotationID else { return nil }
        return annotations.firstIndex { $0.id == selectedAnnotationID }
    }

    /// The image's placement when fit to the window (no view zoom applied).
    private func fitImageRect(for image: NSImage) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else { return .zero }

        // In crop mode, leave a margin and reserve room for a crop that extends
        // beyond the image, so the user can drag handles outward into white space.
        let inset: CGFloat
        var content = CGRect(origin: .zero, size: image.size)
        if let cropSelectionRect {
            inset = max(28, min(bounds.width, bounds.height) * 0.12)
            content = content.union(cropSelectionRect)
        } else {
            inset = 28
        }
        let available = bounds.insetBy(dx: inset, dy: inset)
        guard content.width > 0, content.height > 0 else { return .zero }

        // Never enlarge: a screenshot smaller than the window is shown at its
        // captured size (100%), and only oversized captures are shrunk to fit.
        let scale = min(1, min(available.width / content.width, available.height / content.height))
        let contentSize = CGSize(width: content.width * scale, height: content.height * scale)
        let contentOrigin = CGPoint(
            x: available.midX - contentSize.width / 2,
            y: available.midY - contentSize.height / 2
        )
        // Where the image (0,0,w,h) sits within the laid-out content.
        return CGRect(
            x: contentOrigin.x + (0 - content.minX) * scale,
            y: contentOrigin.y + (0 - content.minY) * scale,
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    }

    private func imageRect(for image: NSImage) -> CGRect {
        if let frozenImageRect { return frozenImageRect }
        let fit = fitImageRect(for: image)
        // View zoom & pan apply only during normal editing, not while cropping.
        guard cropSelectionRect == nil, zoomFactor != 1 || panOffset != .zero else { return fit }
        let width = fit.width * zoomFactor
        let height = fit.height * zoomFactor
        let centerX = fit.midX + panOffset.x
        let centerY = fit.midY + panOffset.y
        return CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
    }

    // MARK: View zoom

    func zoomIn() { applyZoom(zoomFactor * 1.25) }
    func zoomOut() { applyZoom(zoomFactor / 1.25) }
    func resetZoom() {
        zoomFactor = 1
        panOffset = .zero
        needsDisplay = true
        notifyZoomChanged()
    }

    var canZoomOut: Bool { zoomFactor > 1.0001 }

    private func applyZoom(_ newZoom: CGFloat) {
        guard let baseImage, cropSelectionRect == nil else { return }
        zoomFactor = min(maxZoomFactor, max(1, newZoom))
        panOffset = clampedPanOffset(panOffset, fit: fitImageRect(for: baseImage))
        needsDisplay = true
        notifyZoomChanged()
    }

    private func clampedPanOffset(_ pan: CGPoint, fit: CGRect) -> CGPoint {
        let available = bounds.insetBy(dx: 28, dy: 28)
        let maxX = max(0, (fit.width * zoomFactor - available.width) / 2)
        let maxY = max(0, (fit.height * zoomFactor - available.height) / 2)
        return CGPoint(
            x: min(maxX, max(-maxX, pan.x)),
            y: min(maxY, max(-maxY, pan.y))
        )
    }

    private func notifyZoomChanged() {
        guard let baseImage, baseImage.size.width > 0 else { return }
        let percent = Int((imageRect(for: baseImage).width / baseImage.size.width * 100).rounded())
        onZoomChanged?(percent)
    }

    override func magnify(with event: NSEvent) {
        guard baseImage != nil, cropSelectionRect == nil else { return }
        applyZoom(zoomFactor * (1 + event.magnification))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let baseImage, cropSelectionRect == nil, zoomFactor > 1 else {
            super.scrollWheel(with: event)
            return
        }
        let proposed = CGPoint(x: panOffset.x + event.scrollingDeltaX, y: panOffset.y + event.scrollingDeltaY)
        panOffset = clampedPanOffset(proposed, fit: fitImageRect(for: baseImage))
        needsDisplay = true
    }

    private func imagePoint(from viewPoint: CGPoint, image: NSImage) -> CGPoint? {
        let rect = imageRect(for: image)
        guard rect.contains(viewPoint), rect.width > 0 else { return nil }
        return unclampedImagePoint(from: viewPoint, image: image)
    }

    private func unclampedImagePoint(from viewPoint: CGPoint, image: NSImage) -> CGPoint {
        let rect = imageRect(for: image)
        let scale = rect.width / image.size.width
        return CGPoint(
            x: min(image.size.width, max(0, (viewPoint.x - rect.minX) / scale)),
            y: min(image.size.height, max(0, (viewPoint.y - rect.minY) / scale))
        )
    }

    /// Like `unclampedImagePoint`, but without clamping to the image bounds — used
    /// for crop, which may extend past the image into white space.
    private func rawImagePoint(from viewPoint: CGPoint, image: NSImage) -> CGPoint {
        let rect = imageRect(for: image)
        guard rect.width > 0, image.size.width > 0 else { return .zero }
        let scale = rect.width / image.size.width
        return CGPoint(
            x: (viewPoint.x - rect.minX) / scale,
            y: (viewPoint.y - rect.minY) / scale
        )
    }

    private func map(_ point: CGPoint, into targetRect: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(x: targetRect.minX + point.x * scale, y: targetRect.minY + point.y * scale)
    }

    private func map(_ rect: CGRect, into targetRect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: targetRect.minX + rect.minX * scale, y: targetRect.minY + rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    private func defaultTextFontSize(for lineWidth: CGFloat) -> CGFloat {
        16 + lineWidth * 3
    }

    private func effectiveTextFontSize(for annotation: Annotation) -> CGFloat {
        annotation.textSize > 0 ? annotation.textSize : defaultTextFontSize(for: annotation.lineWidth)
    }

    private func textDrawingAttributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: color
        ]
    }

    private func textOutlineDrawingAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .strokeColor: PictoJotStyle.textOutlineColor,
            .strokeWidth: PictoJotStyle.textOutlineWidth
        ]
    }

    private func textBounds(for text: String, at origin: CGPoint, fontSize: CGFloat) -> CGRect {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let measured = measuredTextSize(text, font: font)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: max(16, measured.width + 12),
            height: max(fontSize + 10, measured.height + 10)
        )
    }

    private func measuredTextSize(_ text: String, font: NSFont) -> CGSize {
        let lines = text.components(separatedBy: "\n")
        let widths = lines.map { line in
            ((line.isEmpty ? " " : line) as NSString).size(withAttributes: [.font: font]).width
        }
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return CGSize(
            width: ceil(widths.max() ?? 0),
            height: lineHeight * CGFloat(max(1, lines.count))
        )
    }

    private func resizeTextBounds(at index: Int) {
        let annotation = annotations[index]
        guard annotation.kind == .text else { return }
        annotations[index].rect = textBounds(
            for: annotation.text,
            at: annotation.rect.origin,
            fontSize: effectiveTextFontSize(for: annotation)
        )
    }

    private func pixelatedBaseImage() -> NSImage? {
        if let pixelatedImageCache { return pixelatedImageCache }
        guard let baseImage, let cgImage = baseImage.cgImageValue else { return nil }
        let filter = CIFilter.pixellate()
        filter.inputImage = CIImage(cgImage: cgImage)
        // Block size in points, kept constant regardless of backing scale.
        filter.scale = Float(PictoJotStyle.mosaicBlockSize * basePixelScale)
        guard let output = filter.outputImage,
              let rendered = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent) else { return nil }
        let result = NSImage(cgImage: rendered, size: baseImage.size)
        pixelatedImageCache = result
        return result
    }

    private func snapshot() -> EditorSnapshot {
        EditorSnapshot(image: baseImage, annotations: annotations, selectedID: selectedAnnotationID)
    }

    private func restore(_ snapshot: EditorSnapshot) {
        baseImage = snapshot.image
        annotations = snapshot.annotations
        selectedAnnotationID = snapshot.selectedID
        pixelatedImageCache = nil
        contentDidChange()
    }

    private func registerUndo(to previous: EditorSnapshot, actionName: String) {
        editingUndoManager.registerUndo(withTarget: self) { target in
            let current = target.snapshot()
            target.registerUndo(to: current, actionName: actionName)
            target.restore(previous)
        }
        editingUndoManager.setActionName(actionName)
    }

    private func contentDidChange() {
        needsDisplay = true
        delegate?.canvasViewDidChangeContent(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        firstSupportedImageURL(from: sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = firstSupportedImageURL(from: sender) else { return false }
        delegate?.canvasView(self, didReceiveImageAt: url)
        return true
    }

    private func firstSupportedImageURL(from draggingInfo: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: NSImage.supportedDropTypes.map(\.identifier)
        ]
        return (draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }
}
