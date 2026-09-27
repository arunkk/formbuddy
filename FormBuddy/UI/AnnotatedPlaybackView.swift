import SwiftUI
import AVFoundation
import AVKit

struct AnnotatedPlaybackView: View {
    let videoURL: URL
    let annotations: [FrameAnnotation]
    let fps: Double
    @State private var player: AVPlayer
    @State private var currentFrame: Int = 0
    @State private var timeObserver: Any?

    init(videoURL: URL, annotations: [FrameAnnotation], fps: Double = 30.0) {
        self.videoURL = videoURL
        self.annotations = annotations
        self.fps = fps
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        VStack {
            VideoPlayer(player: player)
                .frame(height: 300)
            if currentFrame < annotations.count {
                let ann = annotations[currentFrame]
                HStack {
                    Text("Phase: \(ann.phase)")
                    if let ka = ann.kneeAngle {
                        Text("Knee: \(Int(ka))°")
                    }
                    Text("Rep: \(ann.repCount)")
                }
                .font(.caption)
            }
        }
        .onAppear {
            let interval = CMTime(seconds: 1.0 / fps, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                let frame = Int(time.seconds * fps)
                if frame < annotations.count {
                    currentFrame = frame
                }
            }
        }
        .onDisappear {
            if let observer = timeObserver {
                player.removeTimeObserver(observer)
            }
        }
    }
}
