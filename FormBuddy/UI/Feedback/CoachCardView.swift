import SwiftUI

/// Header content for a generated coach's card.
struct CoachCardHeader {
    let exercise: String
    let date: Date?
    let totalReps: Int
    let belowParallel: Int
    let faultedReps: Int
}

/// One still on the coach's card.
struct CoachCardStill: Identifiable {
    let rep: RepResult
    let frame: AnnotationFrame
    let image: UIImage
    var id: Int { rep.repNumber }
}

/// The composite "coach's card": a summary header followed by one annotated
/// still per rep, laid out in a grid so a 20-rep set stays a sensible image.
/// Rendered once to a shareable picture.
struct CoachCardView: View {
    let header: CoachCardHeader
    let stills: [CoachCardStill]
    let mapper: OrientationMapper
    let width: CGFloat

    /// More reps, more columns, so the card never becomes a mile-long strip.
    private var columns: Int {
        switch stills.count {
        case 0...4: return 1
        case 5...10: return 2
        default: return 3
        }
    }

    private var rows: [[CoachCardStill]] {
        stride(from: 0, to: stills.count, by: columns).map { start in
            Array(stills[start..<min(start + columns, stills.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerView
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(row) { still in
                            RepStillView(image: still.image, frame: still.frame, rep: still.rep, mapper: mapper)
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                        if row.count < columns {
                            ForEach(0..<(columns - row.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            footer
        }
        .padding(24)
        .frame(width: width, alignment: .leading)
        .background(Color(.systemBackground))
        .environment(\.colorScheme, .light)
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image("BrandMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                Text("Form card")
                    .font(.largeTitle.weight(.bold))
            }
            HStack(spacing: 8) {
                Text(header.exercise.capitalized)
                    .font(.subheadline.weight(.semibold))
                if let date = header.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Chip(text: "\(header.totalReps) reps", tint: .accentColor, systemImage: "number")
                Chip(text: "\(header.belowParallel) below parallel", tint: .green, systemImage: "arrow.down.to.line")
                if header.faultedReps > 0 {
                    Chip(text: "\(header.faultedReps) with notes", tint: .red, systemImage: "exclamationmark.triangle.fill")
                }
            }
            .padding(.top, 2)
        }
    }

    private var footer: some View {
        Text("Pose analysis on device. Descriptive feedback only — not medical advice.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}
