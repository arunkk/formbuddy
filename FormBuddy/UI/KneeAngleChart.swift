import SwiftUI
import Charts

/// Knee-angle trace with the parallel threshold and rep boundaries marked.
struct KneeAngleChart: View {
    let frames: [FrameAnnotation]
    var fps: Double = 30

    private struct Point: Identifiable {
        let id: Int
        let time: Double
        let angle: Double
    }

    private struct RepBoundary: Identifiable {
        let id: Int
        let rep: Int
        let time: Double
    }

    private var points: [Point] {
        let safeFPS = fps > 0 ? fps : 30
        return frames.enumerated().compactMap { index, frame in
            guard let angle = frame.kneeAngle else { return nil }
            return Point(id: index, time: Double(index) / safeFPS, angle: angle)
        }
    }

    private var repBoundaries: [RepBoundary] {
        let safeFPS = fps > 0 ? fps : 30
        var boundaries: [RepBoundary] = []
        var previous = 0
        for (index, frame) in frames.enumerated() where frame.repCount > previous {
            previous = frame.repCount
            boundaries.append(RepBoundary(id: index, rep: frame.repCount, time: Double(index) / safeFPS))
        }
        return boundaries
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("Parallel", SquatAnalyzer.depthParallel))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary)
                .annotation(position: .top, alignment: .leading, spacing: 2) {
                    Text("Parallel \(Int(SquatAnalyzer.depthParallel))°")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Knee angle", point.angle)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.accentColor)
            }

            ForEach(repBoundaries) { boundary in
                RuleMark(x: .value("Rep", boundary.time))
                    .foregroundStyle(.orange.opacity(0.35))
                    .annotation(position: .top, spacing: 2) {
                        Text("Rep \(boundary.rep)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
            }
        }
        .chartYScale(domain: 30...190)
        .chartYAxis {
            AxisMarks(values: [45, 90, 135, 180]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let angle = value.as(Int.self) {
                        Text("\(angle)°")
                    }
                }
            }
        }
        .chartXAxisLabel("Time (seconds)")
        .frame(height: 220)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Knee angle over time")
        .accessibilityValue(chartAccessibilityValue)
    }

    private var chartAccessibilityValue: String {
        guard let minimum = points.map(\.angle).min() else { return "No data" }
        let reps = repBoundaries.count
        return "Minimum knee angle \(Int(minimum)) degrees across \(reps) rep\(reps == 1 ? "" : "s")"
    }
}
