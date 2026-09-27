import XCTest
@testable import FormBuddy

final class SquatAnalyzerTests: XCTestCase {
    // Helper: build synthetic PoseFrame from knee/torso angles
    func makeFrames(kneeAngles: [Double], torsoAngles: [Double]? = nil, dt: Double = 0.1, zeroVisibility: Bool = false) -> [PoseFrame] {
        let torso = torsoAngles ?? [Double](repeating: 0, count: kneeAngles.count)
        var frames: [PoseFrame] = []
        for (i, (ka, ta)) in zip(kneeAngles, torso).enumerated() {
            var lm = [Double](repeating: 0, count: 99)
            let kaRad = ka * .pi / 180.0
            // Knee at origin, hip above, ankle positioned for desired angle
            let knee = [0.5, 0.5]
            let hip = [0.5, 0.4]
            let ankle = [knee[0] + sin(kaRad), knee[1] - cos(kaRad)]
            // Shoulder for torso angle
            let taRad = ta * .pi / 180.0
            let shoulder = [hip[0] - sin(taRad), hip[1] - cos(taRad)]
            // Left side indices
            lm[23*3] = hip[0]; lm[23*3+1] = hip[1]
            lm[25*3] = knee[0]; lm[25*3+1] = knee[1]
            lm[27*3] = ankle[0]; lm[27*3+1] = ankle[1]
            lm[11*3] = shoulder[0]; lm[11*3+1] = shoulder[1]
            if zeroVisibility {
                for j in 0..<33 { lm[j*3+2] = 0.0 }
            } else {
                lm[23*3+2] = 1.0; lm[25*3+2] = 1.0; lm[27*3+2] = 1.0; lm[11*3+2] = 1.0
            }
            frames.append(PoseFrame(landmarks: lm, timestamp: Double(i) * dt))
        }
        return frames
    }

    func twoCleanRepsAngles() -> [Double] {
        let down = stride(from: 170.0, through: 80.0, by: -4.7368).map { $0 }
        let up = stride(from: 80.0, through: 170.0, by: 4.7368).map { $0 }
        return [170.0,170.0,170.0,170.0,170.0] + down + up + [170.0,170.0,170.0,170.0,170.0] + down + up + [170.0,170.0,170.0,170.0,170.0]
    }

    func testTwoCleanRepsCount() {
        let report = SquatAnalyzer().analyze(makeFrames(kneeAngles: twoCleanRepsAngles()))
        XCTAssertEqual(report.summary.totalReps, 2)
    }
    func testTwoCleanRepsBelowParallel() {
        let report = SquatAnalyzer().analyze(makeFrames(kneeAngles: twoCleanRepsAngles()))
        for rep in report.reps { XCTAssertEqual(rep.depth, "below_parallel") }
    }
    func testTwoCleanRepsNoFaults() {
        let report = SquatAnalyzer().analyze(makeFrames(kneeAngles: twoCleanRepsAngles()))
        for rep in report.reps { XCTAssertEqual(rep.faults, []) }
    }
    func testParallelAt95() {
        let down = stride(from: 170.0, through: 95.0, by: -3.9474).map { $0 }
        let up = stride(from: 95.0, through: 170.0, by: 3.9474).map { $0 }
        let angles = [170.0,170.0,170.0,170.0,170.0] + down + up + [170.0,170.0,170.0,170.0,170.0]
        let report = SquatAnalyzer().analyze(makeFrames(kneeAngles: angles))
        XCTAssertEqual(report.reps.count, 1)
        XCTAssertEqual(report.reps[0].depth, "parallel")
    }
    func testAboveParallelAt110() {
        let down = stride(from: 170.0, through: 110.0, by: -3.1579).map { $0 }
        let up = stride(from: 110.0, through: 170.0, by: 3.1579).map { $0 }
        let angles = [170.0,170.0,170.0,170.0,170.0] + down + up + [170.0,170.0,170.0,170.0,170.0]
        let report = SquatAnalyzer().analyze(makeFrames(kneeAngles: angles))
        XCTAssertEqual(report.reps.count, 1)
        XCTAssertEqual(report.reps[0].depth, "above_parallel")
        XCTAssertTrue(report.reps[0].faults.contains("insufficient_depth"))
    }
    func testExcessiveLean() {
        let down = stride(from: 170.0, through: 80.0, by: -4.7368).map { $0 }
        let up = stride(from: 80.0, through: 170.0, by: 4.7368).map { $0 }
        let angles = [170.0,170.0,170.0,170.0,170.0] + down + up + [170.0,170.0,170.0,170.0,170.0]
        let tDown: [Double] = [0.0] + stride(from: 0.0, through: 50.0, by: 2.6316).map { $0 }
        let tUp: [Double] = stride(from: 50.0, through: 0.0, by: -2.6316).map { $0 }
        let torso = [0.0,0.0,0.0,0.0,0.0] + tDown + tUp + [0.0,0.0,0.0,0.0,0.0]
        let report = SquatAnalyzer().analyze(makeFrames(kneeAngles: angles, torsoAngles: torso))
        XCTAssertEqual(report.reps.count, 1)
        XCTAssertTrue(report.reps[0].faults.contains("excessive_forward_lean"))
    }
    func testUncontrolledDescent() {
        let down = stride(from: 170.0, through: 80.0, by: -22.5).map { $0 }
        let up = stride(from: 80.0, through: 170.0, by: 4.7368).map { $0 }
        let angles = [170.0,170.0,170.0,170.0,170.0] + down + up + [170.0,170.0,170.0,170.0,170.0]
        let report = SquatAnalyzer().analyze(makeFrames(kneeAngles: angles))
        XCTAssertEqual(report.reps.count, 1)
        XCTAssertTrue(report.reps[0].faults.contains("uncontrolled_descent"))
    }
    func testPartialRep() {
        let down = stride(from: 170.0, through: 80.0, by: -4.7368).map { $0 }
        let upPartial = stride(from: 80.0, through: 120.0, by: 4.4444).map { $0 }
        let angles = [170.0,170.0,170.0,170.0,170.0] + down + upPartial
        let report = SquatAnalyzer().analyze(makeFrames(kneeAngles: angles))
        XCTAssertGreaterThanOrEqual(report.reps.count, 1)
        XCTAssertTrue(report.reps.last!.partial)
    }
    func testZeroVisibility() {
        let report = SquatAnalyzer().analyze(makeFrames(kneeAngles: [170.0,170.0,170.0,170.0,170.0], zeroVisibility: true))
        XCTAssertEqual(report.summary.totalReps, 0)
    }
    func testFrameAnnotationsCount() {
        let angles = [170.0,170.0,170.0,170.0,170.0] + stride(from: 170.0, through: 80.0, by: -4.7368).map { $0 } + stride(from: 80.0, through: 170.0, by: 4.7368).map { $0 } + [170.0,170.0,170.0,170.0,170.0]
        let frames = makeFrames(kneeAngles: angles)
        let report = SquatAnalyzer().analyze(frames)
        XCTAssertEqual(report.frames.count, frames.count)
    }
    func testPhaseValues() {
        let angles = [170.0,170.0,170.0,170.0,170.0] + stride(from: 170.0, through: 80.0, by: -4.7368).map { $0 } + stride(from: 80.0, through: 170.0, by: 4.7368).map { $0 } + [170.0,170.0,170.0,170.0,170.0]
        let report = SquatAnalyzer().analyze(makeFrames(kneeAngles: angles))
        let validPhases: Set<String> = ["standing", "descending", "ascending"]
        for ann in report.frames { XCTAssertTrue(validPhases.contains(ann.phase)) }
    }
}
