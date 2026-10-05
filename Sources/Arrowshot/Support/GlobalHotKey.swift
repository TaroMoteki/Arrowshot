import AppKit
import Carbon.HIToolbox

/// Registers system-wide keyboard shortcuts using the Carbon Event Manager.
///
/// `RegisterEventHotKey` works even while the app runs as a menu-bar accessory
/// and does not require Accessibility permission, so a shortcut can trigger a
/// capture without the Arrowshot menu being open.
@MainActor
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var namedHotKeys: [String: (id: UInt32, ref: EventHotKeyRef)] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    // Four-char signature 'PJHK' identifying Arrowshot's hot keys.
    private let signature: OSType = 0x504A_484B

    private init() {}

    /// Registers (or replaces) a global shortcut under `name`. Passing an
    /// invalid or `nil` combo just clears any existing shortcut for that name.
    @discardableResult
    func setHotKey(name: String, combo: HotKeyCombo?, handler: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()

        if let existing = namedHotKeys[name] {
            UnregisterEventHotKey(existing.ref)
            handlers[existing.id] = nil
            namedHotKeys[name] = nil
        }

        guard let combo, combo.isValid else { return false }

        let id = nextID
        nextID += 1
        handlers[id] = handler

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            handlers[id] = nil
            return false
        }
        namedHotKeys[name] = (id, ref)
        return true
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    OSType(kEventParamDirectObject),
                    OSType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    GlobalHotKeyCenter.shared.handlers[id]?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }
}
