import SwiftUI
import SwiftData

struct AnalyzingView: View {
    let videoURL: URL
    @State private var pipeline = AnalysisPipeline()
    @State private var report: SquatReport?
    @State private var error: Error?
    @State private var showDetail = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 20) {
            if let report = report {
                Text("Analysis complete!")
                    .font(.title)
                Text("\(report.summary.totalReps) reps detected")
                    .font(.headline)
                Button("View Results") {
                    saveSession(report)
                    showDetail = true
                }
                .buttonStyle(.borderedProminent)
            } else if let error = error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .padding()
            } else {
                ProgressView(value: pipeline.progress)
                    .frame(width: 200)
                Text("Analyzing... \(Int(pipeline.progress * 100))%")
                Text("This may take longer than the clip itself (iOS is CPU-only)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .navigationTitle("Analyzing")
        .task {
            do {
                report = try await pipeline.analyze(videoAt: videoURL)
            } catch {
                self.error = error
            }
        }
        .navigationDestination(isPresented: $showDetail) {
            if let report = report {
                SessionDetailView(report: report, videoURL: videoURL)
            }
        }
    }

    private func saveSession(_ report: SquatReport) {
        let session = Session(
            exercise: report.exercise,
            videoFilename: videoURL.lastPathComponent,
            fps: report.videoMeta["fps"] as? Double ?? 30.0,
            frameCount: report.videoMeta["frame_count"] as? Int ?? 0,
            duration: report.videoMeta["duration"] as? Double ?? 0.0,
            warnings: report.warnings
        )
        session.summary = Summary(
            totalReps: report.summary.totalReps,
            partialReps: report.summary.partialReps,
            repsBelowParallel: report.summary.repsBelowParallel,
            repsAtParallel: report.summary.repsAtParallel,
            repsAboveParallel: report.summary.repsAboveParallel,
            avgEccentricSeconds: report.summary.avgEccentricSeconds,
            avgConcentricSeconds: report.summary.avgConcentricSeconds,
            avgBottomPauseSeconds: report.summary.avgBottomPauseSeconds,
            avgTorsoAngleAtBottom: report.summary.avgTorsoAngleAtBottom,
            maxTorsoAngle: report.summary.maxTorsoAngle
        )
        for rep in report.reps {
            let record = RepRecord(
                repNumber: rep.repNumber,
                depth: rep.depth,
                bottomKneeAngle: rep.bottomKneeAngle,
                torsoAngleAtBottom: rep.torsoAngleAtBottom,
                eccentricSeconds: rep.eccentricSeconds,
                concentricSeconds: rep.concentricSeconds,
                bottomPauseSeconds: rep.bottomPauseSeconds,
                faults: rep.faults,
                partial: rep.partial
            )
            record.session = session
            session.reps.append(record)
        }
        modelContext.insert(session)
        try? modelContext.save()
    }
}
