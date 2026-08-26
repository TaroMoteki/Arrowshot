import AppKit

enum ScreenCoordinates {
    static func cocoaPointToQuartz(_ point: CGPoint, primaryScreenHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    static func quartzPointToCocoa(_ point: CGPoint, primaryScreenHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    static func cocoaRectToQuartz(_ rect: CGRect, primaryScreenHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func quartzRectToCocoa(_ rect: CGRect, primaryScreenHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
