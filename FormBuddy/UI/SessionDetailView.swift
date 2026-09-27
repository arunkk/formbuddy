import SwiftUI
import SwiftData

/// Full report for a session: annotated playback, summary metrics, per-rep
/// breakdown, knee-angle chart, warnings, and sharing.
struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let model: SessionDetailModel
    private let session: Session?
    @State private var showDeleteConfirm = false
    @State private var sidecar: AnnotationSidecar?

    init(session: Session) {
        self.model = SessionDetailModel(session: session)
        self.session = session
    }

    private var frames: [FrameAnnotation] { sidecar?.frameAnnotations ?? [] }
    private var fps: Double { sidecar?.fps ?? 30 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !model.warnings.isEmpty {
                    warningsBanner
                }

                if let videoURL = model.videoURL, let sidecar, !sidecar.frames.isEmpty {
                    SectionHeader(title: "Annotated playback", subtitle: "Skeleton and metrics drawn over your clip")
                    AnnotatedPlaybackView(videoURL: videoURL, sidecar: sidecar)
                } else if model.videoURL == nil {
                    missingVideoNote
                }

                SectionHeader(title: "Summary")
                summaryGrid

                if !model.reps.isEmpty {
                    SectionHeader(title: "Reps", subtitle: "\(model.reps.count) detected")
                    repsList
                } else {
                    SectionHeader(title: "Reps")
                    noRepsNote
                }

                if !frames.isEmpty {
                    SectionHeader(title: "Knee angle", subtitle: "Rep boundaries marked in orange")
                    KneeAngleChart(frames: frames, fps: fps)
                        .padding(.vertical, 4)
                }

                metadataFooter
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(model.exercise.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSidecar() }
        .toolbar { toolbarContent }
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deleteSession)
        } message: {
            Text("The video and report will be removed from this device. This can't be undone.")
        }
    }

    // MARK: - Sections

    private var warningsBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Filming issue", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(model.warnings, id: \.self) { warning in
                Text(FormCopy.warning(warning))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatCard(title: "Total reps", value: "\(model.summary.totalReps)", systemImage: "number")
            StatCard(
                title: "Below parallel",
                value: "\(model.summary.repsBelowParallel)/\(model.summary.totalReps)",
                systemImage: "arrow.down.to.line",
                tint: .green
            )
            if model.summary.partialReps > 0 {
                StatCard(title: "Partial reps", value: "\(model.summary.partialReps)", systemImage: "circle.dashed", tint: .orange)
            }
            StatCard(title: "Avg eccentric", value: FormCopy.duration(model.summary.avgEccentricSeconds), systemImage: "timer")
            StatCard(title: "Avg concentric", value: FormCopy.duration(model.summary.avgConcentricSeconds), systemImage: "timer")
            if model.summary.avgBottomPauseSeconds > 0 {
                StatCard(title: "Avg bottom pause", value: FormCopy.duration(model.summary.avgBottomPauseSeconds), systemImage: "pause.circle")
            }
            StatCard(title: "Avg torso lean", value: "\(Int(model.summary.avgTorsoAngleAtBottom.rounded()))°", systemImage: "angle")
            StatCard(title: "Max torso lean", value: "\(Int(model.summary.maxTorsoAngle.rounded()))°", systemImage: "angle", tint: model.summary.maxTorsoAngle > SquatAnalyzer.excessiveLeanDegrees ? .orange : .accentColor)
        }
    }

    private var repsList: some View {
        VStack(spacing: 10) {
            ForEach(model.reps, id: \.repNumber) { rep in
                RepCard(rep: rep)
            }
        }
    }

    private var noRepsNote: some View {
        Text("No complete reps were detected. Film a full rep from the side with your whole body in frame.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var missingVideoNote: some View {
        Label("The original clip is no longer on this device.", systemImage: "film.stack")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var metadataFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let createdAt = model.createdAt {
                Text("Recorded \(createdAt.formatted(date: .abbreviated, time: .shortened))")
            }
            Text("\(fps > 0 ? Int(fps.rounded()) : 30) fps · pose analysis on device")
        }
        .font(.footnote)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let reportFileURL = model.reportFileURL {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: reportFileURL) {
                    Label("Share report", systemImage: "square.and.arrow.up")
                }
            }
        }
        if session != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete session", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Actions

    private func loadSidecar() async {
        guard sidecar == nil else { return }
        let id = model.sessionID
        let loaded = await Task.detached(priority: .userInitiated) {
            SessionStore.loadAnnotations(for: id)
        }.value
        sidecar = loaded
    }

    private func deleteSession() {
        guard let session else { return }
        SessionStore.delete(for: session.id)
        modelContext.delete(session)
        try? modelContext.save()
        dismiss()
    }
}

/// One rep rendered as a card with a depth chip and metric chips.
private struct RepCard: View {
    let rep: RepResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Rep \(rep.repNumber)")
                    .font(.headline)
                if rep.partial {
                    Chip(text: "Partial", tint: .orange, systemImage: "circle.dashed")
                }
                Spacer()
                Chip(text: FormCopy.depth(rep.depth), tint: .depth(rep.depth))
            }

            if !rep.faults.isEmpty {
                HStack(spacing: 6) {
                    ForEach(rep.faults, id: \.self) { fault in
                        Chip(text: FormCopy.fault(fault), tint: .red, systemImage: "exclamationmark.triangle.fill")
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 16) {
                metric("Knee", "\(Int(rep.bottomKneeAngle.rounded()))°")
                metric("Eccentric", FormCopy.duration(rep.eccentricSeconds))
                metric("Concentric", FormCopy.duration(rep.concentricSeconds))
                metric("Torso", "\(Int(rep.torsoAngleAtBottom.rounded()))°")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}
