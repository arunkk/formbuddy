import Foundation
import AVFoundation

final class CameraRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private var completion: ((URL?) -> Void)?

    override init() {
        super.init()
        session.sessionPreset = .hd1280x720
    }

    func startRecording(to url: URL) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "CameraRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No back camera"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }

        session.startRunning()
        output.startRecording(to: url, recordingDelegate: self)
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        self.completion = completion
        output.stopRecording()
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        session.stopRunning()
        completion?(error == nil ? outputFileURL : nil)
        completion = nil
    }
}
