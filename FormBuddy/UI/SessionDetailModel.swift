import Foundation

/// A read model that normalizes a freshly analyzed `SquatReport` and a
/// persisted `Session` into one shape for `SessionDetailView`.
struct SessionDetailModel {
    let exercise: String
    let createdAt: Date?
    let summary: SquatSummary
    let reps: [RepResult]
    let warnings: [String]
    let sidecar: AnnotationSidecar?
    let videoURL: URL?
    let reportFileURL: URL?

    var frames: [FrameAnnotation] { sidecar?.frameAnnotations ?? [] }
    var fps: Double { sidecar?.fps ?? 30 }

    /// Warnings that describe filming problems are surfaced separately from
    /// per-rep faults so the detail screen can lead with them.
    var filmingWarnings: [String] { warnings }

    init(report: SquatReport, videoURL: URL?, sidecar: AnnotationSidecar?, reportFileURL: URL?) {
        self.exercise = report.exercise
        self.createdAt = nil
        self.summary = report.summary
        self.reps = report.reps
        self.warnings = report.warnings
        self.sidecar = sidecar
        self.videoURL = videoURL
        self.reportFileURL = reportFileURL
    }

    init(session: Session) {
        self.exercise = session.exercise
        self.createdAt = session.createdAt
        self.summary = SquatSummary(session.summary)
        self.reps = session.reps.sorted { $0.repNumber < $1.repNumber }.map(RepResult.init)
        self.warnings = session.warnings
        self.sidecar = SessionStore.loadAnnotations(for: session.id)

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
