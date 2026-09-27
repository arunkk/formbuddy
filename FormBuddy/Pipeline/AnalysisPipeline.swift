import Foundation
import AVFoundation
import CoreVideo
import Observation

@Observable
final class AnalysisPipeline {
    private(set) var progress: Double = 0

    func analyze(videoAt url: URL) async throws -> SquatReport {
        let reader = try VideoFrameReader(url: url)
        let fps = reader.fps

        let estimator = PoseEstimator()!
        let smoother = LandmarkSmoother()
        let analyzer = SquatAnalyzer()

        var emptyFrames = 0
        var totalFrames = 0

        for try await (pixelBuffer, pts) in reader.frames() {
            totalFrames += 1
            let timestampMs = Int64(pts * 1000)
            let detected = estimator.process(pixelBuffer: pixelBuffer, timestampMs: timestampMs)
            if detected == nil { emptyFrames += 1 }
            let smoothed = smoother.update(detected)
            let frame = PoseFrame(landmarks: smoothed, timestamp: Double(totalFrames - 1) / fps)
            _ = analyzer.process(frame)
            progress = Double(totalFrames) / Double(max(totalFrames, 1))
        }

        var report = analyzer.finish()
        report.videoMeta = ["fps": fps, "frame_count": totalFrames, "duration": Double(totalFrames) / fps]
        if totalFrames > 0 && Double(emptyFrames) / Double(totalFrames) > 0.2 {
            report.warnings.append("no_person_in_most_frames")
        }
        return report
    }
}
