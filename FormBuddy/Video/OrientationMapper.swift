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

    func map(point: CGPoint) -> CGPoint {
        // Apply the preferred transform to map from natural coordinates to view coordinates
        let transformed = point.applying(transform)
        return transformed
    }

    func mapLandmark(x: Double, y: Double, viewSize: CGSize) -> CGPoint {
        // Landmarks are normalized (0-1) to the natural buffer
        let naturalPoint = CGPoint(x: x * naturalSize.width, y: y * naturalSize.height)
        let transformed = map(point: naturalPoint)
        // Scale to view size
        return CGPoint(
            x: transformed.x * viewSize.width / naturalSize.width,
            y: transformed.y * viewSize.height / naturalSize.height
        )
    }
}
