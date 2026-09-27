import XCTest
import UIKit
@testable import FormBuddy

/// Exercises the still/card rendering path (Canvas overlay + ImageRenderer)
/// without needing MediaPipe or a real clip.
@MainActor
final class FeedbackRenderingTests: XCTestCase {

    private func syntheticLandmarks() -> [Double] {
        var landmarks = [Double](repeating: 0, count: 99)
        for index in 0..<33 {
            landmarks[index * 3] = 0.3 + Double(index % 5) * 0.05
            landmarks[index * 3 + 1] = 0.1 + Double(index) * 0.02
            landmarks[index * 3 + 2] = 1.0
        }
        return landmarks
    }

    private func annotation(faults: [String]) -> AnnotationFrame {
        AnnotationFrame(
            kneeAngle: 112,
            torsoAngle: 50,
            phase: "descending",
            repCount: 1,
            faults: faults,
            landmarks: syntheticLandmarks()
        )
    }

    private func rep(_ number: Int = 1) -> RepResult {
        RepResult(
            repNumber: number, depth: "above_parallel", bottomKneeAngle: 112,
            torsoAngleAtBottom: 50, eccentricSeconds: 0.4, concentricSeconds: 1.1,
            bottomPauseSeconds: 0, faults: ["insufficient_depth", "excessive_forward_lean"],
            partial: false
        )
    }

    private func solidImage(_ size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testThumbnailRenders() throws {
        let mapper = OrientationMapper(transform: .identity, naturalSize: CGSize(width: 300, height: 400))
        let image = try XCTUnwrap(
            FeedbackCardRenderer.thumbnail(
                image: solidImage(CGSize(width: 300, height: 400)),
                frame: annotation(faults: ["excessive_forward_lean"]),
                rep: rep(),
                mapper: mapper
            )
        )
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        // Portrait source keeps a portrait thumbnail.
        XCTAssertGreaterThan(image.size.height, image.size.width)
    }

    func testCoachCardRenders() throws {
        let mapper = OrientationMapper(transform: .identity, naturalSize: CGSize(width: 300, height: 400))
        let still = CoachCardStill(
            rep: rep(),
            frame: annotation(faults: []),
            image: solidImage(CGSize(width: 300, height: 400))
        )
        let header = CoachCardHeader(
            exercise: "squat", date: Date(), totalReps: 1,
            belowParallel: 0, faultedReps: 1
        )
        let card = try XCTUnwrap(
            FeedbackCardRenderer.coachCard(header: header, stills: [still], mapper: mapper)
        )
        // A card is a vertical composite: header + stills stack downward.
        XCTAssertGreaterThan(card.size.height, card.size.width)
    }

    func testLargeSetCardStaysReasonable() throws {
        let mapper = OrientationMapper(transform: .identity, naturalSize: CGSize(width: 300, height: 400))
        let image = solidImage(CGSize(width: 300, height: 400))
        let stills = (1...24).map { number in
            CoachCardStill(rep: rep(number), frame: annotation(faults: []), image: image)
        }
        let header = CoachCardHeader(
            exercise: "squat", date: Date(), totalReps: 24,
            belowParallel: 10, faultedReps: 3
        )
        let card = try XCTUnwrap(
            FeedbackCardRenderer.coachCard(header: header, stills: stills, mapper: mapper)
        )
        // 24 reps across 3 columns must not become a mile-long strip.
        XCTAssertLessThan(card.size.height / card.size.width, 12)
    }

    func testRotatedTransformStillRenders() throws {
        // 90° rotation: a landscape buffer displays (and renders) as portrait.
        let mapper = OrientationMapper(
            transform: CGAffineTransform(rotationAngle: .pi / 2),
            naturalSize: CGSize(width: 400, height: 300)
        )
        let image = try XCTUnwrap(
            FeedbackCardRenderer.thumbnail(
                image: solidImage(CGSize(width: 400, height: 300)),
                frame: annotation(faults: ["insufficient_depth"]),
                rep: rep(),
                mapper: mapper
            )
        )
        XCTAssertGreaterThan(image.size.height, image.size.width)
    }
}
