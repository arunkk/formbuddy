import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import Observation
import OSLog

/// Everything the UI needs to persist and replay one analyzed clip.
struct AnalysisResult {
    var report: SquatReport
    var sidecar: AnnotationSidecar
    var preferredTransform: CGAffineTransform
}

private final class AnalysisFrameProcessor: @unchecked Sendable {
    private let estimator: PoseEstimator
    private let segmenter: PersonSegmenter?
    private let smoother = LandmarkSmoother()
    private let analyzer = SquatAnalyzer()
    private var annotations: [AnnotationFrame] = []
    private(set) var emptyFrames = 0
    private(set) var processedFrames = 0
    private(set) var segmentedFrames = 0
    private(set) var rejectedFrames = 0

    init(estimator: PoseEstimator, segmenter: PersonSegmenter?) {
        self.estimator = estimator
        self.segmenter = segmenter
    }

    func process(pixelBuffer: CVPixelBuffer, presentationTimestamp: Double, analysisTimestamp: Double) {
        let timestampMs = Int64(presentationTimestamp * 1000)

        // Segment the best person, then hide everything else so the pose model
        // never sees the rack, plates or benches.
        var mask: PersonMask?
        if let segmenter {
            mask = segmenter.process(pixelBuffer: pixelBuffer, timestampMs: timestampMs)
            if let mask {
                PersonMaskBuilder.suppressBackground(pixelBuffer: pixelBuffer, mask: mask)
                segmentedFrames += 1
            }
        }

        var detected = estimator.process(pixelBuffer: pixelBuffer, timestampMs: timestampMs)

        // Drop pose results that fall mostly outside the silhouette (the model
        // locked onto the environment rather than the lifter).
        if let detectedLandmarks = detected, let mask,
           PersonMaskBuilder.landmarkInsideFraction(mask, landmarks: detectedLandmarks)
               < PersonMaskBuilder.minLandmarkInsideFraction {
            detected = nil
            rejectedFrames += 1
        }

        // Count empties at the detection level: the smoother deliberately
        // carries the last landmarks forward, so its output must not be used.
        if detected == nil { emptyFrames += 1 }
        let smoothed = smoother.update(detected)
        let annotation = analyzer.process(PoseFrame(landmarks: smoothed, timestamp: analysisTimestamp))
        annotations.append(
            AnnotationFrame(
                kneeAngle: annotation.kneeAngle,
                torsoAngle: annotation.torsoAngle,
                phase: annotation.phase,
                repCount: annotation.repCount,
                faults: annotation.faults,
                landmarks: smoothed
            )
        )
        processedFrames += 1
    }

    func finish(fps: Double, segmentationEnabled: Bool) -> (report: SquatReport, sidecar: AnnotationSidecar) {
        var report = analyzer.finish()
        var videoMeta: [String: Any] = [
            "fps": fps,
            "frame_count": processedFrames,
            "duration": Double(processedFrames) / fps,
        ]
        if segmentationEnabled {
            videoMeta["segmented_frames"] = segmentedFrames
            videoMeta["pose_rejected_outside_person"] = rejectedFrames
        }
        report.videoMeta = videoMeta
        if processedFrames > 0 && Double(emptyFrames) / Double(processedFrames) > 0.2 {
            report.warnings.append("no_person_in_most_frames")
        }
        let sidecar = AnnotationSidecar(frames: annotations, fps: fps, frameCount: processedFrames)
        return (report, sidecar)
    }
}

@MainActor
@Observable
final class AnalysisPipeline {
    private(set) var progress: Double = 0
    private static let logger = Logger(subsystem: "com.formbuddy.app", category: "analysis")

    func analyze(videoAt url: URL, segmentPerson: Bool = true) async throws -> AnalysisResult {
        Self.logger.info("Starting video analysis: \(url.lastPathComponent, privacy: .public)")
        let reader = try await VideoFrameReader(url: url)
        let fps = reader.fps
        let estimatedFrames = reader.estimatedFrameCount
        Self.logger.info("Video reader ready: fps=\(fps), estimatedFrames=\(estimatedFrames)")

        guard let estimator = PoseEstimator() else {
            throw NSError(domain: "AnalysisPipeline", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize pose estimator. Check that the bundled MediaPipe model is present."])
        }

        // The segmenter is best-effort: if it cannot be created we still
        // analyze, just without the person gate.
        var segmenter: PersonSegmenter?
        var segmentationEnabled = false
        if segmentPerson {
            if let created = PersonSegmenter() {
                segmenter = created
                segmentationEnabled = true
            } else {
                Self.logger.error("Person segmenter unavailable; continuing without segmentation")
            }
        }

        let processor = AnalysisFrameProcessor(estimator: estimator, segmenter: segmenter)
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
        let (report, sidecar) = processor.finish(fps: fps, segmentationEnabled: segmentationEnabled)
        progress = 1
        Self.logger.info("Analysis complete: frames=\(processor.processedFrames), reps=\(report.summary.totalReps), emptyFrames=\(processor.emptyFrames), segmented=\(processor.segmentedFrames), rejected=\(processor.rejectedFrames)")
        return AnalysisResult(report: report, sidecar: sidecar, preferredTransform: reader.preferredTransform)
    }
}
