import Foundation

/// The folder where ⌘S saves images. Defaults to the user's Downloads folder,
/// overridable in Settings.
enum SaveLocation {
    private static let defaultsKey = "saveFolderPath"

    static var folderURL: URL {
        if let path = UserDefaults.standard.string(forKey: defaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultFolderURL
    }

    static var defaultFolderURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    static var isCustom: Bool {
        if let path = UserDefaults.standard.string(forKey: defaultsKey) { return !path.isEmpty }
        return false
    }

    static func setFolder(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
    }

    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// A non-colliding URL for `fileName` inside `folder` (appends " 2", " 3", …).
    static func uniqueURL(for fileName: String, in folder: URL) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = folder.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}
