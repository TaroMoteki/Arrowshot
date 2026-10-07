import AppKit
import UniformTypeIdentifiers

/// The file formats Arrowshot can export. The default (used by ⌘S and drag
/// export, and preselected in Save As) is chosen in Settings.
enum ImageFormat: Int, CaseIterable {
    case png
    case jpeg

    private static let defaultsKey = "saveImageFormat"
    /// High enough that annotation edges stay clean, while files stay small.
    static let jpegQuality: CGFloat = 0.9

    static var preferred: ImageFormat {
        ImageFormat(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? .png
    }

    static func setPreferred(_ format: ImageFormat) {
        UserDefaults.standard.set(format.rawValue, forKey: defaultsKey)
    }

    var label: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    var pasteboardType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(contentType.identifier)
    }

    func data(for image: NSImage) -> Data? {
        switch self {
        case .png: return image.pngData()
        case .jpeg: return image.jpegData(quality: Self.jpegQuality)
        }
    }
}
