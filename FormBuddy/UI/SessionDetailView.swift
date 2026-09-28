import SwiftUI
import SwiftData
import UIKit
import AVFoundation

/// The feedback experience for one session: an annotated video that highlights
/// what's wrong, scoped rep by rep, plus a shareable "coach's card" still that
/// shows every rep's faults at a glance.
struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let model: SessionDetailModel
    private let session: Session?
    @State private var showDeleteConfirm = false
    @State private var sidecar: AnnotationSidecar?

    @State private var selectedRep: Int?
    @State private var thumbnails: [Int: UIImage] = [:]
    @State private var cardImage: UIImage?
    @State private var isBuildingArtifacts = false
    @State private var didBuildArtifacts = false
    /// Measured height of the scroll viewport, used to cap the player so a tall
    /// portrait clip zooms out to fit instead of pushing the controls off screen.
    @State private var viewportHeight: CGFloat = 0

    init(session: Session) {
        self.model = SessionDetailModel(session: session)
        self.session = session
    }

    private var fps: Double { sidecar?.fps ?? 30 }

    private var segments: [RepSegment] {
        guard let sidecar else { return [] }
        return RepSegments.derive(from: sidecar)
    }

    private var feedback: [RepFeedback] {
        RepFeedback.build(reps: model.reps, segments: segments)
    }

    private var selectedFeedback: RepFeedback? {
        guard let selectedRep else { return nil }
        return feedback.first { $0.repNumber == selectedRep }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !model.warnings.isEmpty {
                    warningsBanner
                }

                feedbackSection
                coachCardSection

                SectionHeader(title: "Summary")
                summaryGrid

                if segments.isEmpty {
                    if model.reps.isEmpty {
                        SectionHeader(title: "Reps")
                        noRepsNote
                    } else {
                        SectionHeader(title: "Reps", subtitle: "\(model.reps.count) detected")
                        repsList
                    }
                }

                if let frames = sidecar?.frameAnnotations, !frames.isEmpty {
                    SectionHeader(title: "Knee angle", subtitle: "Rep boundaries marked in orange")
                    KneeAngleChart(frames: frames, fps: fps, segments: segments, reps: model.reps)
                        .padding(.vertical, 4)
                }

                metadataFooter
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewportHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newValue in viewportHeight = newValue }
            }
        }
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSidecar() }
        .task(id: sidecar?.frameCount) {
            guard sidecar != nil else { return }
            await buildArtifacts()
        }
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

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackSection: some View {
        if let videoURL = model.videoURL, let sidecar, !sidecar.frames.isEmpty {
            SectionHeader(title: "Feedback", subtitle: "Form highlights drawn over your clip")
            FeedbackPlayerView(
                videoURL: videoURL,
                sidecar: sidecar,
                segment: selectedFeedback?.segment,
                rep: selectedFeedback?.result,
                maxVideoHeight: VideoFitGeometry.maximumHeight(viewport: viewportHeight)
            )
            if !feedback.isEmpty {
                RepFeedbackStrip(feedback: feedback, thumbnails: thumbnails, selectedRep: $selectedRep)
            }
            if let selectedFeedback, selectedFeedback.segment != nil {
                RepFeedbackCard(item: selectedFeedback)
            }
        } else if model.videoURL == nil {
            missingVideoNote
        }
    }

    // MARK: - Coach's card

    @ViewBuilder
    private var coachCardSection: some View {
        if !model.reps.isEmpty {
            SectionHeader(title: "Coach's card", subtitle: "Every rep's faults in one image")

            if let cardImage {
                VStack(alignment: .leading, spacing: 12) {
                    Image(uiImage: cardImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 1)
                        }
                        .accessibilityLabel("Form card showing \(model.reps.count) reps and their form notes")

                    ShareLink(
                        item: Image(uiImage: cardImage),
                        preview: SharePreview("Form card", image: Image(uiImage: cardImage))
                    ) {
                        Label("Share form card", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            } else if isBuildingArtifacts {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Building your form card…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Text("The form card needs the original clip. It isn't available for this session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
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

    // MARK: - Loading

    private func loadSidecar() async {
        guard sidecar == nil else { return }
        let id = model.sessionID
        let loaded = await Task.detached(priority: .userInitiated) {
            SessionStore.loadAnnotations(for: id)
        }.value
        sidecar = loaded
    }

    @MainActor
    private func buildArtifacts() async {
        guard !didBuildArtifacts else { return }
        guard let sidecar, let videoURL = model.videoURL, !feedback.isEmpty else {
            didBuildArtifacts = true
            return
        }
        isBuildingArtifacts = true
        defer {
            isBuildingArtifacts = false
            didBuildArtifacts = true
        }

        let cardURL = SessionStore.feedbackCardURL(for: model.sessionID)
        if let cached = FeedbackCardRenderer.loadImage(at: cardURL) {
            cardImage = cached
        }

        guard let track = try? await AVURLAsset(url: videoURL).loadTracks(withMediaType: .video).first else { return }
        let naturalSize = (try? await track.load(.naturalSize)) ?? CGSize(width: 1080, height: 1920)
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let mapper = OrientationMapper(transform: transform, naturalSize: naturalSize)

        var stills: [CoachCardStill] = []
        for item in feedback {
            guard let segment = item.segment, sidecar.frames.indices.contains(segment.bottomFrame) else { continue }
            let frame = sidecar.frames[segment.bottomFrame]
            let thumbURL = SessionStore.thumbnailURL(for: model.sessionID, rep: item.repNumber)

            if let thumb = FeedbackCardRenderer.loadImage(at: thumbURL) {
                thumbnails[item.repNumber] = thumb
            }

            let needsThumbnail = thumbnails[item.repNumber] == nil
            let needsCardStill = cardImage == nil
            guard needsThumbnail || needsCardStill else { continue }

            guard let still = await FeedbackCardRenderer.extractFrame(
                videoURL: videoURL,
                atSeconds: segment.bottomTime(fps: fps)
            ) else { continue }

            if needsThumbnail,
               let thumb = FeedbackCardRenderer.thumbnail(image: still, frame: frame, rep: item.result, mapper: mapper) {
                thumbnails[item.repNumber] = thumb
                FeedbackCardRenderer.savePNG(thumb, to: thumbURL)
            }

            if needsCardStill {
                stills.append(CoachCardStill(rep: item.result, frame: frame, image: still))
            }

            // Rendering thumbnails runs on the main actor; yield so the screen
            // stays responsive while a long set's card is built.
            await Task.yield()
        }

        if cardImage == nil, !stills.isEmpty {
            let header = CoachCardHeader(
                exercise: model.exercise,
                date: model.createdAt,
                totalReps: model.summary.totalReps,
                belowParallel: model.summary.repsBelowParallel,
                faultedReps: model.reps.filter { !$0.faults.isEmpty }.count
            )
            if let card = FeedbackCardRenderer.coachCard(header: header, stills: stills, mapper: mapper) {
                cardImage = card
                FeedbackCardRenderer.savePNG(card, to: cardURL)
            }
        }
    }

    private func deleteSession() {
        guard let session else { return }
        SessionStore.delete(for: session.id)
        modelContext.delete(session)
        try? modelContext.save()
        dismiss()
    }
}

/// One rep rendered as a card with a depth chip and metric chips. Used when the
/// clip is no longer available to build the annotated feedback.
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
