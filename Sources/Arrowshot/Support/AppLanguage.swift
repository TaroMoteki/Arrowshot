import AppKit

/// The interface language chosen in Settings. It is stored as this app's own
/// `AppleLanguages`, the same value macOS writes for a per-app language, so it
/// takes effect the next time Arrowshot launches.
enum AppLanguage: Int, CaseIterable {
    case system
    case english
    case japanese

    private static let defaultsKey = "AppleLanguages"

    /// Shown in the language's own name so anyone can find their language.
    var label: String {
        switch self {
        case .system: NSLocalizedString("System", comment: "Follow the macOS language")
        case .english: "English"
        case .japanese: "日本語"
        }
    }

    static var current: AppLanguage {
        // Read only the app's own domain; the global domain always has a value.
        guard let identifier = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: identifier)?[defaultsKey] as? [String],
              let first = languages.first else { return .system }
        if first.hasPrefix("ja") { return .japanese }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    static func set(_ language: AppLanguage) {
        switch language {
        case .system: UserDefaults.standard.removeObject(forKey: defaultsKey)
        case .english: UserDefaults.standard.set(["en"], forKey: defaultsKey)
        case .japanese: UserDefaults.standard.set(["ja"], forKey: defaultsKey)
        }
    }

    /// Quits and reopens Arrowshot so the new language applies. A helper shell
    /// waits for this process to exit (up to 30 seconds) before reopening, so the
    /// two instances never hold the global shortcuts at the same time.
    static func relaunch() {
        let processID = ProcessInfo.processInfo.processIdentifier
        let bundlePath = Bundle.main.bundlePath
        let script = """
        for _ in $(seq 1 150); do kill -0 \(processID) 2>/dev/null || { /usr/bin/open "$0"; exit 0; }; sleep 0.2; done
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script, bundlePath]
        try? helper.run()
        NSApp.terminate(nil)
    }
}
