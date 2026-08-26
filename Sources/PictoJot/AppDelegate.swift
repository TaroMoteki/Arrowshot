import AppKit
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
    private let editorWindowController = EditorWindowController()
    private var captureCoordinator: CaptureCoordinator!
    private var editMenuDelegate: MinimalEditMenuDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        editorWindowController.onVisibilityChanged = { [weak self] isVisible in
            self?.updateApplicationPresentation(editorIsVisible: isVisible)
        }
        captureCoordinator = CaptureCoordinator(editorWindowController: editorWindowController)
        captureCoordinator.onBusyChanged = { [weak self] busy in
            self?.immediateCaptureItem.isEnabled = !busy
            self?.timerCaptureItem.isEnabled = !busy
        }
        configureMainMenu()
        configureStatusItem()
        DispatchQueue.main.async { [weak self] in
            self?.promptForLaunchAtLoginIfNeeded()
        }
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

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "PictoJot")
            button.image?.isTemplate = true
            button.toolTip = "PictoJot"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        immediateCaptureItem = NSMenuItem(
            title: "十字スナップショット",
            action: #selector(startImmediateCapture),
            keyEquivalent: ""
        )
        immediateCaptureItem.target = self

        timerCaptureItem = NSMenuItem(
            title: "タイマー十字スナップショット",
            action: #selector(startTimerCapture),
            keyEquivalent: ""
        )
        timerCaptureItem.target = self

        let showItem = NSMenuItem(
            title: "PictoJotを表示",
            action: #selector(showEditor),
            keyEquivalent: ""
        )
        showItem.target = self

        let quitItem = NSMenuItem(title: "PictoJotを終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(immediateCaptureItem)
        menu.addItem(timerCaptureItem)
        menu.addItem(.separator())
        menu.addItem(showItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem(title: "PictoJot", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "PictoJot")
        let aboutItem = NSMenuItem(
            title: "PictoJotについて",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        applicationMenu.addItem(aboutItem)
        applicationMenu.addItem(.separator())

        let hideItem = NSMenuItem(title: "PictoJotを隠す", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        applicationMenu.addItem(hideItem)

        applicationMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "PictoJotを終了", action: #selector(quit), keyEquivalent: "q")
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
            title: "保存…",
            action: #selector(EditorWindowController.saveImage),
            keyEquivalent: "s"
        )
        saveItem.target = editorWindowController
        fileMenu.addItem(saveItem)
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

        NSApp.mainMenu = mainMenu
    }

    private func updateApplicationPresentation(editorIsVisible: Bool) {
        let activationPolicy: NSApplication.ActivationPolicy = editorIsVisible ? .regular : .accessory
        if NSApp.activationPolicy() != activationPolicy {
            NSApp.setActivationPolicy(activationPolicy)
        }
        if editorIsVisible {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func promptForLaunchAtLoginIfNeeded() {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        guard bundleURL.path == "/Applications/PictoJot.app" else { return }

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
        alert.messageText = "ログイン時にPictoJotを開きますか？"
        alert.informativeText = "有効にすると、Macへのログイン時にPictoJotが自動的に起動してメニューバーに常駐します。"
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
        alert.informativeText = "システム設定の「一般」>「ログイン項目」でPictoJotを許可してください。"
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
        captureCoordinator.start(.timer)
    }

    @objc private func showEditor() {
        editorWindowController.showEditor()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
