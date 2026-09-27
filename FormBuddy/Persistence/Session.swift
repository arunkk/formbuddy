import Foundation
import SwiftData

@Model
final class Session {
    var id: UUID
    var exercise: String
    var createdAt: Date
    var videoFilename: String
    var orientationTransform: Data
    var fps: Double
    var frameCount: Int
    var duration: Double
    var warnings: [String]
    var summary: Summary
    var annotationFilename: String
    @Relationship(deleteRule: .cascade, inverse: \RepRecord.session)
    var reps: [RepRecord]

    init(id: UUID = UUID(), exercise: String = "squat", createdAt: Date = Date(),
         videoFilename: String = "", orientationTransform: Data = Data(),
         fps: Double = 30.0, frameCount: Int = 0, duration: Double = 0.0,
         warnings: [String] = [], summary: Summary = Summary(),
         annotationFilename: String = "", reps: [RepRecord] = []) {
        self.id = id
        self.exercise = exercise
        self.createdAt = createdAt
        self.videoFilename = videoFilename
        self.orientationTransform = orientationTransform
        self.fps = fps
        self.frameCount = frameCount
        self.duration = duration
        self.warnings = warnings
        self.summary = summary
        self.annotationFilename = annotationFilename
        self.reps = reps
    }
}

struct Summary: Codable {
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
