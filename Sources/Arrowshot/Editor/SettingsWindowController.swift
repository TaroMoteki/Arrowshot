import AppKit
import Carbon.HIToolbox

/// A click-to-record field that captures a single keyboard shortcut.
@MainActor
final class HotKeyRecorderControl: NSView {
    var combo: HotKeyCombo {
        didSet { needsDisplay = true }
    }
    /// Called with a newly recorded, valid combo. Return `false` to reject it
    /// (e.g. a duplicate) and keep the previous value.
    var shouldAccept: ((HotKeyCombo) -> Bool)?
    var onChange: ((HotKeyCombo) -> Void)?

    private var recording = false {
        didSet { needsDisplay = true }
    }

    init(combo: HotKeyCombo) {
        self.combo = combo
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 26) }

    override func resignFirstResponder() -> Bool {
        recording = false
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if recording {
            recording = false
            window?.makeFirstResponder(nil)
        } else {
            window?.makeFirstResponder(self)
            recording = true
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        return handle(event)
    }

    override func keyDown(with event: NSEvent) {
        if recording, handle(event) { return }
        super.keyDown(with: event)
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard recording else { return false }

        let cleanFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Escape with no modifiers cancels recording.
        if event.keyCode == UInt32(kVK_Escape), cleanFlags.isEmpty {
            window?.makeFirstResponder(nil)
            return true
        }

        let candidate = HotKeyCombo(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: HotKeyModifierConversion.carbon(from: event.modifierFlags)
        )
        guard candidate.isValid else {
            // Needs at least ⌘/⌃/⌥. Stay in recording mode.
            NSSound.beep()
            return true
        }
        if shouldAccept?(candidate) == false {
            NSSound.beep()
            window?.makeFirstResponder(nil)
            return true
        }
        combo = candidate
        onChange?(candidate)
        window?.makeFirstResponder(nil)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)

        (recording
            ? NSColor.controlAccentColor.withAlphaComponent(0.12)
            : NSColor.controlBackgroundColor).setFill()
        path.fill()

        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text = recording ? NSLocalizedString("Type shortcut…", comment: "") : combo.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// Called after any shortcut changes so the app can re-register hot keys.
    var onHotKeysChanged: (() -> Void)?
    /// Called when the window closes so the app can restore its activation policy.
    var onClose: (() -> Void)?

    private var recorders: [HotKeyAction: HotKeyRecorderControl] = [:]
    private let saveFolderValueLabel = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Settings", comment: "")
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        guard let window, let contentView = window.contentView else { return }

        let heading = NSTextField(labelWithString: NSLocalizedString("Capture Shortcuts", comment: ""))
        heading.font = .systemFont(ofSize: 15, weight: .semibold)

        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing

        for action in HotKeyAction.allCases {
            let label = NSTextField(labelWithString: action.title)
            label.font = .systemFont(ofSize: 13)

            let recorder = HotKeyRecorderControl(combo: HotKeySettings.shared.combo(for: action))
            recorder.translatesAutoresizingMaskIntoConstraints = false
            recorder.widthAnchor.constraint(equalToConstant: 150).isActive = true
            recorder.heightAnchor.constraint(equalToConstant: 26).isActive = true
            recorder.shouldAccept = { [weak self] candidate in
                self?.isComboAvailable(candidate, for: action) ?? true
            }
            recorder.onChange = { [weak self] combo in
                self?.updateCombo(combo, for: action)
            }
            recorders[action] = recorder

            grid.addRow(with: [label, recorder])
        }

        let hint = NSTextField(labelWithString: NSLocalizedString("Click a field and press the new key combination (include ⌘, ⌃, or ⌥).", comment: ""))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2

        let resetButton = NSButton(title: NSLocalizedString("Reset to Defaults", comment: ""), target: self, action: #selector(resetDefaults))
        resetButton.bezelStyle = .rounded

        // Save location section.
        let saveHeading = NSTextField(labelWithString: NSLocalizedString("Save Folder (⌘S saves here instantly)", comment: ""))
        saveHeading.font = .systemFont(ofSize: 15, weight: .semibold)

        saveFolderValueLabel.font = .systemFont(ofSize: 12)
        saveFolderValueLabel.textColor = .secondaryLabelColor
        saveFolderValueLabel.lineBreakMode = .byTruncatingMiddle
        saveFolderValueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateSaveFolderLabel()

        let changeFolderButton = NSButton(title: NSLocalizedString("Change…", comment: ""), target: self, action: #selector(chooseSaveFolder))
        changeFolderButton.bezelStyle = .rounded
        let resetFolderButton = NSButton(title: NSLocalizedString("Reset to Downloads", comment: ""), target: self, action: #selector(resetSaveFolder))
        resetFolderButton.bezelStyle = .rounded
        let saveButtons = NSStackView(views: [changeFolderButton, resetFolderButton])
        saveButtons.spacing = 8
        let saveSection = NSStackView(views: [saveHeading, saveFolderValueLabel, saveButtons])
        saveSection.orientation = .vertical
        saveSection.alignment = .leading
        saveSection.spacing = 8

        // Reference list of the fixed editor shortcuts.
        let refHeading = NSTextField(labelWithString: NSLocalizedString("Editor Shortcuts", comment: ""))
        refHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        let refGrid = NSGridView(numberOfColumns: 2, rows: 0)
        refGrid.columnSpacing = 16
        refGrid.rowSpacing = 6
        refGrid.column(at: 0).xPlacement = .trailing
        let references: [(String, String)] = [
            (NSLocalizedString("Save / Save As", comment: ""), "⌘S / ⇧⌘S"),
            (NSLocalizedString("Copy", comment: ""), "⌘C"),
            (NSLocalizedString("Undo / Redo", comment: ""), "⌘Z / ⇧⌘Z"),
            (NSLocalizedString("Zoom In / Out / Fit", comment: ""), "⌘+ / ⌘- / ⌘0"),
            (NSLocalizedString("Open Settings", comment: ""), "⌘,"),
            (NSLocalizedString("Move Selection", comment: ""), NSLocalizedString("↑↓←→ (⇧ moves 10)", comment: "")),
            (NSLocalizedString("Switch Tools", comment: ""), NSLocalizedString("A Arrow  T Text  R Rect  O Ellipse  L Line  M Pixelate  C Crop", comment: ""))
        ]
        for (name, keys) in references {
            let n = NSTextField(labelWithString: name)
            n.font = .systemFont(ofSize: 12)
            n.textColor = .secondaryLabelColor
            let k = NSTextField(labelWithString: keys)
            k.font = .systemFont(ofSize: 12)
            k.lineBreakMode = .byWordWrapping
            k.maximumNumberOfLines = 2
            refGrid.addRow(with: [n, k])
        }

        // Timer duration section.
        let timerHeading = NSTextField(labelWithString: NSLocalizedString("Timer Length", comment: ""))
        timerHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        let timerSegmented = NSSegmentedControl(
            labels: [NSLocalizedString("3 sec", comment: ""), NSLocalizedString("5 sec", comment: "")],
            trackingMode: .selectOne,
            target: self,
            action: #selector(timerSecondsChanged(_:))
        )
        timerSegmented.selectedSegment = CaptureTimerSettings.seconds == 3 ? 0 : 1
        let timerSection = NSStackView(views: [timerHeading, timerSegmented])
        timerSection.orientation = .vertical
        timerSection.alignment = .leading
        timerSection.spacing = 8

        // Interface language section.
        let languageHeading = NSTextField(labelWithString: NSLocalizedString("Language", comment: ""))
        languageHeading.font = .systemFont(ofSize: 15, weight: .semibold)
        let languageSegmented = NSSegmentedControl(
            labels: AppLanguage.allCases.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(languageChanged(_:))
        )
        languageSegmented.selectedSegment = AppLanguage.current.rawValue
        let languageHint = NSTextField(labelWithString: NSLocalizedString("Takes effect after Arrowshot restarts.", comment: ""))
        languageHint.font = .systemFont(ofSize: 11)
        languageHint.textColor = .secondaryLabelColor
        let languageSection = NSStackView(views: [languageHeading, languageSegmented, languageHint])
        languageSection.orientation = .vertical
        languageSection.alignment = .leading
        languageSection.spacing = 8

        let divider1 = NSBox(); divider1.boxType = .separator
        let divider2 = NSBox(); divider2.boxType = .separator
        let divider3 = NSBox(); divider3.boxType = .separator
        let divider4 = NSBox(); divider4.boxType = .separator

        let stack = NSStackView(views: [
            heading, grid, hint, resetButton,
            divider1, saveSection,
            divider3, timerSection,
            divider4, languageSection,
            divider2, refHeading, refGrid
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(8, after: grid)
        stack.setCustomSpacing(18, after: resetButton)
        stack.setCustomSpacing(18, after: saveSection)
        stack.setCustomSpacing(18, after: timerSection)
        stack.setCustomSpacing(18, after: languageSection)
        stack.setCustomSpacing(8, after: refHeading)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            divider1.widthAnchor.constraint(equalTo: stack.widthAnchor),
            divider2.widthAnchor.constraint(equalTo: stack.widthAnchor),
            divider3.widthAnchor.constraint(equalTo: stack.widthAnchor),
            divider4.widthAnchor.constraint(equalTo: stack.widthAnchor),
            saveFolderValueLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @objc private func languageChanged(_ sender: NSSegmentedControl) {
        guard let language = AppLanguage(rawValue: sender.selectedSegment),
              language != AppLanguage.current else { return }
        AppLanguage.set(language)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Restart Arrowshot now to change the language?", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Restart Now", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))
        guard let window else { return }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                AppLanguage.relaunch()
            }
        }
    }

    @objc private func timerSecondsChanged(_ sender: NSSegmentedControl) {
        CaptureTimerSettings.setSeconds(sender.selectedSegment == 0 ? 3 : 5)
        onHotKeysChanged?()
    }

    private func updateSaveFolderLabel() {
        let folder = SaveLocation.folderURL
        let suffix = SaveLocation.isCustom ? "" : NSLocalizedString(" (Default)", comment: "")
        saveFolderValueLabel.stringValue = "📁 \(folder.path)\(suffix)"
    }

    @objc private func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = SaveLocation.folderURL
        panel.prompt = NSLocalizedString("Choose", comment: "")
        if let window {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                SaveLocation.setFolder(url)
                self?.updateSaveFolderLabel()
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            SaveLocation.setFolder(url)
            updateSaveFolderLabel()
        }
    }

    @objc private func resetSaveFolder() {
        SaveLocation.resetToDefault()
        updateSaveFolderLabel()
    }

    private func isComboAvailable(_ combo: HotKeyCombo, for action: HotKeyAction) -> Bool {
        for other in HotKeyAction.allCases where other != action {
            if HotKeySettings.shared.combo(for: other) == combo {
                presentDuplicateAlert()
                return false
            }
        }
        return true
    }

    private func presentDuplicateAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("This Shortcut Is Already in Use", comment: "")
        alert.informativeText = NSLocalizedString("Choose a different key combination.", comment: "")
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func updateCombo(_ combo: HotKeyCombo, for action: HotKeyAction) {
        HotKeySettings.shared.setCombo(combo, for: action)
        onHotKeysChanged?()
    }

    @objc private func resetDefaults() {
        HotKeySettings.shared.resetToDefaults()
        for action in HotKeyAction.allCases {
            recorders[action]?.combo = action.defaultCombo
        }
        onHotKeysChanged?()
    }

    func present() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
        onClose?()
    }
}
