import Foundation

/// A read model for `SessionDetailView`, built from a persisted `Session`.
///
/// It deliberately stays cheap: the per-frame annotation sidecar can be large,
/// so it is loaded asynchronously by the view rather than decoded here on the
/// main thread.
struct SessionDetailModel {
    let exercise: String
    let createdAt: Date?
    let summary: SquatSummary
    let reps: [RepResult]
    let warnings: [String]
    let sessionID: UUID
    let videoURL: URL?
    let reportFileURL: URL?

    init(session: Session) {
        self.exercise = session.exercise
        self.createdAt = session.createdAt
        self.summary = SquatSummary(session.summary)
        self.reps = session.reps.sorted { $0.repNumber < $1.repNumber }.map(RepResult.init)
        self.warnings = session.warnings
        self.sessionID = session.id

        let video = SessionStore.videoURL(for: session.id, filename: session.videoFilename)
        self.videoURL = session.videoFilename.isEmpty || !FileManager.default.fileExists(atPath: video.path)
            ? nil
            : video
        self.reportFileURL = SessionStore.reportURLIfExists(for: session.id)
    }
}

extension SquatSummary {
    init(_ summary: Summary) {
        self.init(
            totalReps: summary.totalReps,
            partialReps: summary.partialReps,
            repsBelowParallel: summary.repsBelowParallel,
            repsAtParallel: summary.repsAtParallel,
            repsAboveParallel: summary.repsAboveParallel,
            avgEccentricSeconds: summary.avgEccentricSeconds,
            avgConcentricSeconds: summary.avgConcentricSeconds,
            avgBottomPauseSeconds: summary.avgBottomPauseSeconds,
            avgTorsoAngleAtBottom: summary.avgTorsoAngleAtBottom,
            maxTorsoAngle: summary.maxTorsoAngle
        )
    }
}

extension RepResult {
    init(_ record: RepRecord) {
        self.init(
            repNumber: record.repNumber,
            depth: record.depth,
            bottomKneeAngle: record.bottomKneeAngle,
            torsoAngleAtBottom: record.torsoAngleAtBottom,
            eccentricSeconds: record.eccentricSeconds,
            concentricSeconds: record.concentricSeconds,
            bottomPauseSeconds: record.bottomPauseSeconds,
            faults: record.faults,
            partial: record.partial
        )
    }
}
