import XCTest
@testable import FormBuddy

final class AnalysisProgressTests: XCTestCase {
    func testProgressReflectsProcessedFramesAgainstEstimate() {
        XCTAssertEqual(AnalysisProgress.fraction(processedFrames: 2, estimatedFrames: 10), 0.2, accuracy: 1e-12)
    }

    func testProgressIsZeroWhenEstimateIsUnavailable() {
        XCTAssertEqual(AnalysisProgress.fraction(processedFrames: 4, estimatedFrames: 0), 0)
    }

    func testProgressIsClampedToOne() {
        XCTAssertEqual(AnalysisProgress.fraction(processedFrames: 12, estimatedFrames: 10), 1)
    }
}
