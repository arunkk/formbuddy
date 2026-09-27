import SwiftUI
import AVFoundation

struct CaptureView: View {
    @State private var recorder = CameraRecorder()
    @State private var isRecording = false
    @State private var recordedURL: URL?
    @State private var showAnalyzing = false
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    Text(isRecording ? "Recording..." : "Tap to record")
                        .foregroundColor(.white)
                        .font(.title)
                    if isRecording {
                        Text(String(format: "%.1fs / 60s max", elapsed))
                            .foregroundColor(.yellow)
                    }
                }
            }
            .navigationTitle("Capture")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isRecording ? "Stop" : "Record") {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showAnalyzing) {
                if let url = recordedURL {
                    AnalyzingView(videoURL: url)
                }
            }
        }
    }

    private func startRecording() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording.mov")
        try? recorder.startRecording(to: url)
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            elapsed += 0.1
            if elapsed >= 60 { stopRecording() }
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        recorder.stopRecording { url in
            recordedURL = url
            showAnalyzing = true
        }
        isRecording = false
    }
}
