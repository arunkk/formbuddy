import SwiftUI

/// BlazePose body connections (33-landmark topology) used to draw the skeleton.
enum PoseSkeleton {
    static let connections: [(Int, Int)] = [
        // Torso
        (11, 12), (11, 23), (12, 24), (23, 24),
        // Arms
        (11, 13), (13, 15), (12, 14), (14, 16),
        // Hands
        (15, 17), (15, 19), (15, 21), (17, 19), (16, 18), (16, 20), (16, 22), (18, 20),
        // Legs
        (23, 25), (25, 27), (27, 29), (27, 31), (29, 31),
        (24, 26), (26, 28), (28, 30), (28, 32), (30, 32),
    ]
}

/// Draws the pose skeleton and, when enabled, body-anchored fault highlights over
/// a video frame. The same view renders live playback and the still form card,
/// so annotated stills always match what the video shows.
struct FormHighlightsOverlay: View {
    let frame: AnnotationFrame
    /// The rep this frame belongs to, so rep-level faults (depth, tempo) show
    /// across the whole rep rather than only on their own frame.
    var rep: RepResult? = nil
    let mapper: OrientationMapper
    var showHighlights: Bool = true

    private var landmarks: [Double]? {
        guard let landmarks = frame.landmarks, landmarks.count == 99 else { return nil }
        return landmarks
    }

    private var activeFaults: [String] {
        var faults = Set(frame.faults)
        if let rep { faults.formUnion(rep.faults) }
        return faults.sorted()
    }

    var body: some View {
        Canvas { context, size in
            guard let landmarks else { return }
            let side = selectSide(landmarks)
            drawSkeleton(&context, size: size, landmarks: landmarks)
            guard showHighlights else { return }
            drawHighlights(&context, size: size, landmarks: landmarks, side: side)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Skeleton

    private func drawSkeleton(_ context: inout GraphicsContext, size: CGSize, landmarks: [Double]) {
        var path = Path()
        for (a, b) in PoseSkeleton.connections {
            guard landmarks[a * 3 + 2] >= 0.5, landmarks[b * 3 + 2] >= 0.5 else { continue }
            let start = mapper.mapLandmark(x: landmarks[a * 3], y: landmarks[a * 3 + 1], viewSize: size)
            let end = mapper.mapLandmark(x: landmarks[b * 3], y: landmarks[b * 3 + 1], viewSize: size)
            path.move(to: start)
            path.addLine(to: end)
        }
        context.stroke(path, with: .color(.green), style: StrokeStyle(lineWidth: 3, lineCap: .round))

        for index in 0..<33 where landmarks[index * 3 + 2] >= 0.5 {
            let point = mapper.mapLandmark(x: landmarks[index * 3], y: landmarks[index * 3 + 1], viewSize: size)
            let dot = Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            context.fill(dot, with: .color(.white))
        }
    }

    // MARK: - Highlights

    private func drawHighlights(_ context: inout GraphicsContext, size: CGSize, landmarks: [Double], side: Side) {
        if activeFaults.contains("insufficient_depth") {
            drawKneeDepth(&context, size: size, landmarks: landmarks, side: side)
        }
        if activeFaults.contains("excessive_forward_lean") {
            drawTorsoLean(&context, size: size, landmarks: landmarks, side: side)
        }
        if let primary = primaryFault {
            drawCallout(&context, at: anchorPoint(for: primary, size: size, landmarks: landmarks, side: side),
                        in: size, text: calloutLabel(for: primary), color: color(for: primary))
        }
    }

    private func drawKneeDepth(_ context: inout GraphicsContext, size: CGSize, landmarks: [Double], side: Side) {
        guard let hip = point(.hip, side: side, landmarks: landmarks, size: size),
              let knee = point(.knee, side: side, landmarks: landmarks, size: size),
              let ankle = point(.ankle, side: side, landmarks: landmarks, size: size) else { return }

        let color = depthColor(frame.kneeAngle)

        // Arc through the measured knee angle.
        let v1 = CGVector(dx: hip.x - knee.x, dy: hip.y - knee.y)
        let v2 = CGVector(dx: ankle.x - knee.x, dy: ankle.y - knee.y)
        var delta = atan2(v2.dy, v2.dx) - atan2(v1.dy, v1.dx)
        while delta <= -.pi { delta += 2 * .pi }
        while delta > .pi { delta -= 2 * .pi }
        let radius = max(14, min(hypot(v1.dx, v1.dy), hypot(v2.dx, v2.dy)) * 0.4)
        var arc = Path()
        arc.addArc(center: knee, radius: radius,
                   startAngle: .radians(atan2(v1.dy, v1.dx)),
                   endAngle: .radians(atan2(v1.dy, v1.dx) + delta),
                   clockwise: delta < 0)
        context.stroke(arc, with: .color(color), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

        // Parallel target: at parallel the thigh is horizontal, so the hip sits
        // level with the knee. Show that target line.
        var target = Path()
        target.move(to: knee)
        target.addLine(to: CGPoint(x: hip.x, y: knee.y))
        context.stroke(target, with: .color(.cyan.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        context.stroke(Path(ellipseIn: CGRect(x: hip.x - 4, y: knee.y - 4, width: 8, height: 8)),
                       with: .color(.cyan), lineWidth: 2)
    }

    private func drawTorsoLean(_ context: inout GraphicsContext, size: CGSize, landmarks: [Double], side: Side) {
        guard let hip = point(.hip, side: side, landmarks: landmarks, size: size),
              let shoulder = point(.shoulder, side: side, landmarks: landmarks, size: size) else { return }

        let angle = frame.torsoAngle ?? rep?.torsoAngleAtBottom ?? 0
        let color: Color = angle > SquatAnalyzer.excessiveLeanDegrees ? .red : .accentColor
        let length = hypot(shoulder.x - hip.x, shoulder.y - hip.y)
        let verticalTop = CGPoint(x: hip.x, y: hip.y - length)

        var wedge = Path()
        wedge.move(to: hip)
        wedge.addLine(to: shoulder)
        wedge.addLine(to: verticalTop)
        wedge.closeSubpath()
        context.fill(wedge, with: .color(color.opacity(0.22)))
        context.stroke(wedge, with: .color(color.opacity(0.7)), lineWidth: 1.5)

        var reference = Path()
        reference.move(to: hip)
        reference.addLine(to: verticalTop)
        context.stroke(reference, with: .color(.white.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    }

    // MARK: - Callout

    private var primaryFault: String? {
        let priority = ["insufficient_depth", "excessive_forward_lean", "uncontrolled_descent"]
        return priority.first { activeFaults.contains($0) }
    }

    private func anchorPoint(for fault: String, size: CGSize, landmarks: [Double], side: Side) -> CGPoint {
        let joint = FaultVisuals.visual(for: fault)?.joint ?? .knee
        if let index = FaultVisuals.landmarkIndex(for: joint, side: side),
           landmarks[index * 3 + 2] >= 0.5 {
            return mapper.mapLandmark(x: landmarks[index * 3], y: landmarks[index * 3 + 1], viewSize: size)
        }
        return CGPoint(x: size.width * 0.5, y: size.height * 0.4)
    }

    private func calloutLabel(for fault: String) -> String {
        switch fault {
        case "insufficient_depth":
            return "Not deep enough"
        case "excessive_forward_lean":
            let angle = frame.torsoAngle ?? rep?.torsoAngleAtBottom ?? 0
            return "Lean \(Int(angle.rounded()))°"
        case "uncontrolled_descent":
            return "Descent \(String(format: "%.1fs", rep?.eccentricSeconds ?? 0))"
        default:
            return fault.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func color(for fault: String) -> Color {
        switch fault {
        case "insufficient_depth": return depthColor(frame.kneeAngle)
        default: return .red
        }
    }

    private func drawCallout(_ context: inout GraphicsContext, at point: CGPoint, in size: CGSize, text: String, color: Color) {
        let resolved = context.resolve(
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        )
        // Wrap inside the surface so a callout on a narrow portrait clip (or a
        // magnified one) can't run off the edge and get clipped.
        let maxTextWidth = max(size.width - 24, 48)
        let textSize = resolved.measure(in: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude))
        let box = CGSize(width: textSize.width + 16, height: textSize.height + 10)
        var center = CGPoint(x: point.x + box.width / 2 + 14, y: point.y - box.height / 2 - 14)
        center.x = min(max(center.x, box.width / 2 + 4), max(size.width - box.width / 2 - 4, box.width / 2 + 4))
        center.y = min(max(center.y, box.height / 2 + 4), max(size.height - box.height / 2 - 4, box.height / 2 + 4))
        let rect = CGRect(x: center.x - box.width / 2, y: center.y - box.height / 2, width: box.width, height: box.height)

        var leader = Path()
        leader.move(to: point)
        leader.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        context.stroke(leader, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(color.opacity(0.92)))
        context.draw(resolved, at: center, anchor: .center)
        context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(color))
    }

    // MARK: - Helpers

    private func point(_ joint: BodyJoint, side: Side, landmarks: [Double], size: CGSize) -> CGPoint? {
        guard let index = FaultVisuals.landmarkIndex(for: joint, side: side),
              landmarks[index * 3 + 2] >= 0.5 else { return nil }
        return mapper.mapLandmark(x: landmarks[index * 3], y: landmarks[index * 3 + 1], viewSize: size)
    }

    private func depthColor(_ angle: Double?) -> Color {
        guard let angle else { return .secondary }
        if angle < SquatAnalyzer.depthParallel { return .green }
        if angle > SquatAnalyzer.depthAbove { return .orange }
        return .blue
    }
}
