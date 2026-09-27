import SwiftUI
import SwiftData
import UIKit

struct AnalyzingView: View {
    let videoURL: URL
    var onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var pipeline = AnalysisPipeline()
    @State private var phase: Phase = .running
    @State private var analysisTask: Task<Void, Never>?
    @State private var showDetail = false

    enum Phase: Equatable {
        case running
        case finished(Session)
        case failed(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.running, .running): return true
            case (.finished(let a), .finished(let b)): return a.id == b.id
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var body: some View {
        content
            .navigationTitle("Analyzing")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(phase == .running)
            .toolbar {
                if phase == .running {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") { cancel() }
                    }
                }
            }
            .navigationDestination(isPresented: $showDetail) {
                if case .finished(let session) = phase {
                    SessionDetailView(session: session)
                }
            }
            .onAppear { startIfNeeded() }
            .onDisappear(perform: teardown)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .running:
            runningState
        case .finished(let session):
            finishedState(session)
        case .failed(let message):
            failedState(message)
        }
    }

    // MARK: - States

    private var runningState: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressRing(progress: pipeline.progress)
            VStack(spacing: 8) {
                Text("Analyzing your set")
                    .font(.title3.weight(.semibold))
                Text("Estimating pose, smoothing landmarks, and scoring each rep on device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("iOS runs this on the CPU, so it can take longer than the clip itself.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .padding()
    }

    private func finishedState(_ session: Session) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: session.summary.totalReps > 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(session.summary.totalReps > 0 ? .green : .orange)
                .symbolEffect(.bounce, value: session.subtitle)
            Text("Analysis complete")
                .font(.title2.weight(.bold))
            Text("\(session.summary.totalReps) \(session.summary.totalReps == 1 ? "rep" : "reps") detected")
                .font(.headline)
            if session.summary.totalReps == 0 {
                Text("No complete reps were detected. Re-film from the side with your whole body in frame.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            VStack(spacing: 12) {
                Button {
                    showDetail = true
                } label: {
                    Label("View results", systemImage: "chart.bar.doc.horizontal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Done") { onFinish() }
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
    }

    private func failedState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Analysis failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { startIfNeeded(force: true) }
                .buttonStyle(.borderedProminent)
            Button("Close") { onFinish() }
        }
    }

    // MARK: - Lifecycle

    private func startIfNeeded(force: Bool = false) {
        guard force || analysisTask == nil else { return }
        analysisTask?.cancel()
        phase = .running
        UIApplication.shared.isIdleTimerDisabled = true
        analysisTask = Task { @MainActor in
            do {
                let result = try await pipeline.analyze(videoAt: videoURL)
                try Task.checkCancellation()
                let session = save(result)
                phase = .finished(session)
            } catch is CancellationError {
                // Caller is dismissing; leave state alone.
            } catch {
                phase = .failed(error.localizedDescription)
            }
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func cancel() {
        analysisTask?.cancel()
        analysisTask = nil
        onFinish()
    }

    private func teardown() {
        analysisTask?.cancel()
        analysisTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Persistence

    private func save(_ result: AnalysisResult) -> Session {
        let report = result.report
        let fps = (report.videoMeta["fps"] as? Double) ?? 30
        let duration = (report.videoMeta["duration"] as? Double) ?? 0

        let session = Session(
            exercise: report.exercise,
            videoFilename: "",
            fps: fps,
            frameCount: result.sidecar.frameCount,
            duration: duration,
            warnings: report.warnings
        )
        session.orientationTransform = result.preferredTransform.storedData

        if let filename = try? SessionStore.adoptVideo(from: videoURL, for: session.id) {
            session.videoFilename = filename
        }
        try? SessionStore.saveAnnotations(result.sidecar, for: session.id)
        try? SessionStore.writeReportJSON(report, for: session.id)

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
        return session
    }
}

/// Determinate circular progress ring.
private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(min(progress, 1), 0.001))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progress)
            Text("\(Int((min(max(progress, 0), 1)) * 100))%")
                .font(.title2.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .frame(width: 148, height: 148)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analysis progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

private extension Session {
    var subtitle: Int { summary.totalReps }
}
