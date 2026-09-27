import SwiftUI
import AVFoundation
import PhotosUI
import OSLog

struct CaptureView: View {
    private static let logger = Logger(subsystem: "com.formbuddy.app", category: "video-import")
    @State private var recorder = CameraRecorder()
    @State private var isRecording = false
    @State private var analysisURL: URL?
    @State private var isImporting = false
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?

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
                if isImporting {
                    ProgressView("Importing video…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .navigationTitle("Capture")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Record") {
                            if isRecording { stopRecording() } else { startRecording() }
                        }
                        Button("Import from Photos") {
                            showPhotoPicker = true
                        }
                        Button("Import Test Video from Photos") {
                            useTestVideo()
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(item: $analysisURL) { url in
                AnalyzingView(videoURL: url)
            }
            .onAppear {
                setupPreview()
            }
            .onDisappear {
                recorder.stopRecording { _ in }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .videos)
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem = newItem else { return }
                Task {
                    isImporting = true
                    Self.logger.info("Photos video selected; starting transferable import")
                    do {
                        guard let imported = try await newItem.loadTransferable(type: ImportedVideo.self) else {
                            throw VideoImportError.sourceMissing
                        }
                        let attributes = try FileManager.default.attributesOfItem(atPath: imported.url.path)
                        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                        guard size > 0 else { throw VideoImportError.emptyFile }
                        await MainActor.run {
                            Self.logger.info("Video imported successfully (\(size) bytes); navigating to analysis")
                            isImporting = false
                            analysisURL = imported.url
                            selectedPhoto = nil
                        }
                    } catch {
                        await MainActor.run {
                            Self.logger.error("Photos video import failed: \(error.localizedDescription, privacy: .public)")
                            isImporting = false
                            selectedPhoto = nil
                            errorMessage = "Failed to import video: \(error.localizedDescription)"
                            showError = true
                        }
                    }
                }
            }
        }
    }

    private func useTestVideo() {
        // The test clip lives in Photos on the simulator/device; host Mac paths
        // are not accessible from the app sandbox.
        showPhotoPicker = true
    }

    private func setupPreview() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            errorMessage = "No camera available. Use 'Import from Photos' or 'Use Test Video'."
            showError = true
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            errorMessage = "Cannot access camera."
            showError = true
            return
        }
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
        guard previewLayer != nil else {
            errorMessage = "Camera not available. Run on a physical device."
            showError = true
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording.mov")
        do {
            try recorder.startRecording(to: url)
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                elapsed += 0.1
                if elapsed >= 60 { stopRecording() }
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            showError = true
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        isRecording = false
        recorder.stopRecording { url in
            if let url = url {
                analysisURL = url
            } else {
                errorMessage = "Recording failed or was cancelled."
                showError = true
            }
        }
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
