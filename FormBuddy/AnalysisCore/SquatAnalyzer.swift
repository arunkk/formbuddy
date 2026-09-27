import Foundation

final class SquatAnalyzer: ExerciseAnalyzer {
    // Threshold constants
    static let standingKneeAngle = 160.0
    static let hysteresisAngle = 150.0
    static let riseConfirmAngle = 10.0
    static let depthAbove = 100.0
    static let depthParallel = 90.0
    static let excessiveLeanDegrees = 45.0
    static let minEccentricSeconds = 1.0

    // Shoulder indices
    static let shoulderLeft = 11
    static let shoulderRight = 12

    // Min side visibility
    static let minSideVisibility = 0.5

    private var report = SquatReport()
    private var state = "standing"
    private var repCount = 0
    private var descentStartTime: Double? = nil
    private var bottomKneeAngle: Double? = nil
    private var bottomTime: Double? = nil
    private var bottomTorsoAngle: Double? = nil
    private var ascentStartTime: Double? = nil
    private var lastFrameTimestamp: Double = 0.0

    func process(_ frame: PoseFrame) -> FrameAnnotation {
        lastFrameTimestamp = frame.timestamp
        let (kneeAngle, torsoAngle) = measure(frame)

        if kneeAngle == nil {
            let ann = FrameAnnotation(kneeAngle: nil, torsoAngle: nil, phase: state, repCount: repCount, faults: [])
            report.frames.append(ann)
            return ann
        }

        let ka = kneeAngle!
        let ta = torsoAngle
        var faults: [String] = []
        if let ta = ta, ta > Self.excessiveLeanDegrees {
            faults.append("excessive_forward_lean")
        }

        if state == "standing" {
            if ka < Self.hysteresisAngle {
                state = "descending"
                repCount += 1
                descentStartTime = frame.timestamp
                bottomKneeAngle = ka
                bottomTime = frame.timestamp
                bottomTorsoAngle = ta
                ascentStartTime = nil
            }
        } else if state == "descending" {
            if let bk = bottomKneeAngle, ka < bk {
                bottomKneeAngle = ka
                bottomTime = frame.timestamp
                bottomTorsoAngle = ta
            } else if ascentStartTime == nil, let bk = bottomKneeAngle, ka > bk + Self.riseConfirmAngle {
                ascentStartTime = frame.timestamp
                state = "ascending"
            }
        } else { // ascending
            if ka >= Self.standingKneeAngle {
                if let bk = bottomKneeAngle, let bt = bottomTime, let ds = descentStartTime {
                    let rep = buildRep(repNumber: repCount, endTime: frame.timestamp, partial: false,
                                        descentStart: ds, bottomKneeAngle: bk, bottomTime: bt,
                                        bottomTorso: bottomTorsoAngle, ascentStart: ascentStartTime)
                    report.reps.append(rep)
                }
                state = "standing"
                descentStartTime = nil
                bottomKneeAngle = nil
                bottomTime = nil
                bottomTorsoAngle = nil
                ascentStartTime = nil
            }
        }

        let ann = FrameAnnotation(kneeAngle: ka, torsoAngle: ta, phase: state, repCount: repCount, faults: faults)
        report.frames.append(ann)
        return ann
    }

    func finish() -> SquatReport {
        if state != "standing", let bk = bottomKneeAngle, let bt = bottomTime, let ds = descentStartTime {
            let endTime = lastFrameTimestamp
            let rep = buildRep(repNumber: repCount, endTime: endTime, partial: true,
                                descentStart: ds, bottomKneeAngle: bk, bottomTime: bt,
                                bottomTorso: bottomTorsoAngle, ascentStart: ascentStartTime)
            report.reps.append(rep)
        }
        report.summary = summarize(report.reps, report.frames)
        return report
    }

    func analyze(_ frames: [PoseFrame]) -> SquatReport {
        for frame in frames { _ = process(frame) }
        return finish()
    }

    // MARK: - Measurement

    private func measure(_ frame: PoseFrame) -> (Double?, Double?) {
        guard let landmarks = frame.landmarks else { return (nil, nil) }
        let leftIds = [23, 25, 27]
        let rightIds = [24, 26, 28]
        let leftVis = leftIds.map { landmarks[$0*3+2] }.reduce(0,+) / 3.0
        let rightVis = rightIds.map { landmarks[$0*3+2] }.reduce(0,+) / 3.0
        if leftVis < Self.minSideVisibility && rightVis < Self.minSideVisibility {
            return (nil, nil)
        }
        let side = selectSide(landmarks)
        let ids = sideLandmarks[side.rawValue]!
        let hip = [landmarks[ids["hip"]!*3], landmarks[ids["hip"]!*3+1]]
        let knee = [landmarks[ids["knee"]!*3], landmarks[ids["knee"]!*3+1]]
        let ankle = [landmarks[ids["ankle"]!*3], landmarks[ids["ankle"]!*3+1]]
        let shoulderIdx = side == .left ? Self.shoulderLeft : Self.shoulderRight
        let shoulder = [landmarks[shoulderIdx*3], landmarks[shoulderIdx*3+1]]
        return (jointAngle(hip, knee, ankle), segmentAngleVsVertical(shoulder, hip))
    }

    // MARK: - Rep building

    private func buildRep(repNumber: Int, endTime: Double, partial: Bool,
                          descentStart: Double, bottomKneeAngle: Double, bottomTime: Double,
                          bottomTorso: Double?, ascentStart: Double?) -> RepResult {
        let eccentric = bottomTime - descentStart
        let bottomPause: Double
        let concentric: Double
        if let ascent = ascentStart {
            bottomPause = ascent - bottomTime
            concentric = endTime - ascent
        } else {
            bottomPause = 0.0
            concentric = 0.0
        }

        var faults: [String] = []
        if classifyDepth(bottomKneeAngle) == "above_parallel" {
            faults.append("insufficient_depth")
        }
        if let bt = bottomTorso, bt > Self.excessiveLeanDegrees {
            faults.append("excessive_forward_lean")
        }
        if eccentric < Self.minEccentricSeconds {
            faults.append("uncontrolled_descent")
        }

        return RepResult(
            repNumber: repNumber,
            depth: classifyDepth(bottomKneeAngle),
            bottomKneeAngle: bottomKneeAngle,
            torsoAngleAtBottom: bottomTorso ?? 0.0,
            eccentricSeconds: eccentric,
            concentricSeconds: concentric,
            bottomPauseSeconds: bottomPause,
            faults: faults,
            partial: partial
        )
    }

    private func classifyDepth(_ angle: Double) -> String {
        if angle < Self.depthParallel { return "below_parallel" }
        if angle > Self.depthAbove { return "above_parallel" }
        return "parallel"
    }

    private func summarize(_ reps: [RepResult], _ frames: [FrameAnnotation]) -> SquatSummary {
        var maxTorso: Double = 0
        let measured = frames.compactMap { $0.torsoAngle }
        if !measured.isEmpty { maxTorso = measured.max()! }

        let n = reps.count
        if n == 0 {
            return SquatSummary(maxTorsoAngle: maxTorso)
        }
        return SquatSummary(
            totalReps: n,
            partialReps: reps.filter { $0.partial }.count,
            repsBelowParallel: reps.filter { $0.depth == "below_parallel" }.count,
            repsAtParallel: reps.filter { $0.depth == "parallel" }.count,
            repsAboveParallel: reps.filter { $0.depth == "above_parallel" }.count,
            avgEccentricSeconds: reps.map { $0.eccentricSeconds }.reduce(0,+) / Double(n),
            avgConcentricSeconds: reps.map { $0.concentricSeconds }.reduce(0,+) / Double(n),
            avgBottomPauseSeconds: reps.map { $0.bottomPauseSeconds }.reduce(0,+) / Double(n),
            avgTorsoAngleAtBottom: reps.map { $0.torsoAngleAtBottom }.reduce(0,+) / Double(n),
            maxTorsoAngle: maxTorso
        )
    }
}
