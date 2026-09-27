import Foundation
import MediaPipeTasksVision
import CoreVideo

/// Segments the best person out of video frames with MediaPipe's selfie
/// segmentation model (bundled `selfie_segmenter.tflite`).
///
/// Runs in `.video` mode so the person mask is tracked temporally, mirroring
/// the pose estimator and the Python `formbuddy.segment.PersonSegmenter`. This
/// is the only file that imports the segmentation model; the mask maths lives
/// in `PersonMaskBuilder` so it stays testable without the ML runtime.
final class PersonSegmenter {
    private let segmenter: ImageSegmenter

    init?() {
        guard let modelPath = Bundle.main.url(forResource: "selfie_segmenter", withExtension: "tflite") else {
            return nil
        }
        let options = ImageSegmenterOptions()
        options.baseOptions.modelAssetPath = modelPath.path
        options.runningMode = .video
        options.shouldOutputConfidenceMasks = true
        options.shouldOutputCategoryMask = false
        do {
            segmenter = try ImageSegmenter(options: options)
        } catch {
            return nil
        }
    }

    /// The best-person silhouette for this frame, or `nil` when no person is
    /// found (or segmentation fails).
    func process(pixelBuffer: CVPixelBuffer, timestampMs: Int64) -> PersonMask? {
        do {
            let image = try MPImage(pixelBuffer: pixelBuffer)
            let result = try segmenter.segment(videoFrame: image, timestampInMilliseconds: Int(timestampMs))
            guard let mask = result.confidenceMasks?.first else { return nil }
            let width = Int(mask.width)
            let height = Int(mask.height)
            guard width > 0, height > 0 else { return nil }
            let probability = Array(UnsafeBufferPointer(start: mask.float32Data, count: width * height))
            return PersonMaskBuilder.bestPersonMask(probability: probability, width: width, height: height)
        } catch {
            return nil
        }
    }
}
