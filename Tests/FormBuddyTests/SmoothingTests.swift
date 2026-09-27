import XCTest
@testable import FormBuddy

final class SmoothingTests: XCTestCase {
    func makeFrame(offset: Double, visibility: Double = 1.0) -> [Double] {
        var lm = [Double](repeating: 0, count: 99)
        for i in 0..<33 {
            lm[i*3] = Double(i) * 0.01 + offset
            lm[i*3+1] = 0.5
            lm[i*3+2] = visibility
        }
        return lm
    }

    func testReturnsNilUntilFirstDetection() {
        let s = LandmarkSmoother()
        XCTAssertNil(s.update(nil))
        XCTAssertNil(s.update(nil))
    }
    func testFirstDetectionPassesThrough() {
        let s = LandmarkSmoother(alpha: 0.5)
        let out = s.update(makeFrame(offset: 0.0))
        XCTAssertEqual(out, makeFrame(offset: 0.0))
    }
    func testMissingDetectionCarriesForward() {
        let s = LandmarkSmoother(alpha: 0.5)
        _ = s.update(makeFrame(offset: 0.0))
        let afterSecond = s.update(makeFrame(offset: 0.1))
        let carried = s.update(nil)
        XCTAssertEqual(carried, afterSecond)
    }
    func testEMABetweenInputs() {
        let s = LandmarkSmoother(alpha: 0.5)
        _ = s.update(makeFrame(offset: 0.0))
        let out = s.update(makeFrame(offset: 0.1))
        XCTAssertGreaterThan(out![0], 0.0)
        XCTAssertLessThan(out![0], 0.1)
        XCTAssertEqual(out![0], 0.05, accuracy: 1e-9)
    }
    func testInvisibleLandmarksCarryForward() {
        let s = LandmarkSmoother(alpha: 0.5)
        _ = s.update(makeFrame(offset: 0.0))
        var moved = makeFrame(offset: 0.1)
        moved[5*3] = 0.9; moved[5*3+1] = 0.9; moved[5*3+2] = 0.2
        let out = s.update(moved)
        XCTAssertEqual(out![5*3], makeFrame(offset: 0.0)[5*3], accuracy: 1e-9)
    }
}
