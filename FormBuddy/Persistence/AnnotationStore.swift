import Foundation

struct AnnotationFrame: Codable, Sendable {
    let kneeAngle: Double?
    let torsoAngle: Double?
    let phase: String
    let repCount: Int
    let faults: [String]
    /// Flat 33 × (x, y, visibility) landmark array in the video's *buffer*
    /// orientation. Optional so older sidecars decode without it.
    var landmarks: [Double]? = nil

    var frameAnnotation: FrameAnnotation {
        FrameAnnotation(
            kneeAngle: kneeAngle,
            torsoAngle: torsoAngle,
            phase: phase,
            repCount: repCount,
            faults: faults
        )
    }
}

struct AnnotationSidecar: Codable, Sendable {
    let frames: [AnnotationFrame]
    let fps: Double
    let frameCount: Int

    var frameAnnotations: [FrameAnnotation] {
        frames.map(\.frameAnnotation)
    }
}

enum AnnotationStore {
    static func save(_ sidecar: AnnotationSidecar, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(sidecar)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) throws -> AnnotationSidecar {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AnnotationSidecar.self, from: data)
    }
}
