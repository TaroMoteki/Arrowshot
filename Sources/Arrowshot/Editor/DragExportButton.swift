import AppKit

/// A toolbar button you drag from to drop the current image into Finder, chat
/// apps, Mail, browsers, and so on — like Shottr's drag-out handle.
///
/// The drag carries several representations at once so almost any target works:
/// a real (temporary) file in the default format from Settings for file-based
/// targets, plus raw image data for targets that accept it directly (chat
/// boxes, web drop zones).
@MainActor
final class DragExportButton: NSButton, NSDraggingSource {
    /// Returns the flattened image to export, or nil when there is nothing to drag.
    var imageProvider: (() -> NSImage?)?
    /// Returns the file name (with the format's extension) for the dropped file.
    var fileNameProvider: ((ImageFormat) -> String)?
    /// Called once, when the drag has moved `moveAwayDistance` points from where it
    /// started (used to hide the editor window so it does not cover the drop target).
    var onDragMovedAway: (() -> Void)?
    /// Called when the drag finishes. `dropped` is false when the drag was cancelled.
    var onDragEnded: ((_ dropped: Bool) -> Void)?
    /// How far the cursor must travel before `onDragMovedAway` fires, so a click or
    /// a small wiggle does not make the editor disappear.
    var moveAwayDistance: CGFloat = 150

    private var dragStartPoint: NSPoint?

    override func mouseDown(with event: NSEvent) {
        let format = ImageFormat.preferred
        guard let image = imageProvider?(), let data = format.data(for: image) else {
            NSSound.beep()
            return
        }
        let fileName = fileNameProvider?(format) ?? "Arrowshot.\(format.fileExtension)"

        // Write a real temporary file so file-based drop targets get an actual
        // file without the user having to save first.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ArrowshotDrags", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSSound.beep()
            return
        }

        let item = NSPasteboardItem()
        item.setData(data, forType: format.pasteboardType)
        if let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        item.setString(fileURL.absoluteString, forType: .fileURL)

        let draggingItem = NSDraggingItem(pasteboardWriter: item)

        // Show a small thumbnail of the image under the cursor while dragging.
        let maxSide: CGFloat = 160
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let thumbSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let frame = NSRect(
            x: bounds.midX - thumbSize.width / 2,
            y: bounds.midY - thumbSize.height / 2,
            width: max(thumbSize.width, 1),
            height: max(thumbSize.height, 1)
        )
        draggingItem.setDraggingFrame(frame, contents: image)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        dragStartPoint = screenPoint
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard let start = dragStartPoint else { return }
        if hypot(screenPoint.x - start.x, screenPoint.y - start.y) >= moveAwayDistance {
            dragStartPoint = nil
            onDragMovedAway?()
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        dragStartPoint = nil
        onDragEnded?(!operation.isEmpty)
    }
}
