import SwiftUI

/// Human-readable, non-diagnostic copy for report vocabulary. Keeps the raw
/// strings as the data contract while presenting plain language in the UI.
enum FormCopy {
    static func depth(_ raw: String) -> String {
        switch raw {
        case "below_parallel": return "Below parallel"
        case "parallel": return "At parallel"
        case "above_parallel": return "Above parallel"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func fault(_ raw: String) -> String {
        switch raw {
        case "insufficient_depth": return "Shallow"
        case "excessive_forward_lean": return "Forward lean"
        case "uncontrolled_descent": return "Fast descent"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func warning(_ raw: String) -> String {
        switch raw {
        case "no_person_in_most_frames":
            return "No person was detected in most frames. Re-film with your full body in frame and even lighting."
        default:
            return raw.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func phase(_ raw: String) -> String {
        switch raw {
        case "standing": return "Standing"
        case "descending": return "Descending"
        case "ascending": return "Rising"
        default: return raw.capitalized
        }
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        return String(format: "%.1fs", seconds)
    }
}

extension Color {
    static func depth(_ raw: String) -> Color {
        switch raw {
        case "below_parallel": return .green
        case "parallel": return .blue
        case "above_parallel": return .orange
        default: return .secondary
        }
    }
}

/// Small rounded label used for depth and fault classification.
struct Chip: View {
    let text: String
    var tint: Color = .secondary
    var systemImage: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.caption.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.15), in: Capsule())
    }
}

/// Summary metric card used on the session detail grid.
struct StatCard: View {
    let title: String
    let value: String
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// Section heading with consistent spacing.
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}
