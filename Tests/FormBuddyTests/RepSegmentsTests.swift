import XCTest
@testable import FormBuddy

final class RepSegmentsTests: XCTestCase {

    private func frame(
        _ knee: Double?,
        torso: Double? = nil,
        phase: String,
        rep: Int
    ) -> AnnotationFrame {
        AnnotationFrame(kneeAngle: knee, torsoAngle: torso, phase: phase, repCount: rep, faults: [])
    }

    private func sidecar(_ frames: [AnnotationFrame]) -> AnnotationSidecar {
        AnnotationSidecar(frames: frames, fps: 10, frameCount: frames.count)
    }

    func testDerivesTwoReps() {
        let frames = [
            frame(170, phase: "standing", rep: 0),
            frame(170, phase: "standing", rep: 0),
            frame(150, phase: "descending", rep: 1),
            frame(100, torso: 30, phase: "descending", rep: 1),
            frame(80, torso: 20, phase: "descending", rep: 1),
            frame(110, torso: 5, phase: "ascending", rep: 1),
            frame(165, phase: "standing", rep: 1),
            frame(170, phase: "standing", rep: 1),
            frame(150, phase: "descending", rep: 2),
            frame(85, phase: "descending", rep: 2),
            frame(120, phase: "ascending", rep: 2),
            frame(168, phase: "standing", rep: 2),
        ]

        let segments = RepSegments.derive(from: sidecar(frames))
        XCTAssertEqual(segments.count, 2)

        let first = segments[0]
        XCTAssertEqual(first.repNumber, 1)
        XCTAssertEqual(first.startFrame, 2)
        XCTAssertEqual(first.endFrame, 6)
        XCTAssertEqual(first.bottomFrame, 4)
        XCTAssertEqual(first.faultFrames["insufficient_depth"], 4)
        XCTAssertEqual(first.faultFrames["excessive_forward_lean"], 3)

        let second = segments[1]
        XCTAssertEqual(second.repNumber, 2)
        XCTAssertEqual(second.startFrame, 8)
        XCTAssertEqual(second.endFrame, 11)
        XCTAssertEqual(second.bottomFrame, 9)
    }

    func testPartialRepRunsToClipEnd() {
        let frames = [
            frame(170, phase: "standing", rep: 0),
            frame(150, phase: "descending", rep: 1),
            frame(100, phase: "descending", rep: 1),
            frame(90, phase: "ascending", rep: 1),
        ]
        let segments = RepSegments.derive(from: sidecar(frames))
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].startFrame, 1)
        XCTAssertEqual(segments[0].endFrame, 3)
        XCTAssertEqual(segments[0].bottomFrame, 3)
    }

    func testMissingAnglesFallBackToEnd() {
        let frames = [
            frame(nil, phase: "descending", rep: 1),
            frame(nil, phase: "descending", rep: 1),
        ]
        let segments = RepSegments.derive(from: sidecar(frames))
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].bottomFrame, 1)
    }

    func testEmptySidecar() {
        XCTAssertTrue(RepSegments.derive(from: sidecar([])).isEmpty)
    }

    func testTimeHelpers() {
        let frames = [
            frame(150, phase: "descending", rep: 1),
            frame(80, phase: "descending", rep: 1),
            frame(165, phase: "standing", rep: 1),
        ]
        let segment = RepSegments.derive(from: sidecar(frames))[0]
        XCTAssertEqual(segment.startTime(fps: 10), 0, accuracy: 1e-9)
        XCTAssertEqual(segment.bottomTime(fps: 10), 0.1, accuracy: 1e-9)
        XCTAssertEqual(segment.endTime(fps: 10), 0.2, accuracy: 1e-9)
        XCTAssertEqual(segment.faultTime("unknown", fps: 10), 0.1, accuracy: 1e-9)
    }
}
