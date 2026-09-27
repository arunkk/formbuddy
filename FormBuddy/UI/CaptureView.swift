import SwiftUI
import AVFoundation

struct CaptureView: View {
    @State private var recorder = CameraRecorder()
    @State private var isRecording = false
    @State private var recordedURL: URL?
    @State private var showAnalyzing = false
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var previewLayer: AVCaptureVideoPreviewLayer?

    var body: some View {
        NavigationStack {
            ZStack {
                if let layer = previewLayer {
                    CameraPreviewView(previewLayer: layer)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
                VStack {
                    Spacer()
                    if isRecording {
                        Text(String(format: "%.1fs / 60s max", elapsed))
                            .foregroundColor(.yellow)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
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
            .onAppear {
                setupPreview()
            }
            .onDisappear {
                recorder.stopRecording { _ in }
            }
        }
    }

    private func setupPreview() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720
        if session.canAddInput(input) { session.addInput(input) }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
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

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        previewLayer.frame = uiView.bounds
    }
}
