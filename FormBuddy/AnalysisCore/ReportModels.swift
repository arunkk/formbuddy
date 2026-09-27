import Foundation

struct FrameAnnotation {
    var kneeAngle: Double?
    var torsoAngle: Double?
    var phase: String
    var repCount: Int
    var faults: [String] = []
}

struct RepResult {
    var repNumber: Int
    var depth: String
    var bottomKneeAngle: Double
    var torsoAngleAtBottom: Double
    var eccentricSeconds: Double
    var concentricSeconds: Double
    var bottomPauseSeconds: Double
    var faults: [String] = []
    var partial: Bool = false
}

struct SquatSummary {
    var totalReps: Int = 0
    var partialReps: Int = 0
    var repsBelowParallel: Int = 0
    var repsAtParallel: Int = 0
    var repsAboveParallel: Int = 0
    var avgEccentricSeconds: Double = 0
    var avgConcentricSeconds: Double = 0
    var avgBottomPauseSeconds: Double = 0
    var avgTorsoAngleAtBottom: Double = 0
    var maxTorsoAngle: Double = 0
}

struct SquatReport {
    var exercise: String = "squat"
    var warnings: [String] = []
    var videoMeta: [String: Any] = [:]
    var reps: [RepResult] = []
    var summary: SquatSummary = SquatSummary()
    var frames: [FrameAnnotation] = []
}
