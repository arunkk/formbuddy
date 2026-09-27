import SwiftUI
import Charts

struct KneeAngleChart: View {
    let annotations: [FrameAnnotation]

    var body: some View {
        Chart {
            ForEach(Array(annotations.enumerated()), id: \.offset) { index, ann in
                if let angle = ann.kneeAngle {
                    LineMark(
                        x: .value("Frame", index),
                        y: .value("Knee Angle", angle)
                    )
                }
            }
        }
        .chartYScale(domain: 60...180)
        .frame(height: 200)
    }
}
