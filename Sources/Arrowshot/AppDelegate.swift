import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
private final class MinimalEditMenuDelegate: NSObject, NSMenuDelegate {
    private let permittedItems: [NSMenuItem]

    init(permittedItems: [NSMenuItem]) {
        self.permittedItems = permittedItems
    }

    func menuWillOpen(_ menu: NSMenu) {
        let permittedIdentifiers = Set(permittedItems.map(ObjectIdentifier.init))
        for item in menu.items where !permittedIdentifiers.contains(ObjectIdentifier(item)) {
            menu.removeItem(item)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var immediateCaptureItem: NSMenuItem!
    private var timerCaptureItem: NSMenuItem!
    private var timer3CaptureItem: NSMenuItem!
    private var timer5CaptureItem: NSMenuItem!
    private var fullScreenCaptureItem: NSMenuItem!
    private let editorWindowController = EditorWindowController()
    private var captureCoordinator: CaptureCoordinator!
    private var editMenuDelegate: MinimalEditMenuDelegate?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        editorWindowController.onVisibilityChanged = { [weak self] isVisible in
            self?.updateApplicationPresentation(editorIsVisible: isVisible)
        }
        captureCoordinator = CaptureCoordinator(editorWindowController: editorWindowController)
        captureCoordinator.onBusyChanged = { [weak self] busy in
            self?.immediateCaptureItem.isEnabled = !busy
            self?.timerCaptureItem.isEnabled = !busy
            self?.timer3CaptureItem.isEnabled = !busy
            self?.timer5CaptureItem.isEnabled = !busy
            self?.fullScreenCaptureItem.isEnabled = !busy
        }
        configureMainMenu()
        configureStatusItem()
        configureGlobalHotKeys()
        DispatchQueue.main.async { [weak self] in
            self?.promptForLaunchAtLoginIfNeeded()
        }
    }

    private func configureGlobalHotKeys() {
        applyHotKeys()
    }

    /// (Re)registers the global shortcuts from the saved settings and refreshes
    /// the shortcut hints shown in the menu.
    private func applyHotKeys() {
        let settings = HotKeySettings.shared

        GlobalHotKeyCenter.shared.setHotKey(
            name: HotKeyAction.immediate.rawValue,
            combo: settings.combo(for: .immediate)
        ) { [weak self] in
            guard let self, self.immediateCaptureItem.isEnabled else { return }
            self.startImmediateCapture()
        }
        GlobalHotKeyCenter.shared.setHotKey(
            name: HotKeyAction.timer.rawValue,
            combo: settings.combo(for: .timer)
        ) { [weak self] in
            guard let self, self.timerCaptureItem.isEnabled else { return }
            self.startTimerCapture()
        }
        GlobalHotKeyCenter.shared.setHotKey(
            name: HotKeyAction.fullScreen.rawValue,
            combo: settings.combo(for: .fullScreen)
        ) { [weak self] in
            guard let self, self.fullScreenCaptureItem.isEnabled else { return }
            self.startFullScreenCapture()
        }

        updateCaptureMenuShortcut(immediateCaptureItem, combo: settings.combo(for: .immediate))
        updateCaptureMenuShortcut(timerCaptureItem, combo: settings.combo(for: .timer))
        updateCaptureMenuShortcut(fullScreenCaptureItem, combo: settings.combo(for: .fullScreen))
        timerCaptureItem.title = "タイマー十字スナップショット（\(CaptureTimerSettings.seconds)秒）"

        // Fixed global shortcut to open Settings, so the menu-bar icon is never
        // needed even when it is buried among other menu-bar items.
        GlobalHotKeyCenter.shared.setHotKey(
            name: "openSettings",
            combo: HotKeyCombo(keyCode: UInt32(kVK_ANSI_Comma), carbonModifiers: UInt32(cmdKey | shiftKey))
        ) { [weak self] in
            self?.openSettings()
        }
    }

    private func updateCaptureMenuShortcut(_ item: NSMenuItem?, combo: HotKeyCombo) {
        guard let item else { return }
        item.keyEquivalent = HotKeyFormatter.menuKeyEquivalent(for: combo.keyCode)
        item.keyEquivalentModifierMask = HotKeyModifierConversion.cocoa(from: combo.carbonModifiers)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        editorWindowController.openImage(at: url)
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureCoordinator?.cancel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            editorWindowController.showEditor()
        }
        return true
    }

    /// A monochrome (template) menu-bar icon matching the Arrowshot app icon's
    /// viewfinder motif: four corner marks framing a center crosshair.
    private static func statusBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setStroke()

            let frame = NSRect(x: 2.5, y: 2.5, width: 13, height: 13)
            let arm: CGFloat = 3.4
            let marks = NSBezierPath()
            marks.lineWidth = 1.6
            marks.lineCapStyle = .round
            marks.lineJoinStyle = .round
            // Top-left
            marks.move(to: NSPoint(x: frame.minX, y: frame.maxY - arm))
            marks.line(to: NSPoint(x: frame.minX, y: frame.maxY))
            marks.line(to: NSPoint(x: frame.minX + arm, y: frame.maxY))
            // Top-right
            marks.move(to: NSPoint(x: frame.maxX - arm, y: frame.maxY))
            marks.line(to: NSPoint(x: frame.maxX, y: frame.maxY))
            marks.line(to: NSPoint(x: frame.maxX, y: frame.maxY - arm))
            // Bottom-right
            marks.move(to: NSPoint(x: frame.maxX, y: frame.minY + arm))
            marks.line(to: NSPoint(x: frame.maxX, y: frame.minY))
            marks.line(to: NSPoint(x: frame.maxX - arm, y: frame.minY))
            // Bottom-left
            marks.move(to: NSPoint(x: frame.minX + arm, y: frame.minY))
            marks.line(to: NSPoint(x: frame.minX, y: frame.minY))
            marks.line(to: NSPoint(x: frame.minX, y: frame.minY + arm))
            marks.stroke()

            let crossHalf: CGFloat = 2.4
            let crosshair = NSBezierPath()
            crosshair.lineWidth = 1.6
            crosshair.lineCapStyle = .round
            crosshair.move(to: NSPoint(x: frame.midX - crossHalf, y: frame.midY))
            crosshair.line(to: NSPoint(x: frame.midX + crossHalf, y: frame.midY))
            crosshair.move(to: NSPoint(x: frame.midX, y: frame.midY - crossHalf))
            crosshair.line(to: NSPoint(x: frame.midX, y: frame.midY + crossHalf))
            crosshair.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = AppDelegate.statusBarIcon()
            button.toolTip = "Arrowshot"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        immediateCaptureItem = NSMenuItem(
            title: "十字スナップショット",
            action: #selector(startImmediateCapture),
            keyEquivalent: "2"
        )
        immediateCaptureItem.keyEquivalentModifierMask = [.command, .shift]
        immediateCaptureItem.target = self

        timerCaptureItem = NSMenuItem(
            title: "タイマー十字スナップショット",
            action: #selector(startTimerCapture),
            keyEquivalent: "1"
        )
        timerCaptureItem.keyEquivalentModifierMask = [.command, .shift]
        timerCaptureItem.target = self

        timer3CaptureItem = NSMenuItem(
            title: "3秒タイマー",
            action: #selector(startTimerCapture3),
            keyEquivalent: ""
        )
        timer3CaptureItem.target = self

        timer5CaptureItem = NSMenuItem(
            title: "5秒タイマー",
            action: #selector(startTimerCapture5),
            keyEquivalent: ""
        )
        timer5CaptureItem.target = self

        fullScreenCaptureItem = NSMenuItem(
            title: "全画面スナップショット",
            action: #selector(startFullScreenCapture),
            keyEquivalent: ""
        )
        fullScreenCaptureItem.target = self

        let showItem = NSMenuItem(
            title: "Arrowshotを表示",
            action: #selector(showEditor),
            keyEquivalent: ""
        )
        showItem.target = self

        let settingsItem = NSMenuItem(
            title: "設定…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self

        let quitItem = NSMenuItem(title: "Arrowshotを終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(immediateCaptureItem)
        menu.addItem(timerCaptureItem)
        menu.addItem(timer3CaptureItem)
        menu.addItem(timer5CaptureItem)
        menu.addItem(fullScreenCaptureItem)
        menu.addItem(.separator())
        menu.addItem(showItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem(title: "Arrowshot", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "Arrowshot")
        let aboutItem = NSMenuItem(
            title: "Arrowshotについて",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        applicationMenu.addItem(aboutItem)
        applicationMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "設定…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())

        let hideItem = NSMenuItem(title: "Arrowshotを隠す", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        applicationMenu.addItem(hideItem)

        applicationMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Arrowshotを終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let fileItem = NSMenuItem(title: "ファイル", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "ファイル")
        let openItem = NSMenuItem(
            title: "開く…",
            action: #selector(EditorWindowController.openImagePanel),
            keyEquivalent: "o"
        )
        openItem.target = editorWindowController
        fileMenu.addItem(openItem)

        let saveItem = NSMenuItem(
            title: "保存",
            action: #selector(EditorWindowController.saveImage),
            keyEquivalent: "s"
        )
        saveItem.target = editorWindowController
        fileMenu.addItem(saveItem)

        let saveAsItem = NSMenuItem(
            title: "名前を付けて保存…",
            action: #selector(EditorWindowController.saveAsImage),
            keyEquivalent: "s"
        )
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        saveAsItem.target = editorWindowController
        fileMenu.addItem(saveAsItem)
        fileMenu.addItem(.separator())

        let closeItem = NSMenuItem(title: "閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.target = editorWindowController.window
        fileMenu.addItem(closeItem)
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem(title: "編集", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "編集")
        let undoItem = NSMenuItem(
            title: "取り消す",
            action: #selector(EditorWindowController.undoEdit),
            keyEquivalent: "z"
        )
        undoItem.target = editorWindowController
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(
            title: "やり直す",
            action: #selector(EditorWindowController.redoEdit),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = editorWindowController
        editMenu.addItem(redoItem)
        let editSeparator = NSMenuItem.separator()
        editMenu.addItem(editSeparator)

        let copyItem = NSMenuItem(
            title: "コピー",
            action: #selector(EditorWindowController.copyImage),
            keyEquivalent: "c"
        )
        copyItem.target = editorWindowController
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(
            title: "ペースト",
            action: #selector(EditorWindowController.pasteImage),
            keyEquivalent: "v"
        )
        pasteItem.target = editorWindowController
        editMenu.addItem(pasteItem)
        let editMenuDelegate = MinimalEditMenuDelegate(
            permittedItems: [undoItem, redoItem, editSeparator, copyItem, pasteItem]
        )
        editMenu.delegate = editMenuDelegate
        self.editMenuDelegate = editMenuDelegate
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem(title: "表示", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "表示")
        let zoomInItem = NSMenuItem(
            title: "拡大",
            action: #selector(EditorWindowController.zoomIn),
            keyEquivalent: "+"
        )
        zoomInItem.keyEquivalentModifierMask = [.command]
        zoomInItem.target = editorWindowController
        viewMenu.addItem(zoomInItem)

        // Also accept ⌘= (same physical key as ⌘+ without Shift).
        let zoomInAltItem = NSMenuItem(
            title: "拡大",
            action: #selector(EditorWindowController.zoomIn),
            keyEquivalent: "="
        )
        zoomInAltItem.keyEquivalentModifierMask = [.command]
        zoomInAltItem.target = editorWindowController
        zoomInAltItem.isAlternate = false
        zoomInAltItem.isHidden = true
        viewMenu.addItem(zoomInAltItem)

        let zoomOutItem = NSMenuItem(
            title: "縮小",
            action: #selector(EditorWindowController.zoomOut),
            keyEquivalent: "-"
        )
        zoomOutItem.keyEquivalentModifierMask = [.command]
        zoomOutItem.target = editorWindowController
        viewMenu.addItem(zoomOutItem)

        let zoomFitItem = NSMenuItem(
            title: "全体表示（フィット）",
            action: #selector(EditorWindowController.zoomFit),
            keyEquivalent: "0"
        )
        zoomFitItem.keyEquivalentModifierMask = [.command]
        zoomFitItem.target = editorWindowController
        viewMenu.addItem(zoomFitItem)

        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        NSApp.mainMenu = mainMenu
    }

    /// 常に .regular を維持する。起動後に .accessory から昇格したアプリは
    /// Cmd+Tab のリスト末尾に追加されたまま MRU（最近使った順）で繰り上がらないため、
    /// 起動時点から通常アプリとして登録しておく必要がある。
    private func updateApplicationPresentation(editorIsVisible: Bool) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        if editorIsVisible {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func promptForLaunchAtLoginIfNeeded() {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard bundleURL.path == "/Applications/Arrowshot.app" else { return }

        let defaults = UserDefaults.standard
        let promptKey = "didPromptForLaunchAtLogin"
        guard !defaults.bool(forKey: promptKey) else { return }

        let service = SMAppService.mainApp
        if service.status == .enabled {
            defaults.set(true, forKey: promptKey)
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "ログイン時にArrowshotを開きますか？"
        alert.informativeText = "有効にすると、Macへのログイン時にArrowshotが自動的に起動してメニューバーに常駐します。"
        alert.addButton(withTitle: "自動起動を有効にする")
        alert.addButton(withTitle: "今はしない")

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try service.register()
                defaults.set(true, forKey: promptKey)
                if service.status == .requiresApproval {
                    showLaunchAtLoginApprovalNotice()
                }
            } catch {
                showLaunchAtLoginError(error)
            }
        } else {
            defaults.set(true, forKey: promptKey)
        }

        updateApplicationPresentation(editorIsVisible: editorWindowController.window?.isVisible == true)
    }

    private func showLaunchAtLoginApprovalNotice() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "ログイン項目の許可が必要です"
        alert.informativeText = "システム設定の「一般」>「ログイン項目」でArrowshotを許可してください。"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "自動起動を設定できませんでした"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func startImmediateCapture() {
        captureCoordinator.start(.immediate)
    }

    @objc private func startTimerCapture() {
        captureCoordinator.start(.timer, timerSeconds: CaptureTimerSettings.seconds)
    }

    @objc private func startTimerCapture3() {
        captureCoordinator.start(.timer, timerSeconds: 3)
    }

    @objc private func startTimerCapture5() {
        captureCoordinator.start(.timer, timerSeconds: 5)
    }

    @objc private func startFullScreenCapture() {
        captureCoordinator.start(.fullScreen)
    }

    @objc private func showEditor() {
        editorWindowController.showEditor()
    }

    @objc private func openSettings() {
        let controller: SettingsWindowController
        if let existing = settingsWindowController {
            controller = existing
        } else {
            controller = SettingsWindowController()
            controller.onHotKeysChanged = { [weak self] in
                self?.applyHotKeys()
            }
            controller.onClose = { [weak self] in
                guard let self else { return }
                self.updateApplicationPresentation(
                    editorIsVisible: self.editorWindowController.window?.isVisible == true
                )
            }
            settingsWindowController = controller
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.present()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
