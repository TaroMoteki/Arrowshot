import AppKit
import ScreenCaptureKit

enum ScreenshotServiceError: LocalizedError {
    case displayNotFound
    case windowNotFound
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "対象ディスプレイを取得できませんでした。"
        case .windowNotFound: "対象ウインドウを取得できませんでした。"
        case .emptySelection: "選択範囲が小さすぎます。"
        }
    }
}

@MainActor
struct ScreenshotService {
    func captureRectangle(_ globalRect: CGRect, displayID: CGDirectDisplayID) async throws -> NSImage {
        guard globalRect.width >= 2, globalRect.height >= 2 else {
            throw ScreenshotServiceError.emptySelection
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotServiceError.displayNotFound
        }

        let ownApplications = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let localRect = CGRect(
            x: globalRect.minX - display.frame.minX,
            y: globalRect.minY - display.frame.minY,
            width: globalRect.width,
            height: globalRect.height
        ).intersection(CGRect(origin: .zero, size: display.frame.size))
        guard localRect.width >= 2, localRect.height >= 2 else {
            throw ScreenshotServiceError.emptySelection
        }

        let outputSize = CaptureOutputSizing.nativePixels(
            forLogicalSize: localRect.size,
            pointPixelScale: CGFloat(filter.pointPixelScale)
        )
        configuration.sourceRect = localRect
        configuration.width = outputSize.width
        configuration.height = outputSize.height
        configuration.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return Self.nativeImage(cgImage, pointPixelScale: CGFloat(filter.pointPixelScale))
    }

    func captureDisplay(displayID: CGDirectDisplayID) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw ScreenshotServiceError.displayNotFound
        }

        let ownApplications = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let outputSize = CaptureOutputSizing.nativePixels(
            forLogicalSize: display.frame.size,
            pointPixelScale: CGFloat(filter.pointPixelScale)
        )
        configuration.width = outputSize.width
        configuration.height = outputSize.height
        configuration.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return Self.nativeImage(cgImage, pointPixelScale: CGFloat(filter.pointPixelScale))
    }

    func captureWindow(windowID: CGWindowID) async throws -> NSImage {
        var content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard var targetWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenshotServiceError.windowNotFound
        }

        // The selection overlay temporarily activates PictoJot. Restore the selected
        // application's active appearance before taking the actual screenshot.
        if let processID = targetWindow.owningApplication?.processID,
           let application = NSRunningApplication(processIdentifier: processID),
           !application.isActive {
            application.activate(options: [])
            for _ in 0..<10 where !application.isActive {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(20))
            }
            try await Task.sleep(for: .milliseconds(120))

            // Refresh the SCWindow after activation so controls and title bars are
            // captured from the newly rendered active-window state.
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let refreshedWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenshotServiceError.windowNotFound
            }
            targetWindow = refreshedWindow
        }

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        let configuration = SCStreamConfiguration()
        let outputSize = CaptureOutputSizing.nativePixels(
            forLogicalSize: targetWindow.frame.size,
            pointPixelScale: CGFloat(filter.pointPixelScale)
        )
        configuration.width = outputSize.width
        configuration.height = outputSize.height
        configuration.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return Self.nativeImage(cgImage, pointPixelScale: CGFloat(filter.pointPixelScale))
    }

    /// Wraps the captured bitmap without resampling it. Every native (Retina)
    /// pixel is kept, while `size` stays in points so one image point still maps
    /// to one screen point on screen and in the editor's coordinates.
    private static func nativeImage(_ cgImage: CGImage, pointPixelScale: CGFloat) -> NSImage {
        let scale = max(1, pointPixelScale)
        let logicalSize = CGSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        )
        return NSImage(cgImage: cgImage, size: logicalSize)
    }
}
