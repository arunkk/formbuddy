import Foundation
import MediaPipeTasksVision
import CoreVideo
import UIKit

final class PoseEstimator {
    private let landmarker: PoseLandmarker

    init?() {
        guard let modelPath = Bundle.main.url(forResource: "pose_landmarker_lite", withExtension: "task") else {
            return nil
        }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath.path
        options.runningMode = .video
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minTrackingConfidence = 0.5
        do {
            landmarker = try PoseLandmarker(options: options)
        } catch {
            return nil
        }
    }

    func process(pixelBuffer: CVPixelBuffer, timestampMs: Int64) -> [Double]? {
        do {
            let image = try MPImage(pixelBuffer: pixelBuffer)
            let result = try landmarker.detect(videoFrame: image, timestampInMilliseconds: Int(timestampMs))
            guard let landmarks = result.landmarks.first, !landmarks.isEmpty else { return nil }
            var flat = [Double](repeating: 0, count: 99)
            for (i, lm) in landmarks.enumerated() {
                flat[i*3] = Double(lm.x)
                flat[i*3+1] = Double(lm.y)
                flat[i*3+2] = Double(lm.visibility?.floatValue ?? 0)
            }
            return flat
        } catch {
            return nil
        }
    }
}
