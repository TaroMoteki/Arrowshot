import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut expressed with a Carbon virtual key code and a Carbon
/// modifier mask (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// A shortcut must include at least one of ⌘/⌃/⌥ so it does not swallow
    /// ordinary typing system-wide. Shift alone is not enough.
    var isValid: Bool {
        let required = UInt32(cmdKey | controlKey | optionKey)
        return carbonModifiers & required != 0
    }

    var displayString: String { HotKeyFormatter.string(for: self) }
}

enum HotKeyModifierConversion {
    static func carbon(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if cocoa.contains(.command) { result |= UInt32(cmdKey) }
        if cocoa.contains(.shift) { result |= UInt32(shiftKey) }
        if cocoa.contains(.option) { result |= UInt32(optionKey) }
        if cocoa.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    static func cocoa(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey) != 0 { result.insert(.command) }
        if carbon & UInt32(shiftKey) != 0 { result.insert(.shift) }
        if carbon & UInt32(optionKey) != 0 { result.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { result.insert(.control) }
        return result
    }
}

enum HotKeyFormatter {
    static func string(for combo: HotKeyCombo) -> String {
        var result = ""
        let modifiers = combo.carbonModifiers
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += keyLabel(for: combo.keyCode)
        return result
    }

    /// A lowercase character usable as an `NSMenuItem.keyEquivalent`, when the
    /// key code maps to one. Returns "" for keys that have no simple equivalent.
    static func menuKeyEquivalent(for keyCode: UInt32) -> String {
        menuEquivalents[Int(keyCode)] ?? ""
    }

    static func keyLabel(for keyCode: UInt32) -> String {
        keyLabels[Int(keyCode)] ?? "Key \(keyCode)"
    }

    private static let keyLabels: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Grave: "`",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12"
    ]

    private static let menuEquivalents: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d",
        kVK_ANSI_E: "e", kVK_ANSI_F: "f", kVK_ANSI_G: "g", kVK_ANSI_H: "h",
        kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
        kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p",
        kVK_ANSI_Q: "q", kVK_ANSI_R: "r", kVK_ANSI_S: "s", kVK_ANSI_T: "t",
        kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
        kVK_ANSI_Y: "y", kVK_ANSI_Z: "z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/"
    ]
}

/// The countdown length (seconds) used by the timer capture. 3 or 5.
enum CaptureTimerSettings {
    private static let key = "timerSeconds"

    static var seconds: Int {
        let value = UserDefaults.standard.integer(forKey: key)
        return value == 3 ? 3 : 5
    }

    static func setSeconds(_ seconds: Int) {
        UserDefaults.standard.set(seconds == 3 ? 3 : 5, forKey: key)
    }
}

/// Which capture a shortcut triggers. Also the persistence key.
enum HotKeyAction: String, CaseIterable {
    case immediate
    case timer
    case fullScreen

    var title: String {
        switch self {
        case .immediate: "十字スナップショット"
        case .timer: "タイマー十字スナップショット"
        case .fullScreen: "全画面スナップショット"
        }
    }

    var defaultCombo: HotKeyCombo {
        switch self {
        case .immediate:
            HotKeyCombo(keyCode: UInt32(kVK_ANSI_2), carbonModifiers: UInt32(cmdKey | shiftKey))
        case .timer:
            HotKeyCombo(keyCode: UInt32(kVK_ANSI_1), carbonModifiers: UInt32(cmdKey | shiftKey))
        case .fullScreen:
            HotKeyCombo(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: UInt32(cmdKey | shiftKey | optionKey))
        }
    }
}

/// Persists the user's shortcut choices in `UserDefaults`.
@MainActor
final class HotKeySettings {
    static let shared = HotKeySettings()

    private let defaults = UserDefaults.standard

    private init() {}

    func combo(for action: HotKeyAction) -> HotKeyCombo {
        let keyCodeKey = "hotkey.\(action.rawValue).keyCode"
        guard defaults.object(forKey: keyCodeKey) != nil else {
            return action.defaultCombo
        }
        let keyCode = UInt32(bitPattern: Int32(truncatingIfNeeded: defaults.integer(forKey: keyCodeKey)))
        let modifiers = UInt32(bitPattern: Int32(truncatingIfNeeded: defaults.integer(forKey: "hotkey.\(action.rawValue).mods")))
        return HotKeyCombo(keyCode: keyCode, carbonModifiers: modifiers)
    }

    func setCombo(_ combo: HotKeyCombo, for action: HotKeyAction) {
        defaults.set(Int(combo.keyCode), forKey: "hotkey.\(action.rawValue).keyCode")
        defaults.set(Int(combo.carbonModifiers), forKey: "hotkey.\(action.rawValue).mods")
    }

    func resetToDefaults() {
        for action in HotKeyAction.allCases {
            defaults.removeObject(forKey: "hotkey.\(action.rawValue).keyCode")
            defaults.removeObject(forKey: "hotkey.\(action.rawValue).mods")
        }
    }
}
