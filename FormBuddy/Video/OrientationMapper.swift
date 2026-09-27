import Foundation
import CoreGraphics
import AVFoundation

struct OrientationMapper {
    let transform: CGAffineTransform
    let naturalSize: CGSize

    init(track: AVAssetTrack) {
        self.transform = track.preferredTransform
        self.naturalSize = track.naturalSize
    }

    /// Map a normalized landmark coordinate (0-1) to view coordinates.
    /// Correctly handles the dimension swap from 90°/270° rotations.
    func mapLandmark(x: Double, y: Double, viewSize: CGSize) -> CGPoint {
        let naturalPoint = CGPoint(x: x * naturalSize.width, y: y * naturalSize.height)

        // Transform all four corners to find the post-transform bounding box
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: naturalSize.width, y: 0),
            CGPoint(x: 0, y: naturalSize.height),
            CGPoint(x: naturalSize.width, y: naturalSize.height),
        ]
        let transformed = corners.map { $0.applying(transform) }
        let minX = transformed.map { $0.x }.min()!
        let maxX = transformed.map { $0.x }.max()!
        let minY = transformed.map { $0.y }.min()!
        let maxY = transformed.map { $0.y }.max()!

        let transformedWidth = maxX - minX
        let transformedHeight = maxY - minY

        let transformedPoint = naturalPoint.applying(transform)

        return CGPoint(
            x: (transformedPoint.x - minX) / transformedWidth * viewSize.width,
            y: (transformedPoint.y - minY) / transformedHeight * viewSize.height
        )
    }
}
