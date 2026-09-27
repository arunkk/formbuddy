import Foundation
import AVFoundation
import CoreVideo
import Observation
import OSLog

private final class AnalysisFrameProcessor: @unchecked Sendable {
    private let estimator: PoseEstimator
    private let smoother = LandmarkSmoother()
    private let analyzer = SquatAnalyzer()
    private(set) var emptyFrames = 0
    private(set) var processedFrames = 0

    init(estimator: PoseEstimator) {
        self.estimator = estimator
    }

    func process(pixelBuffer: CVPixelBuffer, presentationTimestamp: Double, analysisTimestamp: Double) {
        let detected = estimator.process(
            pixelBuffer: pixelBuffer,
            timestampMs: Int64(presentationTimestamp * 1000)
        )
        if detected == nil { emptyFrames += 1 }
        let smoothed = smoother.update(detected)
        _ = analyzer.process(PoseFrame(landmarks: smoothed, timestamp: analysisTimestamp))
        processedFrames += 1
    }

    func finish(fps: Double) -> SquatReport {
        var report = analyzer.finish()
        report.videoMeta = [
            "fps": fps,
            "frame_count": processedFrames,
            "duration": Double(processedFrames) / fps,
        ]
        if processedFrames > 0 && Double(emptyFrames) / Double(processedFrames) > 0.2 {
            report.warnings.append("no_person_in_most_frames")
        }
        return report
    }
}

@MainActor
@Observable
final class AnalysisPipeline {
    private(set) var progress: Double = 0
    private static let logger = Logger(subsystem: "com.formbuddy.app", category: "analysis")

    func analyze(videoAt url: URL) async throws -> SquatReport {
        Self.logger.info("Starting video analysis: \(url.lastPathComponent, privacy: .public)")
        let reader = try VideoFrameReader(url: url)
        let fps = reader.fps
        let estimatedFrames = reader.estimatedFrameCount
        Self.logger.info("Video reader ready: fps=\(fps), estimatedFrames=\(estimatedFrames)")

        guard let estimator = PoseEstimator() else {
            throw NSError(domain: "AnalysisPipeline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize pose estimator. Check that the bundled MediaPipe model is present."])
        }
        let processor = AnalysisFrameProcessor(estimator: estimator)
        progress = 0

        for try await (pixelBuffer, pts) in reader.frames() {
            try Task.checkCancellation()
            let analysisTimestamp = Double(processor.processedFrames) / fps
            await Task.detached(priority: .userInitiated) {
                processor.process(
                    pixelBuffer: pixelBuffer,
                    presentationTimestamp: pts,
                    analysisTimestamp: analysisTimestamp
                )
            }.value
            progress = AnalysisProgress.fraction(
                processedFrames: processor.processedFrames,
                estimatedFrames: estimatedFrames
            )
            await reader.acknowledgeFrame()
        }

        guard processor.processedFrames > 0 else {
            throw NSError(domain: "AnalysisPipeline", code: 2, userInfo: [NSLocalizedDescriptionKey: "No video frames could be decoded from the selected clip."])
        }
        let report = processor.finish(fps: fps)
        progress = 1
        Self.logger.info("Analysis complete: frames=\(processor.processedFrames), reps=\(report.summary.totalReps), emptyFrames=\(processor.emptyFrames)")
        return report
    }
}
