import SwiftUI
import AVFoundation
import UIKit

/// Renders rep stills and the composite coach's card to shareable images.
/// Extraction uses the preferred track transform, so the still is upright and
/// the same `OrientationMapper` used for playback keeps the overlay registered.
@MainActor
enum FeedbackCardRenderer {
    static let cardWidth: CGFloat = 900
    static let thumbnailWidth: CGFloat = 200

    /// Pulls a single frame from the clip at `seconds` (displayed orientation).
    static func extractFrame(videoURL: URL, atSeconds seconds: Double) async -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        do {
            let result = try await generator.image(at: CMTime(seconds: max(seconds, 0), preferredTimescale: 600))
            return UIImage(cgImage: result.image)
        } catch {
            return nil
        }
    }

    /// A small annotated still for the rep strip.
    static func thumbnail(image: UIImage, frame: AnnotationFrame, rep: RepResult, mapper: OrientationMapper) -> UIImage? {
        let view = RepStillView(image: image, frame: frame, rep: rep, mapper: mapper, showsCaption: false)
            .frame(width: thumbnailWidth)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// The composite coach's card: header + one annotated still per rep.
    static func coachCard(header: CoachCardHeader, stills: [CoachCardStill], mapper: OrientationMapper) -> UIImage? {
        guard !stills.isEmpty else { return nil }
        let view = CoachCardView(header: header, stills: stills, mapper: mapper, width: cardWidth)
        let renderer = ImageRenderer(content: view)
        // Keep the exported image a sensible size for long sets.
        renderer.scale = stills.count > 12 ? 1 : (stills.count > 6 ? 1.5 : 2)
        renderer.isOpaque = true
        return renderer.uiImage
    }

    static func savePNG(_ image: UIImage, to url: URL) {
        guard let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadImage(at url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
