import XCTest
@testable import FormBuddy

final class GeometryTests: XCTestCase {
    func testRightAngleAtOrigin() {
        XCTAssertEqual(jointAngle([0,0],[1,0],[1,1]), 90.0, accuracy: 1e-9)
    }
    func testStraightLine() {
        XCTAssertEqual(jointAngle([0,0],[1,0],[2,0]), 180.0, accuracy: 1e-9)
    }
    func testObtuseAngle() {
        XCTAssertEqual(jointAngle([0,0],[1,0],[0,1]), 45.0, accuracy: 1e-9)
    }
    func testUprightSegment() {
        XCTAssertEqual(segmentAngleVsVertical([1,0],[1,1]), 0.0, accuracy: 1e-9)
    }
    func test45DegreeSegment() {
        XCTAssertEqual(segmentAngleVsVertical([1,0],[2,1]), 45.0, accuracy: 1e-9)
    }
    func testSelectLeft() {
        var lm = [Double](repeating: 0, count: 99)
        for i in [23,25,27] { lm[i*3+2] = 1.0 }
        for i in [24,26,28] { lm[i*3+2] = 0.0 }
        XCTAssertEqual(selectSide(lm), .left)
    }
    func testSelectRight() {
        var lm = [Double](repeating: 0, count: 99)
        for i in [23,25,27] { lm[i*3+2] = 0.0 }
        for i in [24,26,28] { lm[i*3+2] = 1.0 }
        XCTAssertEqual(selectSide(lm), .right)
    }
    func testSelectTieBreaksLeft() {
        var lm = [Double](repeating: 0, count: 99)
        for i in [23,25,27,24,26,28] { lm[i*3+2] = 0.5 }
        XCTAssertEqual(selectSide(lm), .left)
    }
}
