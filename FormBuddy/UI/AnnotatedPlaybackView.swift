import SwiftUI
import AVFoundation
import UIKit

/// BlazePose body connections (33-landmark topology) used to draw the skeleton.
enum PoseSkeleton {
    static let connections: [(Int, Int)] = [
        // Torso
        (11, 12), (11, 23), (12, 24), (23, 24),
        // Arms
        (11, 13), (13, 15), (12, 14), (14, 16),
        // Hands
        (15, 17), (15, 19), (15, 21), (17, 19), (16, 18), (16, 20), (16, 22), (18, 20),
        // Legs
        (23, 25), (25, 27), (27, 29), (27, 31), (29, 31),
        (24, 26), (26, 28), (28, 30), (28, 32), (30, 32),
    ]
}

/// Annotated playback: the original clip with a landmark skeleton, live phase /
/// rep / knee-angle HUD, fault badges, and a scrubber — all drawn at playback
/// time from the stored sidecar (no re-encoded video).
struct AnnotatedPlaybackView: View {
    let videoURL: URL
    let sidecar: AnnotationSidecar

    @State private var player = AVPlayer()
    @State private var currentFrame = 0
    @State private var position: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var isPlaying = false
    @State private var showSkeleton = true
    @State private var videoAspect: CGFloat = 9.0 / 16.0
    @State private var mapper: OrientationMapper?
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?

    private var frames: [AnnotationFrame] { sidecar.frames }
    private var safeFPS: Double { sidecar.fps > 0 ? sidecar.fps : 30 }

    private var currentAnnotation: AnnotationFrame? {
        guard frames.indices.contains(currentFrame) else { return nil }
        return frames[currentFrame]
    }

    var body: some View {
        VStack(spacing: 12) {
            videoSurface
            controls
            if !repStartFrames.isEmpty {
                repPicker
            }
        }
        .onAppear(perform: configurePlayer)
        .onDisappear(perform: teardownPlayer)
        .task { await loadVideoGeometry() }
    }

    // MARK: - Video surface

    private var videoSurface: some View {
        ZStack {
            Color.black
            PlayerLayerRepresentable(player: player)

            if showSkeleton, let mapper {
                skeleton(mapper: mapper)
            }

            hud
        }
        .aspectRatio(videoAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                showSkeleton.toggle()
            } label: {
                Image(systemName: showSkeleton ? "figure.walk.motion" : "figure.walk")
                    .font(.body.weight(.semibold))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(10)
            .accessibilityLabel(showSkeleton ? "Hide skeleton overlay" : "Show skeleton overlay")
        }
    }

    private func skeleton(mapper: OrientationMapper) -> some View {
        Canvas { context, size in
            guard let landmarks = currentAnnotation?.landmarks, landmarks.count == 99 else { return }

            var path = Path()
            for (a, b) in PoseSkeleton.connections {
                guard landmarks[a * 3 + 2] >= 0.5, landmarks[b * 3 + 2] >= 0.5 else { continue }
                let start = mapper.mapLandmark(x: landmarks[a * 3], y: landmarks[a * 3 + 1], viewSize: size)
                let end = mapper.mapLandmark(x: landmarks[b * 3], y: landmarks[b * 3 + 1], viewSize: size)
                path.move(to: start)
                path.addLine(to: end)
            }
            context.stroke(path, with: .color(.green), style: StrokeStyle(lineWidth: 3, lineCap: .round))

            for index in 0..<33 where landmarks[index * 3 + 2] >= 0.5 {
                let point = mapper.mapLandmark(x: landmarks[index * 3], y: landmarks[index * 3 + 1], viewSize: size)
                let dot = Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(.white))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var hud: some View {
        if let annotation = currentAnnotation {
            VStack {
                HStack {
                    HStack(spacing: 8) {
                        Text("Rep \(annotation.repCount)")
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
                if !annotation.faults.isEmpty {
                    HStack {
                        ForEach(annotation.faults, id: \.self) { fault in
                            Chip(text: FormCopy.fault(fault), tint: .red, systemImage: "exclamationmark.triangle.fill")
                        }
                        Spacer()
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
            Slider(value: $position, in: 0...max(duration, 0.01)) { editing in
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

                Text("fps \(Int(safeFPS.rounded()))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var repPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(repStartFrames, id: \.rep) { item in
                    Button("Rep \(item.rep)") {
                        seek(to: Double(item.frame) / safeFPS)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var timeLabel: String {
        String(format: "%0.1f / %0.1f s", min(position, duration), duration)
    }

    private struct RepStart: Hashable {
        let rep: Int
        let frame: Int
    }

    private var repStartFrames: [RepStart] {
        var starts: [RepStart] = []
        var previous = 0
        for (index, frame) in frames.enumerated() where frame.repCount > previous {
            previous = frame.repCount
            starts.append(RepStart(rep: frame.repCount, frame: index))
        }
        return starts
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
            let frame = Int(seconds * safeFPS)
            currentFrame = min(max(frame, 0), max(frames.count - 1, 0))
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            isPlaying = false
            position = 0
            currentFrame = 0
            player.seek(to: .zero)
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
            if duration > 0, position >= duration - 0.1 {
                player.seek(to: .zero)
                position = 0
                currentFrame = 0
            }
            player.play()
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    private func seek(to seconds: Double) {
        let clamped = min(max(seconds, 0), max(duration, 0))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentFrame = min(max(Int(clamped * safeFPS), 0), max(frames.count - 1, 0))
    }
}

/// A UIView backed by `AVPlayerLayer` so the skeleton overlay can be sized to
/// the exact displayed video rect.
private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct PlayerLayerRepresentable: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}
