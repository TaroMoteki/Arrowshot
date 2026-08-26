import AppKit
import CoreGraphics

enum CaptureMode {
    case immediate
    case timer
}

@MainActor
final class CaptureCoordinator {
    var onBusyChanged: ((Bool) -> Void)?

    private weak var editorWindowController: EditorWindowController?
    private let screenshotService = ScreenshotService()
    private var selectionController: SelectionOverlayController?
    private var captureTask: Task<Void, Never>?
    private var foregroundApplicationBeforeCapture: NSRunningApplication?
    private var shouldRestoreEditor = false
    private(set) var isBusy = false {
        didSet { onBusyChanged?(isBusy) }
    }

    init(editorWindowController: EditorWindowController) {
        self.editorWindowController = editorWindowController
    }

    func start(_ mode: CaptureMode) {
        guard !isBusy else {
            NSSound.beep()
            return
        }
        guard ensureScreenCapturePermission() else { return }

        isBusy = true
        foregroundApplicationBeforeCapture = NSWorkspace.shared.frontmostApplication
        shouldRestoreEditor = editorWindowController?.window?.isVisible == true
        editorWindowController?.hideEditor()
        let selectionController = SelectionOverlayController()
        self.selectionController = selectionController
        selectionController.begin { [weak self] selection in
            self?.selectionController = nil
            self?.handle(selection, mode: mode)
        }
    }

    func cancel() {
        selectionController?.cancel()
        captureTask?.cancel()
        captureTask = nil
        restoreEditorIfNeeded()
        isBusy = false
    }

    private func handle(_ selection: CaptureSelection, mode: CaptureMode) {
        switch selection {
        case .cancelled:
            foregroundApplicationBeforeCapture = nil
            restoreEditorIfNeeded()
            isBusy = false
        case .window(let windowID):
            captureTask = Task { [weak self] in
                await self?.captureWindow(windowID)
            }
        case .rectangle(let rect, let displayID):
            foregroundApplicationBeforeCapture = nil
            captureTask = Task { [weak self] in
                await self?.captureRectangle(rect, displayID: displayID, useTimer: mode == .timer)
            }
        }
    }

    private func captureWindow(_ windowID: CGWindowID) async {
        do {
            let image = try await screenshotService.captureWindow(windowID: windowID)
            await restoreForegroundApplication()
            shouldRestoreEditor = false
            editorWindowController?.presentCapturedImage(image)
        } catch is CancellationError {
            await restoreForegroundApplication()
            // The user cancelled the current capture.
        } catch {
            await restoreForegroundApplication()
            showCaptureError(error)
            restoreEditorIfNeeded()
        }
        captureTask = nil
        isBusy = false
    }

    private func restoreForegroundApplication() async {
        guard let application = foregroundApplicationBeforeCapture else { return }
        foregroundApplicationBeforeCapture = nil
        guard application.processIdentifier != getpid(), !application.isTerminated else { return }

        application.activate(options: [])
        for _ in 0..<10 where !application.isActive {
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                return
            }
        }
        if application.isActive {
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    private func captureRectangle(_ rect: CGRect, displayID: CGDirectDisplayID, useTimer: Bool) async {
        do {
            if useTimer {
                let countdown = CountdownPresenter()
                try await countdown.run(centeredOn: rect)
            }
            try Task.checkCancellation()
            let image = try await screenshotService.captureRectangle(rect, displayID: displayID)
            shouldRestoreEditor = false
            editorWindowController?.presentCapturedImage(image)
        } catch is CancellationError {
            // The user cancelled the current capture.
        } catch {
            showCaptureError(error)
            restoreEditorIfNeeded()
        }
        captureTask = nil
        isBusy = false
    }

    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        if CGRequestScreenCaptureAccess() {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "画面収録の許可が必要です"
        alert.informativeText = "システム設定の「プライバシーとセキュリティ」→「画面収録」でPictoJotを許可し、アプリを再起動してください。"
        alert.addButton(withTitle: "システム設定を開く")
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func showCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "画面をキャプチャできませんでした"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func restoreEditorIfNeeded() {
        if shouldRestoreEditor {
            editorWindowController?.showEditor()
        }
        shouldRestoreEditor = false
    }
}
