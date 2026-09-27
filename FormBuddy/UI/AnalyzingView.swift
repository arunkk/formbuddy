import SwiftUI

struct AnalyzingView: View {
    let videoURL: URL
    @State private var pipeline = AnalysisPipeline()
    @State private var report: SquatReport?
    @State private var error: Error?
    @State private var showDetail = false

    var body: some View {
        VStack(spacing: 20) {
            if let report = report {
                Text("Analysis complete!")
                    .font(.title)
                Text("\(report.summary.totalReps) reps detected")
                    .font(.headline)
                Button("View Results") {
                    showDetail = true
                }
                .buttonStyle(.borderedProminent)
            } else if let error = error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
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
}
