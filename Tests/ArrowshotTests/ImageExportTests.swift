import AppKit
import XCTest
@testable import Arrowshot

final class ImageExportTests: XCTestCase {
    func testRenderedPNGUsesLogicalImageDimensionsOnRetinaDisplays() throws {
        let expectedSize = CGSize(width: 1022, height: 659)
        let rendered = try XCTUnwrap(PixelExactImageRenderer.render(size: expectedSize) { bounds in
            NSColor.systemBlue.setFill()
            bounds.fill()
        })
        let data = try XCTUnwrap(rendered.pngData())
        let representation = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertEqual(representation.pixelsWide, 1022)
        XCTAssertEqual(representation.pixelsHigh, 659)
    }

    func testJPEGKeepsPixelSizeAndUsesJPGExtension() throws {
        let rendered = try XCTUnwrap(PixelExactImageRenderer.render(size: CGSize(width: 1022, height: 659)) { bounds in
            NSColor.systemBlue.setFill()
            bounds.fill()
        })
        let data = try XCTUnwrap(ImageFormat.jpeg.data(for: rendered))
        let representation = try XCTUnwrap(NSBitmapImageRep(data: data))

        XCTAssertTrue(data.starts(with: [0xFF, 0xD8]))
        XCTAssertEqual(representation.pixelsWide, 1022)
        XCTAssertEqual(representation.pixelsHigh, 659)
        XCTAssertEqual(ImageFormat.jpeg.fileExtension, "jpg")
    }
}
