import SwiftUI

/// One rep rendered as an annotated still: the extracted frame with the pose
/// skeleton and fault highlights drawn over it, plus an optional caption. Used
/// both for the strip thumbnails and the full coach's card, so they always look
/// the same.
struct RepStillView: View {
    let image: UIImage
    let frame: AnnotationFrame
    let rep: RepResult
    let mapper: OrientationMapper
    var showsCaption: Bool = true

    private var aspect: CGFloat {
        let size = mapper.displayedSize
        guard size.width > 0, size.height > 0 else { return 9.0 / 16.0 }
        return size.width / size.height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                FormHighlightsOverlay(frame: frame, rep: rep, mapper: mapper, showHighlights: true)
            }
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if showsCaption {
                caption
            }
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Rep \(rep.repNumber)")
                    .font(.subheadline.weight(.semibold))
                Chip(text: FormCopy.depth(rep.depth), tint: .depth(rep.depth))
                if rep.partial {
                    Chip(text: "Partial", tint: .orange, systemImage: "circle.dashed")
                }
                Spacer(minLength: 0)
            }

            if rep.faults.isEmpty {
                Label("No form notes", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(rep.faults, id: \.self) { fault in
                        if let visual = FaultVisuals.visual(for: fault) {
                            Label(visual.title, systemImage: visual.symbol)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }
}
