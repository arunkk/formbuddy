import SwiftUI

struct GuidanceView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    GuidanceRow(
                        icon: "figure.strengthtraining.traditional",
                        tint: .blue,
                        title: "Film from the side",
                        detail: "Keep the camera perpendicular to your direction of travel, about hip height."
                    )
                    GuidanceRow(
                        icon: "person.crop.rectangle",
                        tint: .green,
                        title: "Whole body in frame",
                        detail: "Head to toe with margin, and keep your feet visible through the whole rep."
                    )
                    GuidanceRow(
                        icon: "sun.max",
                        tint: .yellow,
                        title: "Bright, even light",
                        detail: "Diffuse light works best. Avoid backlighting and harsh shadows."
                    )
                    GuidanceRow(
                        icon: "speedometer",
                        tint: .orange,
                        title: "30 fps or faster",
                        detail: "Rep timing is measured from frame timestamps, so frame rate sets the resolution."
                    )
                } header: {
                    Text("How to film a set")
                } footer: {
                    Text("FormBuddy reads depth, tempo, and forward lean from the side plane.")
                }

                Section {
                    GuidanceRow(
                        icon: "arrow.left.and.right",
                        tint: .purple,
                        title: "Knee tracking",
                        detail: "Knees caving in or out can't be seen from a single side view."
                    )
                    GuidanceRow(
                        icon: "figure.stand",
                        tint: .purple,
                        title: "Left / right differences",
                        detail: "Asymmetry needs a front or rear angle to compare sides."
                    )
                    GuidanceRow(
                        icon: "shoe",
                        tint: .purple,
                        title: "Heel lift",
                        detail: "Film from the side and front if you want to check your heels."
                    )
                } header: {
                    Text("What a side view can't see")
                } footer: {
                    Text("Film extra angles and analyze them separately to cover these cues.")
                }

                Section {
                    Text("FormBuddy gives descriptive feedback about your movement. It isn't medical advice and doesn't diagnose or treat injuries.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About the feedback")
                }
            }
            .navigationTitle("Guidance")
        }
    }
}

private struct GuidanceRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
