import XCTest
@testable import FormBuddy

final class FixtureParityTests: XCTestCase {

    struct Fixture: Codable {
        let name: String
        let frames: [FixtureFrame]
        let expected: Expected
    }

    struct FixtureFrame: Codable {
        let timestamp: Double
        let landmarks: [Double]?
    }

    struct Expected: Codable {
        let summary: SummaryExpected
        let reps: [RepExpected]
        let frameAnnotations: [FrameAnnotationExpected]
        enum CodingKeys: String, CodingKey {
            case summary, reps
            case frameAnnotations = "frame_annotations"
        }
    }

    struct SummaryExpected: Codable {
        let total_reps: Int
        let partial_reps: Int
        let reps_below_parallel: Int
        let reps_at_parallel: Int
        let reps_above_parallel: Int
        let avg_eccentric_seconds: Double
        let avg_concentric_seconds: Double
        let avg_bottom_pause_seconds: Double
        let avg_torso_angle_at_bottom: Double
        let max_torso_angle: Double
    }

    struct RepExpected: Codable {
        let rep_number: Int
        let depth: String
        let bottom_knee_angle: Double
        let torso_angle_at_bottom: Double
        let eccentric_seconds: Double
        let concentric_seconds: Double
        let bottom_pause_seconds: Double
        let faults: [String]
        let partial: Bool
    }

    struct FrameAnnotationExpected: Codable {
        let knee_angle: Double?
        let torso_angle: Double?
        let phase: String
        let rep_count: Int
        let faults: [String]
    }

    func loadFixture(_ name: String) -> Fixture? {
        guard let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(Fixture.self, from: data)
    }

    func testTwoCleanReps() {
        guard let f = loadFixture("two_clean_reps") else { XCTFail("Fixture not found"); return }
        let report = SquatAnalyzer().analyze(f.frames.map { PoseFrame(landmarks: $0.landmarks, timestamp: $0.timestamp) })
        XCTAssertEqual(report.summary.totalReps, f.expected.summary.total_reps)
        XCTAssertEqual(report.summary.partialReps, f.expected.summary.partial_reps)
        XCTAssertEqual(report.summary.repsBelowParallel, f.expected.summary.reps_below_parallel)
        XCTAssertEqual(report.summary.repsAtParallel, f.expected.summary.reps_at_parallel)
        XCTAssertEqual(report.summary.repsAboveParallel, f.expected.summary.reps_above_parallel)
        XCTAssertEqual(report.summary.avgEccentricSeconds, f.expected.summary.avg_eccentric_seconds, accuracy: 1e-4)
        XCTAssertEqual(report.summary.avgConcentricSeconds, f.expected.summary.avg_concentric_seconds, accuracy: 1e-4)
        XCTAssertEqual(report.summary.avgBottomPauseSeconds, f.expected.summary.avg_bottom_pause_seconds, accuracy: 1e-4)
        XCTAssertEqual(report.reps.count, f.expected.reps.count)
        for (actual, expected) in zip(report.reps, f.expected.reps) {
            XCTAssertEqual(actual.repNumber, expected.rep_number)
            XCTAssertEqual(actual.depth, expected.depth)
            XCTAssertEqual(actual.partial, expected.partial)
            XCTAssertEqual(actual.faults, expected.faults)
        }
        XCTAssertEqual(report.frames.count, f.expected.frameAnnotations.count)
        for (actual, expected) in zip(report.frames, f.expected.frameAnnotations) {
            XCTAssertEqual(actual.phase, expected.phase)
            XCTAssertEqual(actual.repCount, expected.rep_count)
        }
    }

    func testParallel95() {
        guard let f = loadFixture("parallel_95") else { XCTFail("Fixture not found"); return }
        let report = SquatAnalyzer().analyze(f.frames.map { PoseFrame(landmarks: $0.landmarks, timestamp: $0.timestamp) })
        XCTAssertEqual(report.reps.count, f.expected.reps.count)
        XCTAssertEqual(report.reps[0].depth, f.expected.reps[0].depth)
    }

    func testAboveParallel110() {
        guard let f = loadFixture("above_parallel_110") else { XCTFail("Fixture not found"); return }
        let report = SquatAnalyzer().analyze(f.frames.map { PoseFrame(landmarks: $0.landmarks, timestamp: $0.timestamp) })
        XCTAssertEqual(report.reps.count, f.expected.reps.count)
        XCTAssertEqual(report.reps[0].depth, f.expected.reps[0].depth)
        XCTAssertEqual(report.reps[0].faults, f.expected.reps[0].faults)
    }

    func testExcessiveLean() {
        guard let f = loadFixture("excessive_lean") else { XCTFail("Fixture not found"); return }
        let report = SquatAnalyzer().analyze(f.frames.map { PoseFrame(landmarks: $0.landmarks, timestamp: $0.timestamp) })
        XCTAssertEqual(report.reps.count, f.expected.reps.count)
        XCTAssertEqual(report.reps[0].faults, f.expected.reps[0].faults)
    }

    func testUncontrolledDescent() {
        guard let f = loadFixture("uncontrolled_descent") else { XCTFail("Fixture not found"); return }
        let report = SquatAnalyzer().analyze(f.frames.map { PoseFrame(landmarks: $0.landmarks, timestamp: $0.timestamp) })
        XCTAssertEqual(report.reps.count, f.expected.reps.count)
        XCTAssertEqual(report.reps[0].faults, f.expected.reps[0].faults)
    }

    func testPartialRep() {
        guard let f = loadFixture("partial_rep") else { XCTFail("Fixture not found"); return }
        let report = SquatAnalyzer().analyze(f.frames.map { PoseFrame(landmarks: $0.landmarks, timestamp: $0.timestamp) })
        XCTAssertEqual(report.reps.count, f.expected.reps.count)
        XCTAssertEqual(report.reps.last!.partial, f.expected.reps.last!.partial)
    }

    func testZeroVisibility() {
        guard let f = loadFixture("zero_visibility") else { XCTFail("Fixture not found"); return }
        let report = SquatAnalyzer().analyze(f.frames.map { PoseFrame(landmarks: $0.landmarks, timestamp: $0.timestamp) })
        XCTAssertEqual(report.summary.totalReps, 0)
    }

    func testTorsoSummary() {
        guard let f = loadFixture("torso_summary") else { XCTFail("Fixture not found"); return }
        let report = SquatAnalyzer().analyze(f.frames.map { PoseFrame(landmarks: $0.landmarks, timestamp: $0.timestamp) })
        XCTAssertEqual(report.summary.totalReps, f.expected.summary.total_reps)
        // Fixture landmarks are float32; tolerance relaxed from 1e-9 to 1e-4
        XCTAssertEqual(report.summary.avgTorsoAngleAtBottom, f.expected.summary.avg_torso_angle_at_bottom, accuracy: 1e-4)
        XCTAssertEqual(report.summary.maxTorsoAngle, f.expected.summary.max_torso_angle, accuracy: 1e-4)
    }
}
