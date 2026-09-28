import XCTest
@testable import FormBuddy

/// The feedback surface must never crop or overflow its viewport: a tall
/// portrait clip has to scale down to fit, and zoom must clamp and reset.
final class VideoFitGeometryTests: XCTestCase {

    func testMaximumHeightFallsBackBeforeViewportIsMeasured() {
        XCTAssertEqual(VideoFitGeometry.maximumHeight(viewport: 0), 460)
        XCTAssertEqual(VideoFitGeometry.maximumHeight(viewport: .nan), 460)
    }

    func testMaximumHeightClampsToRange() {
        XCTAssertEqual(VideoFitGeometry.maximumHeight(viewport: 400), 320)   // 220 -> floor
        XCTAssertEqual(VideoFitGeometry.maximumHeight(viewport: 700), 385, accuracy: 0.001)  // 385 within
        XCTAssertEqual(VideoFitGeometry.maximumHeight(viewport: 2000), 560)  // 1100 -> ceiling
    }

    func testFittedSizeIsWidthLimitedForWideVideo() {
        // 16:9 in a 320x500 slot: width fills, height follows.
        let size = VideoFitGeometry.fittedSize(
            aspect: 16.0 / 9.0,
            available: CGSize(width: 320, height: 500)
        )
        XCTAssertEqual(size.width, 320, accuracy: 0.001)
        XCTAssertEqual(size.height, 180, accuracy: 0.001)
    }

    func testFittedSizeZoomsOutForTallVideo() {
        // 9:16 in a 320x400 slot: the natural height (569) is too tall, so it
        // scales down to the available height instead of overflowing.
        let size = VideoFitGeometry.fittedSize(
            aspect: 9.0 / 16.0,
            available: CGSize(width: 320, height: 400)
        )
        XCTAssertEqual(size.height, 400, accuracy: 0.001)
        XCTAssertEqual(size.width, 225, accuracy: 0.001)
        XCTAssertLessThanOrEqual(size.height, 400)
    }

    func testFittedSizePreservesAspect() {
        let aspect: CGFloat = 3.0 / 4.0
        let size = VideoFitGeometry.fittedSize(
            aspect: aspect,
            available: CGSize(width: 200, height: 600)
        )
        XCTAssertEqual(size.width / size.height, aspect, accuracy: 0.0001)
    }

    func testFittedSizeRejectsDegenerateInput() {
        XCTAssertEqual(VideoFitGeometry.fittedSize(aspect: 0, available: CGSize(width: 100, height: 100)), .zero)
        XCTAssertEqual(VideoFitGeometry.fittedSize(aspect: 1, available: .zero), .zero)
        XCTAssertEqual(VideoFitGeometry.fittedSize(aspect: .nan, available: CGSize(width: 100, height: 100)), .zero)
    }

    func testFittedRectCentersTheVideo() {
        let rect = VideoFitGeometry.fittedRect(
            aspect: 9.0 / 16.0,
            available: CGSize(width: 390, height: 844)
        )
        XCTAssertEqual(rect.height, 693.5, accuracy: 0.5)
        XCTAssertEqual(rect.midX, 195, accuracy: 0.5)
        XCTAssertEqual(rect.midY, 422, accuracy: 0.5)
    }

    func testZoomClampAndEffective() {
        XCTAssertEqual(VideoFitGeometry.clampedZoom(0.2), 1)
        XCTAssertEqual(VideoFitGeometry.clampedZoom(9), 5)
        XCTAssertEqual(VideoFitGeometry.clampedZoom(2), 2)
        XCTAssertEqual(VideoFitGeometry.clampedZoom(.nan), 1)
        XCTAssertEqual(VideoFitGeometry.effectiveZoom(base: 2, pinch: 3), 5)
        XCTAssertEqual(VideoFitGeometry.effectiveZoom(base: 1, pinch: 0.5), 1)
    }

    func testDoubleTapTogglesBetweenFitAndMagnified() {
        XCTAssertEqual(VideoFitGeometry.toggledZoom(1), VideoFitGeometry.doubleTapZoom)
        XCTAssertEqual(VideoFitGeometry.toggledZoom(3), 1)
        XCTAssertFalse(VideoFitGeometry.isMagnified(1))
        XCTAssertTrue(VideoFitGeometry.isMagnified(1.2))
    }
}
