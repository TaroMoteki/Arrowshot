import CoreGraphics
import XCTest
@testable import Arrowshot

final class ScreenCoordinatesTests: XCTestCase {
    func testSecondaryDisplayOverlayUsesScreenRelativeOrigin() {
        let secondaryScreen = CGRect(x: 1920, y: -240, width: 2560, height: 1440)
        let contentRect = OverlayWindowGeometry.contentRect(forScreenFrame: secondaryScreen)

        XCTAssertEqual(contentRect, CGRect(x: 0, y: 0, width: 2560, height: 1440))
    }

    func testCaptureOutputDoesNotApplyRetinaScaleTwice() {
        let output = CaptureOutputSizing.pixels(
            forLogicalSize: CGSize(width: 1475, height: 1007)
        )

        XCTAssertEqual(output.width, 1475)
        XCTAssertEqual(output.height, 1007)
    }

    func testCocoaRectConvertsToQuartzCoordinates() {
        let cocoaRect = CGRect(x: 100, y: 700, width: 200, height: 100)
        let quartzRect = ScreenCoordinates.cocoaRectToQuartz(cocoaRect, primaryScreenHeight: 1000)

        XCTAssertEqual(quartzRect, CGRect(x: 100, y: 200, width: 200, height: 100))
    }

    func testCoordinateRoundTrip() {
        let original = CGRect(x: -500, y: 120, width: 320, height: 240)
        let quartz = ScreenCoordinates.cocoaRectToQuartz(original, primaryScreenHeight: 982)
        let roundTrip = ScreenCoordinates.quartzRectToCocoa(quartz, primaryScreenHeight: 982)

        XCTAssertEqual(roundTrip, original)
    }

    func testCoordinateRoundTripForDisplayRightOfPrimary() {
        let original = CGRect(x: 1920, y: -240, width: 640, height: 480)
        let quartz = ScreenCoordinates.cocoaRectToQuartz(original, primaryScreenHeight: 1080)
        let roundTrip = ScreenCoordinates.quartzRectToCocoa(quartz, primaryScreenHeight: 1080)

        XCTAssertEqual(roundTrip, original)
    }
}
