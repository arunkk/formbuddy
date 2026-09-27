import Foundation

/// A body joint a fault highlight is anchored to.
enum BodyJoint: String, Sendable {
    case shoulder, hip, knee, ankle
}

/// How a fault is drawn over the video.
enum FaultHighlight: String, Sendable {
    /// Knee-angle arc tinted by the depth verdict.
    case kneeArc
    /// Torso wedge against vertical.
    case torsoWedge
    /// A tempo callout on the descent.
    case tempo
}

/// Presentation metadata for one analyzer fault. Keeps the raw fault string as
/// the data contract while giving the UI plain language and a visual treatment.
struct FaultVisual: Equatable, Sendable {
    let fault: String
    let highlight: FaultHighlight
    let joint: BodyJoint
    let title: String
    let symbol: String
    let detail: String
}

enum FaultVisuals {
    static let all: [FaultVisual] = [
        FaultVisual(
            fault: "insufficient_depth",
            highlight: .kneeArc,
            joint: .knee,
            title: "Not deep enough",
            symbol: "arrow.down.to.line",
            detail: "Aim for your hip crease below the knee — a knee angle under 90° at the bottom."
        ),
        FaultVisual(
            fault: "excessive_forward_lean",
            highlight: .torsoWedge,
            joint: .shoulder,
            title: "Leaning too far forward",
            symbol: "angle",
            detail: "Keep your torso closer to upright — under 45° from vertical at the bottom."
        ),
        FaultVisual(
            fault: "uncontrolled_descent",
            highlight: .tempo,
            joint: .hip,
            title: "Dropping too fast",
            symbol: "timer",
            detail: "Lower under control — take at least 1 second on the way down."
        ),
    ]

    static func visual(for fault: String) -> FaultVisual? {
        all.first { $0.fault == fault }
    }

    /// Landmark index for a joint on the near side. Leg joints come from
    /// `sideLandmarks`; shoulders use the analyzer's indices.
    static func landmarkIndex(for joint: BodyJoint, side: Side) -> Int? {
        switch joint {
        case .shoulder:
            return side == .left ? SquatAnalyzer.shoulderLeft : SquatAnalyzer.shoulderRight
        case .hip:
            return sideLandmarks[side.rawValue]?["hip"]
        case .knee:
            return sideLandmarks[side.rawValue]?["knee"]
        case .ankle:
            return sideLandmarks[side.rawValue]?["ankle"]
        }
    }
}

/// A single rep's feedback: its scored result plus where it sits in the clip.
struct RepFeedback: Identifiable {
    let result: RepResult
    let segment: RepSegment?

    var id: Int { result.repNumber }
    var repNumber: Int { result.repNumber }
    var faults: [String] { result.faults }
    var visuals: [FaultVisual] { result.faults.compactMap(FaultVisuals.visual(for:)) }

    static func build(reps: [RepResult], segments: [RepSegment]) -> [RepFeedback] {
        let byRep = Dictionary(uniqueKeysWithValues: segments.map { ($0.repNumber, $0) })
        return reps
            .sorted { $0.repNumber < $1.repNumber }
            .map { RepFeedback(result: $0, segment: byRep[$0.repNumber]) }
    }
}
