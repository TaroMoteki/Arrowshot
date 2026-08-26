import AppKit

@MainActor
final class CountdownPresenter {
    private var window: NSWindow?
    private let label = NSTextField(labelWithString: "5")

    func run(centeredOn quartzRect: CGRect) async throws {
        let cocoaRect = ScreenCoordinates.quartzRectToCocoa(quartzRect)
        let size = CGSize(width: 104, height: 104)
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
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true

        label.frame = background.bounds
        label.alignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: 58, weight: .bold)
        label.textColor = .white
        background.addSubview(label)
        window.contentView = background
        self.window = window
        window.orderFrontRegardless()

        do {
            for count in stride(from: 5, through: 1, by: -1) {
                label.stringValue = "\(count)"
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
