import SwiftUI
import AVFoundation

struct AnnotatedPlaybackView: View {
    let videoURL: URL
    let annotations: [FrameAnnotation]
    @State private var player: AVPlayer
    @State private var currentFrame: Int = 0

    init(videoURL: URL, annotations: [FrameAnnotation]) {
        self.videoURL = videoURL
        self.annotations = annotations
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
        .onReceive(player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.033, preferredTimescale: 600), queue: .main) { time in
            let frame = Int(time.seconds * 30)
            if frame < annotations.count {
                currentFrame = frame
            }
        }) { _ in }
    }
}
