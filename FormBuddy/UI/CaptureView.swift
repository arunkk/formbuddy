import SwiftUI
@preconcurrency import AVFoundation
import PhotosUI
import UIKit
import OSLog

struct CaptureView: View {
    private static let logger = Logger(subsystem: "com.formbuddy.app", category: "capture")
    private static let maxDuration: TimeInterval = 60

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var recorder = CameraRecorder()
    @State private var captureSession: AVCaptureSession?
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var status: CameraStatus = .checking
    @State private var isRecording = false
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var analysisURL: URL?
    @State private var isImporting = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var showError = false
    /// Aspect of the preview after the capture connection's (default portrait)
    /// orientation is applied, so the framing guide can hug the real frame.
    @State private var previewAspect: CGFloat = 720.0 / 1280.0

    enum CameraStatus: Equatable {
        case checking
        case ready
        case unavailable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                previewBackground
                if status == .ready {
                    controls
                } else if status == .unavailable {
                    unavailableState
                } else {
                    ProgressView("Starting camera…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }

                if isImporting {
                    ProgressView("Importing video…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Import from Photos", systemImage: "photo.on.rectangle")
                    }
                }
            }
            .navigationDestination(item: $analysisURL) { url in
                AnalyzingView(videoURL: url, onFinish: { dismiss() })
            }
            .alert("Something went wrong", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .videos)
            .onChange(of: selectedPhoto) { _, newItem in
                handlePhotoSelection(newItem)
            }
            .task { await prepareCamera() }
            .onDisappear(perform: stopEverything)
            .interactiveDismissDisabled(isRecording || isImporting)
        }
    }

    // MARK: - Camera

    @ViewBuilder
    private var previewBackground: some View {
        ZStack {
            // Fill under the notch / home indicator; the preview itself stays
            // inside the safe area so the framing guide never hides behind the
            // navigation bar.
            Color.black.ignoresSafeArea()
            if let layer = previewLayer {
                GeometryReader { proxy in
                    ZStack {
                        CameraPreviewView(previewLayer: layer)
                        if status == .ready {
                            // The preview shows the whole recorded frame (it is
                            // never cropped), so the guide tracks the real frame
                            // the analyzer will see.
                            let rect = VideoFitGeometry.fittedRect(aspect: previewAspect, available: proxy.size)
                            FramingGuide()
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
            }
        }
    }

    private func prepareCamera() async {
        // Returning from analysis: reuse the configured session and restart it.
        if previewLayer != nil {
            let session = captureSession
            DispatchQueue.global(qos: .userInitiated).async { session?.startRunning() }
            return
        }
        guard await requestCameraAccess() else {
            status = .unavailable
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            status = .unavailable
            return
        }
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720
        if session.canAddInput(input) { session.addInput(input) }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        // Show the entire recorded frame rather than a crop, so what you frame
        // is exactly what gets analyzed.
        layer.videoGravity = .resizeAspect

        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        if dimensions.width > 0, dimensions.height > 0 {
            let width = CGFloat(dimensions.width)
            let height = CGFloat(dimensions.height)
            // The connection defaults to portrait, so a landscape sensor buffer
            // is displayed rotated: the short side becomes the on-screen width.
            previewAspect = width > height ? height / width : width / height
        }

        captureSession = session
        previewLayer = layer
        status = .ready

        let sessionRef = session
        DispatchQueue.global(qos: .userInitiated).async {
            sessionRef.startRunning()
        }
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private var controls: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                Text(isRecording ? String(format: "%.1fs · up to 60s", elapsed) : "Side view · whole body in frame")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.35), in: Capsule())
                    .contentTransition(.numericText())

                RecordButton(isRecording: isRecording, progress: min(elapsed / Self.maxDuration, 1)) {
                    isRecording ? stopRecording() : startRecording()
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: isRecording)

                Text("Record a set, or import a clip you've already filmed")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera unavailable")
                .font(.title3.weight(.semibold))
            Text("This device has no usable camera, or access is turned off. You can still import a clip from Photos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showPhotoPicker = true
            } label: {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderedProminent)

            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Recording

    private func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).mov")
        do {
            try recorder.startRecording(to: url)
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                elapsed += 0.1
                if elapsed >= Self.maxDuration { stopRecording() }
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            showError = true
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        isRecording = false
        recorder.stopRecording { url in
            if let url {
                analysisURL = url
            } else {
                errorMessage = "Recording failed or was cancelled."
                showError = true
            }
        }
    }

    private func stopEverything() {
        timer?.invalidate()
        timer = nil
        if isRecording {
            isRecording = false
            recorder.stopRecording { _ in }
        }
        captureSession?.stopRunning()
    }

    // MARK: - Import

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            isImporting = true
            Self.logger.info("Photos video selected; starting transferable import")
            do {
                guard let imported = try await item.loadTransferable(type: ImportedVideo.self) else {
                    throw VideoImportError.sourceMissing
                }
                let attributes = try FileManager.default.attributesOfItem(atPath: imported.url.path)
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0 else { throw VideoImportError.emptyFile }
                await MainActor.run {
                    Self.logger.info("Video imported successfully (\(size) bytes); navigating to analysis")
                    isImporting = false
                    selectedPhoto = nil
                    analysisURL = imported.url
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

/// Dashed head-to-toe framing guide with a side-view reminder.
private struct FramingGuide: View {
    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 24
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .foregroundStyle(.white.opacity(0.75))
                .padding(inset)

            VStack {
                Label("Side view · head to toe in frame", systemImage: "figure.strengthtraining.traditional")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.35), in: Capsule())
                    .padding(.top, inset + 12)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Large camera shutter that shows record progress around its rim.
private struct RecordButton: View {
    let isRecording: Bool
    let progress: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(progress, 0.001))
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RoundedRectangle(cornerRadius: isRecording ? 6 : 26, style: .continuous)
                    .fill(.red)
                    .frame(width: isRecording ? 30 : 56, height: isRecording ? 30 : 56)
            }
            .frame(width: 76, height: 76)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint(isRecording ? "Stops and analyzes the clip" : "Records up to 60 seconds")
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
