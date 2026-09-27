import Foundation

struct AnnotationFrame: Codable {
    let kneeAngle: Double?
    let torsoAngle: Double?
    let phase: String
    let repCount: Int
    let faults: [String]
}

struct AnnotationSidecar: Codable {
    let frames: [AnnotationFrame]
    let fps: Double
    let frameCount: Int
}

enum AnnotationStore {
    static func save(_ sidecar: AnnotationSidecar, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(sidecar)
        try data.write(to: url)
    }

    static func load(from url: URL) throws -> AnnotationSidecar {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AnnotationSidecar.self, from: data)
    }
}
