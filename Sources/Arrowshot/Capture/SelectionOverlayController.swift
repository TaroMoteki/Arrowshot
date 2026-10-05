import AppKit

enum CaptureSelection {
    case rectangle(CGRect, CGDirectDisplayID)
    case window(CGWindowID)
    case cancelled
}

@MainActor
final class SelectionOverlayController {
    private var overlayWindows: [NSWindow] = []
    private var completion: ((CaptureSelection) -> Void)?
    private var hasCompleted = false

    func begin(completion: @escaping (CaptureSelection) -> Void) {
        self.completion = completion
        hasCompleted = false

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let window = SelectionWindow(
                contentRect: OverlayWindowGeometry.contentRect(forScreenFrame: screen.frame),
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false

            let selectionView = SelectionOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
            selectionView.onGesture = { [weak self, weak window] gesture in
                guard let self, let window else { return }
                self.handle(gesture, in: window, displayID: displayID)
            }
            window.contentView = selectionView
            overlayWindows.append(window)
            window.orderFrontRegardless()
            window.makeFirstResponder(selectionView)
        }

        NSApp.activate(ignoringOtherApps: true)
        let mouseLocation = NSEvent.mouseLocation
        let keyWindow = overlayWindows.first { $0.frame.contains(mouseLocation) } ?? overlayWindows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    func cancel() {
        finish(with: .cancelled)
    }

    private func handle(_ gesture: SelectionGesture, in window: NSWindow, displayID: CGDirectDisplayID) {
        switch gesture {
        case .cancel:
            finish(with: .cancelled)
        case .rectangle(let localRect):
            let cocoaRect = window.convertToScreen(localRect)
            let quartzRect = ScreenCoordinates.cocoaRectToQuartz(cocoaRect).integral
            guard quartzRect.width >= 2, quartzRect.height >= 2 else {
                finish(with: .cancelled)
                return
            }
            finish(with: .rectangle(quartzRect, displayID))
        case .click(let localPoint):
            let cocoaPoint = window.convertPoint(toScreen: localPoint)
            let quartzPoint = ScreenCoordinates.cocoaPointToQuartz(cocoaPoint)
            if let windowID = frontmostWindowID(at: quartzPoint) {
                finish(with: .window(windowID))
            } else {
                NSSound.beep()
                finish(with: .cancelled)
            }
        }
    }

    private func finish(with result: CaptureSelection) {
        guard !hasCompleted else { return }
        hasCompleted = true
        NSCursor.pop()
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    private func frontmostWindowID(at point: CGPoint) -> CGWindowID? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        let ownPID = getpid()
        for information in windowList {
            guard let ownerPID = information[kCGWindowOwnerPID] as? pid_t,
                  ownerPID != ownPID,
                  let layer = information[kCGWindowLayer] as? Int,
                  layer == 0,
                  let alpha = information[kCGWindowAlpha] as? CGFloat,
                  alpha > 0,
                  let number = information[kCGWindowNumber] as? CGWindowID,
                  let boundsDictionary = information[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 20,
                  bounds.height >= 20,
                  bounds.contains(point) else { continue }
            return number
        }
        return nil
    }
}

private enum SelectionGesture {
    case rectangle(CGRect)
    case click(CGPoint)
    case cancel
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayView: NSView {
    var onGesture: ((SelectionGesture) -> Void)?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()
        guard let selectionRect, selectionRect.width > 1, selectionRect.height > 1 else {
            drawInstruction()
            return
        }

        NSColor.clear.setFill()
        selectionRect.fill(using: .copy)
        let outline = NSBezierPath(rect: selectionRect)
        outline.lineWidth = 2
        NSColor.white.setStroke()
        outline.stroke()

        let sizeText = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        sizeText.draw(at: CGPoint(x: selectionRect.minX, y: max(4, selectionRect.minY - 22)), withAttributes: attributes)
    }

    private func drawInstruction() {
        let text = NSLocalizedString("Drag to select an area · Click a window to capture it · Esc to cancel", comment: "")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.65)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: 28), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = clamped(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint else { return }
        let endPoint = clamped(convert(event.locationInWindow, from: nil))
        let distance = hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y)
        if distance < 4 {
            onGesture?(.click(endPoint))
        } else {
            onGesture?(.rectangle(Geometry.normalizedRect(from: startPoint, to: endPoint)))
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onGesture?(.cancel)
        } else {
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onGesture?(.cancel)
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return Geometry.normalizedRect(from: startPoint, to: currentPoint)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(bounds.maxX, max(bounds.minX, point.x)), y: min(bounds.maxY, max(bounds.minY, point.y)))
    }
}
