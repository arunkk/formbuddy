import XCTest
@testable import FormBuddy

final class FaultVisualsTests: XCTestCase {

    func testKnownFaultsHaveVisuals() {
        XCTAssertEqual(FaultVisuals.visual(for: "insufficient_depth")?.highlight, .kneeArc)
        XCTAssertEqual(FaultVisuals.visual(for: "insufficient_depth")?.joint, .knee)
        XCTAssertEqual(FaultVisuals.visual(for: "excessive_forward_lean")?.highlight, .torsoWedge)
        XCTAssertEqual(FaultVisuals.visual(for: "excessive_forward_lean")?.joint, .shoulder)
        XCTAssertEqual(FaultVisuals.visual(for: "uncontrolled_descent")?.highlight, .tempo)
    }

    func testUnknownFaultHasNoVisual() {
        XCTAssertNil(FaultVisuals.visual(for: "not_a_fault"))
    }

    func testLandmarkIndices() {
        XCTAssertEqual(FaultVisuals.landmarkIndex(for: .knee, side: .left), 25)
        XCTAssertEqual(FaultVisuals.landmarkIndex(for: .knee, side: .right), 26)
        XCTAssertEqual(FaultVisuals.landmarkIndex(for: .hip, side: .left), 23)
        XCTAssertEqual(FaultVisuals.landmarkIndex(for: .ankle, side: .right), 28)
        XCTAssertEqual(FaultVisuals.landmarkIndex(for: .shoulder, side: .left), 11)
        XCTAssertEqual(FaultVisuals.landmarkIndex(for: .shoulder, side: .right), 12)
    }

    func testRepFeedbackJoinsSegments() {
        let result = RepResult(
            repNumber: 1,
            depth: "above_parallel",
            bottomKneeAngle: 112,
            torsoAngleAtBottom: 10,
            eccentricSeconds: 0.4,
            concentricSeconds: 1.2,
            bottomPauseSeconds: 0,
            faults: ["insufficient_depth"],
            partial: false
        )
        let segment = RepSegment(
            repNumber: 1, startFrame: 0, endFrame: 5, bottomFrame: 3, faultFrames: [:]
        )
        let feedback = RepFeedback.build(reps: [result], segments: [segment])
        XCTAssertEqual(feedback.count, 1)
        XCTAssertEqual(feedback[0].segment, segment)
        XCTAssertEqual(feedback[0].visuals.map(\.fault), ["insufficient_depth"])
    }

    func testRepFeedbackWithoutSegment() {
        let result = RepResult(
            repNumber: 2, depth: "below_parallel", bottomKneeAngle: 80,
            torsoAngleAtBottom: 5, eccentricSeconds: 1.5, concentricSeconds: 1.5,
            bottomPauseSeconds: 0, faults: [], partial: false
        )
        let feedback = RepFeedback.build(reps: [result], segments: [])
        XCTAssertEqual(feedback.count, 1)
        XCTAssertNil(feedback[0].segment)
        XCTAssertTrue(feedback[0].visuals.isEmpty)
    }
}
