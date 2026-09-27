import SwiftUI
import AVFoundation

/// The feedback player: the original clip with the pose skeleton and
/// body-anchored fault highlights, optionally scoped to a single rep. Scoped
/// playback loops the rep (unless Reduce Motion is on) so the user can study it.
struct FeedbackPlayerView: View {
    let videoURL: URL
    let sidecar: AnnotationSidecar
    let segment: RepSegment?
    var rep: RepResult? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var player = AVPlayer()
    @State private var currentFrame = 0
    @State private var position: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var isScrubbing = false
    @State private var showHighlights = true
    @State private var videoAspect: CGFloat = 9.0 / 16.0
    @State private var mapper: OrientationMapper?
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?

    @State private var isScoped = false
    @State private var rangeStart: Double = 0
    @State private var rangeEnd: Double = 0

    private var frames: [AnnotationFrame] { sidecar.frames }
    private var safeFPS: Double { sidecar.fps > 0 ? sidecar.fps : 30 }

    private var currentAnnotation: AnnotationFrame? {
        guard frames.indices.contains(currentFrame) else { return nil }
        return frames[currentFrame]
    }

    private var activeFaults: [String] {
        guard let annotation = currentAnnotation else { return rep?.faults ?? [] }
        var faults = Set(annotation.faults)
        if let rep { faults.formUnion(rep.faults) }
        return faults.sorted()
    }

    private var sliderRange: ClosedRange<Double> {
        if isScoped {
            let upper = max(rangeEnd, rangeStart + 0.01)
            return rangeStart...upper
        }
        return 0...max(duration, 0.01)
    }

    var body: some View {
        VStack(spacing: 12) {
            videoSurface
            controls
        }
        .onAppear(perform: configurePlayer)
        .onDisappear(perform: teardownPlayer)
        .task { await loadVideoGeometry() }
        .onChange(of: segment) { _, _ in applySegment(autoplay: true) }
    }

    // MARK: - Video surface

    private var videoSurface: some View {
        ZStack {
            Color.black
            PlayerLayerRepresentable(player: player)

            if let annotation = currentAnnotation, let mapper {
                FormHighlightsOverlay(frame: annotation, rep: rep, mapper: mapper, showHighlights: showHighlights)
            }

            hud
        }
        .aspectRatio(videoAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                showHighlights.toggle()
            } label: {
                Image(systemName: showHighlights ? "figure.walk.motion" : "figure.walk")
                    .font(.body.weight(.semibold))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .frame(minWidth: 44, minHeight: 44)
            .padding(6)
            .accessibilityLabel(showHighlights ? "Hide form highlights" : "Show form highlights")
        }
    }

    @ViewBuilder
    private var hud: some View {
        if let annotation = currentAnnotation {
            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Text(isScoped ? "Rep \(rep?.repNumber ?? annotation.repCount)" : "Full set")
                            .font(.caption.weight(.bold))
                        Text(FormCopy.phase(annotation.phase))
                            .font(.caption)
                        if let knee = annotation.kneeAngle {
                            Text("\(Int(knee))°")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                Spacer()
                if showHighlights {
                    HStack {
                        if activeFaults.isEmpty {
                            Chip(text: "Form looks good", tint: .green, systemImage: "checkmark.circle.fill")
                        } else {
                            ForEach(activeFaults, id: \.self) { fault in
                                Chip(text: FormCopy.fault(fault), tint: .red, systemImage: "exclamationmark.triangle.fill")
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(10)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 8) {
            Slider(value: $position, in: sliderRange) { editing in
                isScrubbing = editing
                if !editing { seek(to: position) }
            }
            .onChange(of: position) { _, newValue in
                if isScrubbing { seek(to: newValue) }
            }
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Int(min(position, duration))) seconds of \(Int(duration))")

            HStack {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Text(timeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                if isScoped {
                    Label(reduceMotion ? "Rep view" : "Looping rep", systemImage: "repeat")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var timeLabel: String {
        String(format: "%0.1f / %0.1f s", min(position, duration), duration)
    }

    // MARK: - Player lifecycle

    private func configurePlayer() {
        let item = AVPlayerItem(url: videoURL)
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause
        duration = item.duration.seconds.isFinite ? item.duration.seconds : 0

        let interval = CMTime(seconds: 1.0 / safeFPS, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            isPlaying = player.rate != 0
            guard !isScrubbing else { return }
            position = seconds
            currentFrame = min(max(Int(seconds * safeFPS), 0), max(frames.count - 1, 0))
            handleScope(seconds)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            isPlaying = false
            let restart = isScoped ? rangeStart : 0
            position = restart
            currentFrame = isScoped ? (segment?.startFrame ?? 0) : 0
            player.seek(to: CMTime(seconds: restart, preferredTimescale: 600))
        }
    }

    private func teardownPlayer() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.pause()
    }

    private func handleScope(_ seconds: Double) {
        guard isScoped, rangeEnd > rangeStart else { return }
        guard seconds >= rangeEnd - (1.0 / safeFPS) else { return }
        if reduceMotion {
            player.pause()
            isPlaying = false
        } else {
            player.seek(to: CMTime(seconds: rangeStart, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
            position = rangeStart
            currentFrame = segment?.startFrame ?? 0
        }
    }

    private func applySegment(autoplay: Bool) {
        let start = segment.map { $0.startTime(fps: safeFPS) } ?? 0
        let end = segment.map { $0.endTime(fps: safeFPS) } ?? max(duration, 0)
        isScoped = segment != nil
        rangeStart = start
        rangeEnd = max(end, start)
        seek(to: start)

        if autoplay, segment != nil, !reduceMotion {
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    private func loadVideoGeometry() async {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
        let naturalSize = (try? await track.load(.naturalSize)) ?? CGSize(width: 1080, height: 1920)
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let orientationMapper = OrientationMapper(transform: transform, naturalSize: naturalSize)
        let displayed = orientationMapper.displayedSize
        if displayed.width > 0, displayed.height > 0 {
            videoAspect = displayed.width / displayed.height
        }
        mapper = orientationMapper
        duration = (try? await asset.load(.duration).seconds) ?? duration
    }

    private func togglePlayback() {
        if player.rate == 0 {
            let end = isScoped ? rangeEnd : duration
            if end > 0, position >= end - 0.1 {
                seek(to: isScoped ? rangeStart : 0)
            }
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    private func seek(to seconds: Double) {
        let lower = isScoped ? rangeStart : 0
        let upper = isScoped ? rangeEnd : max(duration, 0)
        let clamped = min(max(seconds, lower), max(upper, lower))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentFrame = min(max(Int(clamped * safeFPS), 0), max(frames.count - 1, 0))
    }
}
