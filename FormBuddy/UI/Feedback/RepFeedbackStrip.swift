import SwiftUI

/// Horizontal rep selector. Each item shows a still of the rep's bottom
/// position, its depth colour, and a fault badge. Tapping scopes the hero
/// player to that rep; "Full set" clears the scope.
struct RepFeedbackStrip: View {
    let feedback: [RepFeedback]
    let thumbnails: [Int: UIImage]
    @Binding var selectedRep: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                fullSetChip
                ForEach(feedback) { item in
                    repChip(item)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private var fullSetChip: some View {
        Button {
            selectedRep = nil
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                    Image(systemName: "rectangle.stack")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 66, height: 88)
                Text("Full set")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play the full set")
        .accessibilityAddTraits(selectedRep == nil ? [.isSelected, .isButton] : .isButton)
    }

    private func repChip(_ item: RepFeedback) -> some View {
        let isSelected = selectedRep == item.repNumber
        return Button {
            selectedRep = isSelected ? nil : item.repNumber
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.depth(item.result.depth).opacity(0.18))
                    if let image = thumbnails[item.repNumber] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title3)
                            .foregroundStyle(Color.depth(item.result.depth))
                    }
                }
                .frame(width: 66, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                }

                HStack(spacing: 4) {
                    Text("Rep \(item.repNumber)")
                        .font(.caption2.weight(.semibold))
                    if !item.faults.isEmpty {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                    }
                }
                .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func accessibilityLabel(for item: RepFeedback) -> String {
        var parts = ["Rep \(item.repNumber)", FormCopy.depth(item.result.depth)]
        if item.faults.isEmpty {
            parts.append("no form notes")
        } else {
            parts.append(item.faults.map(FormCopy.fault).joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }
}
