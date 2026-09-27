import SwiftUI

/// Per-rep feedback card: the scores plus plain-language notes for each fault,
/// with a short coaching cue. Shown for the rep currently selected in the strip.
struct RepFeedbackCard: View {
    let item: RepFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            faultsSection
            metrics
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Rep \(item.repNumber)")
                .font(.headline)
            Chip(text: FormCopy.depth(item.result.depth), tint: .depth(item.result.depth))
            if item.result.partial {
                Chip(text: "Partial", tint: .orange, systemImage: "circle.dashed")
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var faultsSection: some View {
        if item.visuals.isEmpty {
            Label("No form notes for this rep — nice work.", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
                .accessibilityLabel("Rep \(item.repNumber), no form notes")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(item.visuals, id: \.fault) { visual in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: visual.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(visual.title)
                                .font(.subheadline.weight(.semibold))
                            Text(visual.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 16) {
            metric("Knee at bottom", "\(Int(item.result.bottomKneeAngle.rounded()))°")
            metric("Descent", FormCopy.duration(item.result.eccentricSeconds))
            metric("Ascent", FormCopy.duration(item.result.concentricSeconds))
            metric("Torso lean", "\(Int(item.result.torsoAngleAtBottom.rounded()))°")
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }
}
