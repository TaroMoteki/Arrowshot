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
}
