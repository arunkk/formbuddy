import Foundation
import Accelerate
import CoreVideo

/// Downscales BGRA frames before the ML stages.
///
/// MediaPipe resizes its input to ~256 px internally, so feeding it a full
/// 1080p buffer only makes the surrounding pixel work — silhouette suppression
/// and mask resampling — scale with the whole frame. Bounding the analysis
/// resolution keeps that work cheap without changing landmark coordinates,
/// which are normalized.
enum FrameScaler {
    /// Longest side of the frame handed to pose/segmentation.
    static let maxDimension = 512

    /// Returns a scaled copy of `source`, or `nil` when it is already small
    /// enough (callers then use the original buffer).
    static func scaled(_ source: CVPixelBuffer, maxDimension: Int = maxDimension) -> CVPixelBuffer? {
        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let longest = max(sourceWidth, sourceHeight)
        guard longest > maxDimension else { return nil }

        let scale = Double(maxDimension) / Double(longest)
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))

        var destination: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &destination
        ) == kCVReturnSuccess, let output = destination else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
        }
        guard let sourceBase = CVPixelBufferGetBaseAddress(source),
              let outputBase = CVPixelBufferGetBaseAddress(output) else { return nil }

        var sourceBuffer = vImage_Buffer(
            data: sourceBase,
            height: vImagePixelCount(sourceHeight),
            width: vImagePixelCount(sourceWidth),
            rowBytes: CVPixelBufferGetBytesPerRow(source)
        )
        var destinationBuffer = vImage_Buffer(
            data: outputBase,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRow(output)
        )

        let error = vImageScale_ARGB8888(
            &sourceBuffer, &destinationBuffer, nil, vImage_Flags(kvImageHighQualityResampling)
        )
        guard error == kvImageNoError else { return nil }
        return output
    }
}
