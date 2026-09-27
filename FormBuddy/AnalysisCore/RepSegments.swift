import Foundation

/// One rep's frame range inside a clip, derived purely from the annotation
/// sidecar so it also works on sessions that were saved before this feature
/// existed (no re-analysis, no schema change).
///
/// The analyzer increments `repCount` the moment the lifter leaves standing and
/// keeps it for the whole rep, so a rep spans every frame whose `repCount`
/// equals its number. The rep ends when the lifter is standing again, or at the
/// last frame for a partial rep.
struct RepSegment: Identifiable, Equatable, Sendable {
    let repNumber: Int
    /// First frame of the rep (descent begins).
    let startFrame: Int
    /// Return-to-standing frame, or the last frame of a partial rep.
    let endFrame: Int
    /// Frame with the smallest knee angle (the bottom of the rep).
    let bottomFrame: Int
    /// A representative frame for each fault, used to anchor stills and
    /// highlights (e.g. `insufficient_depth -> bottomFrame`).
    let faultFrames: [String: Int]

    var id: Int { repNumber }

    /// Length of the rep in frames, inclusive of both ends.
    var frameCount: Int { max(endFrame - startFrame + 1, 0) }

    func time(ofFrame frame: Int, fps: Double) -> Double {
        let safeFPS = fps > 0 ? fps : 30
        return Double(frame) / safeFPS
    }

    func startTime(fps: Double) -> Double { time(ofFrame: startFrame, fps: fps) }
    func endTime(fps: Double) -> Double { time(ofFrame: endFrame, fps: fps) }
    func bottomTime(fps: Double) -> Double { time(ofFrame: bottomFrame, fps: fps) }
    func faultTime(_ fault: String, fps: Double) -> Double {
        time(ofFrame: faultFrames[fault] ?? bottomFrame, fps: fps)
    }
}

enum RepSegments {
    /// Builds one segment per detected rep, ordered by rep number.
    static func derive(from sidecar: AnnotationSidecar) -> [RepSegment] {
        let frames = sidecar.frames
        guard !frames.isEmpty else { return [] }

        var spans: [Int: [Int]] = [:]
        for (index, frame) in frames.enumerated() where frame.repCount > 0 {
            spans[frame.repCount, default: []].append(index)
        }

        return spans.keys.sorted().compactMap { repNumber in
            guard let indices = spans[repNumber], let first = indices.first, let last = indices.last else {
                return nil
            }
            // The frame the lifter is back on their feet ends the rep; a partial
            // rep never reaches standing, so it runs to the last frame.
            let endFrame = frames[first...last].firstIndex(where: { $0.phase == "standing" }) ?? last

            let bottomFrame = argMinKnee(in: indices, frames: frames) ?? endFrame
            let leanFrame = argMaxTorso(in: indices, frames: frames) ?? bottomFrame
            // Represent the descent with a frame partway down rather than the
            // bottom, so a fast-descent still shows the movement.
            let descentFrame = first + max((bottomFrame - first) / 2, 0)

            let faultFrames: [String: Int] = [
                "insufficient_depth": bottomFrame,
                "excessive_forward_lean": leanFrame,
                "uncontrolled_descent": descentFrame,
            ]

            return RepSegment(
                repNumber: repNumber,
                startFrame: first,
                endFrame: endFrame,
                bottomFrame: bottomFrame,
                faultFrames: faultFrames
            )
        }
    }

    private static func argMinKnee(in indices: [Int], frames: [AnnotationFrame]) -> Int? {
        var best: Int?
        var bestAngle = Double.greatestFiniteMagnitude
        for index in indices {
            guard let angle = frames[index].kneeAngle, angle < bestAngle else { continue }
            bestAngle = angle
            best = index
        }
        return best
    }

    private static func argMaxTorso(in indices: [Int], frames: [AnnotationFrame]) -> Int? {
        var best: Int?
        var bestAngle = -Double.greatestFiniteMagnitude
        for index in indices {
            guard let angle = frames[index].torsoAngle, angle > bestAngle else { continue }
            bestAngle = angle
            best = index
        }
        return best
    }
}
