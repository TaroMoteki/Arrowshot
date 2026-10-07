import AppKit
import UniformTypeIdentifiers

private final class CircularColorWell: NSColorWell {
    override func mouseDown(with event: NSEvent) {
        activate(true)
        NSColorPanel.shared.showsAlpha = false
        NSColorPanel.shared.makeKeyAndOrderFront(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let outerRect = bounds.insetBy(dx: 2, dy: 2)
        let outer = NSBezierPath(ovalIn: outerRect)
        NSColor.white.setFill()
        outer.fill()
        NSColor.separatorColor.setStroke()
        outer.lineWidth = 1
        outer.stroke()

        let swatch = NSBezierPath(ovalIn: outerRect.insetBy(dx: 3, dy: 3))
        color.setFill()
        swatch.fill()
    }
}

private final class ToolIconButton: NSButton {
    var displaysTextGlyph = false

    func setSelectedAppearance(_ selected: Bool) {
        state = selected ? .on : .off
        layer?.backgroundColor = selected
            ? NSColor(calibratedWhite: 0.38, alpha: 1).cgColor
            : NSColor.clear.cgColor
        contentTintColor = selected ? .white : .secondaryLabelColor
        if displaysTextGlyph {
            attributedTitle = NSAttributedString(
                string: "a",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 25, weight: .bold),
                    .foregroundColor: selected ? NSColor.white : NSColor.secondaryLabelColor
                ]
            )
        }
    }
}

private class ArrowCursorVisualEffectView: NSVisualEffectView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

private final class DraggableToolbarView: ArrowCursorVisualEffectView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class EditorWindow: NSWindow {
    private var arrowCursorRegions: [NSView] = []

    func setArrowCursorRegions(_ views: [NSView]) {
        arrowCursorRegions = views
        if let contentView {
            invalidateCursorRects(for: contentView)
        }
    }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)

        guard event.type == .mouseMoved ||
                event.type == .mouseEntered ||
                event.type == .cursorUpdate else { return }
        let isInsideArrowRegion = arrowCursorRegions.contains { view in
            guard !view.isHidden, view.window === self else { return false }
            return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
        if isInsideArrowRegion || !contentLayoutRect.contains(event.locationInWindow) {
            NSCursor.arrow.set()
        }
    }
}

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, CanvasViewDelegate {
    var onVisibilityChanged: ((Bool) -> Void)?

    private let canvasView = CanvasView(frame: .zero)
    private let colorWell = CircularColorWell(frame: .zero)
    private let widthPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fillToggle = NSButton()
    private let statusLabel = NSTextField(labelWithString: NSLocalizedString("Open an image to get started", comment: ""))
    private let cropSizeLabel = NSTextField(labelWithString: "— × —")
    private var editingControls: NSStackView!
    private var exportControls: NSStackView!
    private var cropControls: NSStackView!
    private var toolButtons: [EditorTool: ToolIconButton] = [:]
    private var lastNonCropTool: EditorTool = .arrow
    private var currentSourceName: String?
    private var isDirty = false
    private var zoomPercent = 100
    private var isHiddenForDrag = false

    init() {
        let window = EditorWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Arrowshot"
        window.minSize = CGSize(width: 820, height: 520)
        window.center()
        super.init(window: window)
        window.delegate = self
        configureInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showEditor() {
        guard let window else { return }
        onVisibilityChanged?(true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvasView)
    }

    func hideEditor() {
        window?.orderOut(nil)
        onVisibilityChanged?(false)
        NSCursor.arrow.set()
    }

    func presentCapturedImage(_ image: NSImage) {
        requestImageReplacement(with: image, sourceName: NSLocalizedString("Screenshot", comment: ""))
    }

    func openImage(at url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            showError(title: NSLocalizedString("Can’t Open the Image", comment: ""), message: NSLocalizedString("Choose a supported image file.", comment: ""))
            return
        }
        requestImageReplacement(with: image, sourceName: url.lastPathComponent)
    }

    private func configureInterface() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        let toolbar = makeToolbar()
        let sidebar = makeSidebar()
        (window as? EditorWindow)?.setArrowCursorRegions([toolbar, sidebar])
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.delegate = self
        canvasView.onZoomChanged = { [weak self] percent in
            self?.zoomPercent = percent
            self?.updateStatus()
        }
        canvasView.onToolShortcut = { [weak self] tool in
            self?.activateTool(tool)
        }
        canvasView.onCropCommitRequested = { [weak self] in
            self?.applyCrop()
        }

        let body = NSStackView(views: [sidebar, canvasView])
        body.orientation = .horizontal
        body.spacing = 0
        body.translatesAutoresizingMaskIntoConstraints = false

        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(statusLabel)

        root.addArrangedSubview(toolbar)
        root.addArrangedSubview(body)
        root.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 54),
            sidebar.widthAnchor.constraint(equalToConstant: 60),
            footer.heightAnchor.constraint(equalToConstant: 25),
            statusLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 10),
            statusLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])

        colorWell.color = ArrowshotStyle.defaultAnnotationColor
        colorWell.isBordered = false
        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))

        widthPopup.addItems(withTitles: ["2", "4", "6", "10", "16", "24"])
        widthPopup.selectItem(at: 2)
        widthPopup.target = self
        widthPopup.action = #selector(widthChanged(_:))
        selectToolButton(.arrow)
    }

    private func makeToolbar() -> NSView {
        let background = DraggableToolbarView()
        background.material = .titlebar
        background.blendingMode = .behindWindow
        background.state = .followsWindowActiveState
        background.translatesAutoresizingMaskIntoConstraints = false

        let undoButton = makeIconButton(symbol: "arrow.uturn.backward", toolTip: NSLocalizedString("Undo (⌘Z)", comment: ""), action: #selector(undoEdit))
        let redoButton = makeIconButton(symbol: "arrow.uturn.forward", toolTip: NSLocalizedString("Redo (⇧⌘Z)", comment: ""), action: #selector(redoEdit))
        let dragButton = makeDragButton()
        let copyButton = makeIconButton(symbol: "doc.on.doc", toolTip: NSLocalizedString("Copy (⌘C)", comment: ""), action: #selector(copyImage))
        let saveButton = makeIconButton(symbol: "square.and.arrow.down", toolTip: NSLocalizedString("Save (⌘S) / Save As (⇧⌘S)", comment: ""), action: #selector(saveImage))
        let cancelCropButton = makeButton(title: NSLocalizedString("Cancel", comment: ""), action: #selector(cancelCrop), width: 88)
        let applyCropButton = makeButton(title: NSLocalizedString("✓ Apply", comment: ""), action: #selector(applyCrop), width: 78)

        editingControls = NSStackView(views: [undoButton, redoButton])
        editingControls.orientation = .horizontal
        editingControls.spacing = 7
        editingControls.alignment = .centerY

        exportControls = NSStackView(views: [dragButton, copyButton, saveButton])
        exportControls.orientation = .horizontal
        exportControls.spacing = 7
        exportControls.alignment = .centerY

        cropSizeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        cropSizeLabel.alignment = .center
        cropSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        cropSizeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 112).isActive = true
        cropControls = NSStackView(views: [cropSizeLabel, cancelCropButton, applyCropButton])
        cropControls.orientation = .horizontal
        cropControls.spacing = 8
        cropControls.alignment = .centerY
        cropControls.isHidden = true

        for controls in [editingControls!, exportControls!, cropControls!] {
            controls.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(controls)
        }

        NSLayoutConstraint.activate([
            editingControls.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            editingControls.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            exportControls.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            exportControls.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            cropControls.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            cropControls.centerYAnchor.constraint(equalTo: background.centerYAnchor)
        ])
        return background
    }

    private func makeSidebar() -> NSView {
        let background = ArrowCursorVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .withinWindow
        background.state = .active
        background.translatesAutoresizingMaskIntoConstraints = false

        let toolStack = NSStackView()
        toolStack.orientation = .vertical
        toolStack.spacing = 3
        toolStack.alignment = .centerX

        for tool in EditorTool.allCases {
            let button = makeToolButton(for: tool)
            toolButtons[tool] = button
            toolStack.addArrangedSubview(button)
        }

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 42).isActive = true

        colorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorWell.widthAnchor.constraint(equalToConstant: 20),
            colorWell.heightAnchor.constraint(equalToConstant: 20)
        ])

        widthPopup.translatesAutoresizingMaskIntoConstraints = false
        widthPopup.toolTip = NSLocalizedString("Line and text width", comment: "")
        NSLayoutConstraint.activate([
            widthPopup.widthAnchor.constraint(equalToConstant: 48),
            widthPopup.heightAnchor.constraint(equalToConstant: 28)
        ])

        fillToggle.setButtonType(.pushOnPushOff)
        fillToggle.bezelStyle = .texturedRounded
        fillToggle.imagePosition = .imageOnly
        fillToggle.image = NSImage(systemSymbolName: "square.fill", accessibilityDescription: NSLocalizedString("Fill", comment: ""))?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        fillToggle.toolTip = NSLocalizedString("Fill (rectangles and ellipses)", comment: "")
        fillToggle.target = self
        fillToggle.action = #selector(fillToggled(_:))
        fillToggle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fillToggle.widthAnchor.constraint(equalToConstant: 34),
            fillToggle.heightAnchor.constraint(equalToConstant: 28)
        ])

        let stack = NSStackView(views: [toolStack, separator, colorWell, widthPopup, fillToggle])
        stack.orientation = .vertical
        stack.spacing = 9
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            stack.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor, constant: -12)
        ])
        return background
    }

    private func makeToolButton(for tool: EditorTool) -> ToolIconButton {
        let button = ToolIconButton()
        button.target = self
        button.action = #selector(toolChanged(_:))
        button.tag = tool.rawValue
        button.toolTip = String(format: NSLocalizedString("%@ (%@)", comment: "Tool name and its key"), tool.title, tool.shortcutLabel)
        button.isBordered = false
        button.focusRingType = .none
        button.setButtonType(.momentaryChange)
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        if tool == .text {
            button.displaysTextGlyph = true
            button.imagePosition = .noImage
        } else {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            if tool == .mosaic {
                button.image = mosaicToolImage()
            } else {
                let symbol = NSImage(systemSymbolName: symbolName(for: tool), accessibilityDescription: tool.title)
                button.image = symbol?.withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
            }
        }
        button.setSelectedAppearance(false)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 42),
            button.heightAnchor.constraint(equalToConstant: 42)
        ])
        return button
    }

    private func mosaicToolImage() -> NSImage {
        let size = CGSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            let pixels: [(column: CGFloat, row: CGFloat, opacity: CGFloat)] = [
                (0, 3, 0.66), (2, 3, 0.38),
                (1, 2, 0.38), (2, 2, 0.38), (3, 2, 0.38),
                (1, 1, 0.66), (2, 1, 0.66),
                (0, 0, 0.50), (1, 0, 0.50), (3, 0, 0.50)
            ]
            for pixel in pixels {
                NSColor.black.withAlphaComponent(pixel.opacity).setFill()
                CGRect(
                    x: 1 + pixel.column * 5,
                    y: 1 + pixel.row * 5,
                    width: 5,
                    height: 5
                ).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = NSLocalizedString("Pixelate", comment: "")
        return image
    }

    private func symbolName(for tool: EditorTool) -> String {
        switch tool {
        case .arrow: "arrow.down.left"
        case .text: "textformat"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .mosaic: "square.grid.3x3.fill"
        case .crop: "crop"
        }
    }

    private func makeButton(title: String, action: Selector, width: CGFloat? = nil) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        if let width {
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return button
    }

    /// An original template icon: a small page framed by four corner marks,
    /// evoking "grab and drag this image out".
    private static func dragGlyphImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()

            // Page in the middle.
            let page = NSBezierPath(
                roundedRect: NSRect(x: 5.5, y: 4, width: 7, height: 10),
                xRadius: 1.3,
                yRadius: 1.3
            )
            page.lineWidth = 1.3
            page.stroke()

            // Four corner marks around it (a drag "marquee").
            let outer = NSRect(x: 1.6, y: 1.6, width: 14.8, height: 14.8)
            let arm: CGFloat = 3.0
            let marks = NSBezierPath()
            marks.lineWidth = 1.5
            marks.lineCapStyle = .round
            marks.lineJoinStyle = .round
            // Top-left
            marks.move(to: NSPoint(x: outer.minX, y: outer.maxY - arm))
            marks.line(to: NSPoint(x: outer.minX, y: outer.maxY))
            marks.line(to: NSPoint(x: outer.minX + arm, y: outer.maxY))
            // Top-right
            marks.move(to: NSPoint(x: outer.maxX - arm, y: outer.maxY))
            marks.line(to: NSPoint(x: outer.maxX, y: outer.maxY))
            marks.line(to: NSPoint(x: outer.maxX, y: outer.maxY - arm))
            // Bottom-right
            marks.move(to: NSPoint(x: outer.maxX, y: outer.minY + arm))
            marks.line(to: NSPoint(x: outer.maxX, y: outer.minY))
            marks.line(to: NSPoint(x: outer.maxX - arm, y: outer.minY))
            // Bottom-left
            marks.move(to: NSPoint(x: outer.minX + arm, y: outer.minY))
            marks.line(to: NSPoint(x: outer.minX, y: outer.minY))
            marks.line(to: NSPoint(x: outer.minX, y: outer.minY + arm))
            marks.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func makeDragButton() -> DragExportButton {
        let button = DragExportButton()
        button.toolTip = NSLocalizedString("Drag to export the image (drop it into Finder or another app)", comment: "")
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.image = Self.dragGlyphImage()
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 34),
            button.heightAnchor.constraint(equalToConstant: 30)
        ])
        button.imageProvider = { [weak self] in self?.canvasView.renderedImage() }
        button.fileNameProvider = { [weak self] format in
            self?.suggestedFileName(format: format) ?? "Arrowshot.\(format.fileExtension)"
        }
        // Get the editor out of the way once the drag has moved a little, so it
        // does not cover the drop target. Dropped → stay hidden (reopen from the
        // Dock/menu, edits kept); cancelled → bring it back.
        button.onDragMovedAway = { [weak self] in
            self?.fadeOutForDrag()
        }
        button.onDragEnded = { [weak self] dropped in
            guard let self else { return }
            let wasHidden = self.isHiddenForDrag
            self.isHiddenForDrag = false
            self.window?.alphaValue = 1
            if dropped {
                self.hideEditor()
            } else if wasHidden {
                self.showEditor()
            }
        }
        return button
    }

    private func fadeOutForDrag() {
        guard let window, window.isVisible else { return }
        isHiddenForDrag = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // The drag may have been cancelled mid-fade; leave the window up then.
                guard let self, self.isHiddenForDrag else { return }
                window.orderOut(nil)
                window.alphaValue = 1
            }
        })
    }

    private func makeIconButton(symbol: String, toolTip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.target = self
        button.action = action
        button.toolTip = toolTip
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 34),
            button.heightAnchor.constraint(equalToConstant: 30)
        ])
        return button
    }

    private func requestImageReplacement(with image: NSImage, sourceName: String) {
        showEditor()
        canvasView.loadImage(image)
        currentSourceName = sourceName
        isDirty = false
        updateWindowTitle()
        updateStatus()
    }

    @objc private func toolChanged(_ sender: NSButton) {
        guard let tool = EditorTool(rawValue: sender.tag) else { return }
        activateTool(tool)
    }

    func activateTool(_ tool: EditorTool) {
        selectToolButton(tool)
        if tool != .crop {
            lastNonCropTool = tool
        }
        canvasView.selectTool(tool)
        updateCropControls(isCropping: tool == .crop)
        if tool == .crop {
            updateStatus(message: NSLocalizedString("Drag the white handles or edges to adjust the crop area", comment: ""))
        } else {
            updateStatus(message: String(format: NSLocalizedString("%@: drag on the image to add · Click an annotation to select it", comment: ""), tool.title))
        }
    }

    @objc private func applyCrop() {
        canvasView.applyCropSelection()
        leaveCropMode()
    }

    @objc private func cancelCrop() {
        canvasView.cancelCropSelection()
        leaveCropMode()
    }

    private func leaveCropMode() {
        selectToolButton(lastNonCropTool)
        canvasView.selectTool(lastNonCropTool)
        updateCropControls(isCropping: false)
        updateStatus()
    }

    private func selectToolButton(_ tool: EditorTool) {
        for (candidate, button) in toolButtons {
            button.setSelectedAppearance(candidate == tool)
        }
    }

    private func updateCropControls(isCropping: Bool) {
        editingControls.isHidden = isCropping
        exportControls.isHidden = isCropping
        cropControls.isHidden = !isCropping
        colorWell.isEnabled = !isCropping
        widthPopup.isEnabled = !isCropping
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        canvasView.setColor(sender.color)
        sender.needsDisplay = true
    }

    @objc private func widthChanged(_ sender: NSPopUpButton) {
        let widths: [CGFloat] = [2, 4, 6, 10, 16, 24]
        let index = max(0, min(sender.indexOfSelectedItem, widths.count - 1))
        canvasView.setLineWidth(widths[index])
    }

    @objc func openImagePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = NSImage.supportedDropTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openImage(at: url)
    }

    /// ⌘S — save immediately to the configured folder (Downloads by default),
    /// no dialog. Falls back to Save As if the folder can't be written.
    @objc func saveImage() {
        let format = ImageFormat.preferred
        guard let image = canvasView.renderedImage(), let data = format.data(for: image) else {
            NSSound.beep()
            return
        }
        let folder = SaveLocation.folderURL
        let url = SaveLocation.uniqueURL(for: suggestedFileName(format: format), in: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            isDirty = false
            currentSourceName = url.lastPathComponent
            updateWindowTitle()
            updateStatus(message: String(format: NSLocalizedString("Saved %1$@ to %2$@", comment: "File name, folder name"), url.lastPathComponent, folder.lastPathComponent))
        } catch {
            // Couldn't write to the chosen folder — fall back to a Save panel.
            saveAsImage()
        }
    }

    /// ⇧⌘S — choose the location and format with a Save panel. The format
    /// starts at the default from Settings.
    @objc func saveAsImage() {
        guard let image = canvasView.renderedImage() else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        let formatPicker = SaveFormatAccessory(panel: panel, format: ImageFormat.preferred)
        panel.accessoryView = formatPicker
        panel.nameFieldStringValue = suggestedFileName(format: formatPicker.format)
        panel.directoryURL = SaveLocation.folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = formatPicker.format.data(for: image) else {
            NSSound.beep()
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            isDirty = false
            currentSourceName = url.lastPathComponent
            updateWindowTitle()
            updateStatus(message: String(format: NSLocalizedString("Saved %@", comment: "File name"), url.lastPathComponent))
        } catch {
            showError(title: NSLocalizedString("Can’t Save the Image", comment: ""), message: error.localizedDescription)
        }
    }

    /// The inline text field while a text annotation is being typed. Edit menu
    /// commands act on its text instead of on the image.
    private var activeTextView: NSTextView? {
        window?.firstResponder as? NSTextView
    }

    @objc func cutText() {
        guard let textView = activeTextView else {
            NSSound.beep()
            return
        }
        textView.cut(nil)
    }

    @objc func selectAllText() {
        activeTextView?.selectAll(nil)
    }

    @objc func copyImage() {
        if let textView = activeTextView {
            textView.copy(nil)
            return
        }
        guard let image = canvasView.renderedImage(), let pngData = image.pngData() else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        updateStatus(message: NSLocalizedString("Copied the image to the clipboard", comment: ""))
    }

    @objc func pasteImage() {
        if let textView = activeTextView {
            textView.paste(nil)
            return
        }
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) {
            requestImageReplacement(with: image, sourceName: NSLocalizedString("Clipboard", comment: ""))
            return
        }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: NSImage.supportedDropTypes.map(\.identifier),
        ]
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first,
           let image = NSImage(contentsOf: url) {
            requestImageReplacement(with: image, sourceName: url.lastPathComponent)
            return
        }

        NSSound.beep()
        updateStatus(message: NSLocalizedString("No supported image on the clipboard", comment: ""))
    }

    @objc func undoEdit() {
        if let textView = activeTextView {
            textView.undoManager?.undo()
            return
        }
        canvasView.undoEdit()
    }

    @objc func redoEdit() {
        if let textView = activeTextView {
            textView.undoManager?.redo()
            return
        }
        canvasView.redoEdit()
    }

    func canvasView(_ canvasView: CanvasView, didReceiveImageAt url: URL) {
        openImage(at: url)
    }

    func canvasViewDidChangeContent(_ canvasView: CanvasView) {
        isDirty = true
        updateWindowTitle()
        updateStatus()
    }

    func canvasView(_ canvasView: CanvasView, didUpdateCropRect rect: CGRect?) {
        guard let rect else {
            cropSizeLabel.stringValue = "— × —"
            return
        }
        cropSizeLabel.stringValue = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideEditor()
        return false
    }

    private func updateWindowTitle() {
        let source = currentSourceName.map { " — \($0)" } ?? ""
        let dirtyMark = isDirty ? " ●" : ""
        window?.title = "Arrowshot\(source)\(dirtyMark)"
    }

    private func updateStatus(message: String? = nil) {
        if let message {
            statusLabel.stringValue = message
        } else if let image = canvasView.baseImage {
            // Report the real bitmap size: a Retina capture holds 2x the points.
            let pixels = image.cgImageValue.map { CGSize(width: $0.width, height: $0.height) } ?? image.size
            statusLabel.stringValue = "\(Int(pixels.width)) × \(Int(pixels.height)) px · \(zoomPercent)%"
        } else {
            statusLabel.stringValue = NSLocalizedString("Open an image to get started", comment: "")
        }
    }

    @objc private func fillToggled(_ sender: NSButton) {
        canvasView.setFilled(sender.state == .on)
    }

    @objc func zoomIn() { canvasView.zoomIn() }
    @objc func zoomOut() { canvasView.zoomOut() }
    @objc func zoomFit() { canvasView.resetZoom() }

    private func suggestedFileName(format: ImageFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Arrowshot \(formatter.string(from: Date())).\(format.fileExtension)"
    }

    private func showError(title: String, message: String) {
        showEditor()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

/// The "Format: PNG / JPEG" row under the Save As panel. Switching it updates
/// the allowed type, which also swaps the file name's extension.
@MainActor
private final class SaveFormatAccessory: NSView {
    private(set) var format: ImageFormat {
        didSet { panel?.allowedContentTypes = [format.contentType] }
    }
    private weak var panel: NSSavePanel?

    init(panel: NSSavePanel, format: ImageFormat) {
        self.panel = panel
        self.format = format
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 44))
        panel.allowedContentTypes = [format.contentType]

        let label = NSTextField(labelWithString: NSLocalizedString("Format:", comment: "Save panel"))
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ImageFormat.allCases.map(\.label))
        popup.selectItem(at: format.rawValue)
        popup.target = self
        popup.action = #selector(formatChanged(_:))

        let row = NSStackView(views: [label, popup])
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        format = ImageFormat(rawValue: sender.indexOfSelectedItem) ?? .png
    }
}
