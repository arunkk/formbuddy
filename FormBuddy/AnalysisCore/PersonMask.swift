import Foundation
import CoreVideo

/// Binary silhouette of the best person in one frame.
///
/// Ports ``src/formbuddy/segment.py``: MediaPipe Pose can lock onto gym
/// equipment (rack uprights, plates, benches) when the lifter shares the frame
/// with it, so the pose landmarker is only ever shown person pixels and pose
/// results are validated against the silhouette.
struct PersonMask: Equatable {
    let width: Int
    let height: Int
    /// 1 on person pixels, 0 elsewhere, row-major.
    private(set) var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height,
                     "mask pixels must be width * height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Fraction of frame pixels belonging to the person.
    var coverage: Double {
        guard !pixels.isEmpty else { return 0 }
        let count = pixels.reduce(0) { $0 + ($1 == 1 ? 1 : 0) }
        return Double(count) / Double(pixels.count)
    }

    @inline(__always)
    func isPerson(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return pixels[y * width + x] == 1
    }
}

/// Pure implementations of the segmentation gate. Kept free of MediaPipe so it
/// is unit-testable; the model wrapper lives in `PersonSegmenter`.
enum PersonMaskBuilder {
    /// Per-pixel probability cut-off for person vs. background.
    static let personConfidence: Float = 0.5
    /// A connected component smaller than this fraction of the frame is noise.
    static let minPersonCoverage = 0.002
    /// Components at least this large relative to the biggest one are merged
    /// into the best person when their bounding box touches the main body.
    static let attachedAreaRatio = 0.05
    static let attachedMargin = 0.15
    /// Neutral mid-grey used to suppress background pixels (BGRA all channels).
    static let backgroundFill: UInt8 = 114
    /// Pose results with fewer than this fraction of visible landmarks inside
    /// the (dilated) mask are treated as environment lock-on and dropped.
    static let minLandmarkInsideFraction = 0.5
    /// Dilation of the mask, as a fraction of the short frame side, used when
    /// validating pose landmarks against the silhouette.
    static let maskDilateFraction = 0.008

    /// Reduce a person-probability map to the best person's binary mask.
    ///
    /// Thresholds, closes small holes, then keeps the largest connected
    /// component plus any sizeable component whose bounding box touches it (a
    /// detached limb of the same person). Distant components — other people or
    /// equipment — are dropped. Returns `nil` when nothing reaches
    /// `minCoverage`.
    static func bestPersonMask(
        probability: [Float],
        width: Int,
        height: Int,
        threshold: Float = personConfidence,
        minCoverage: Double = minPersonCoverage
    ) -> PersonMask? {
        guard width > 0, height > 0, probability.count == width * height else { return nil }

        var binary = [UInt8](repeating: 0, count: width * height)
        for index in 0..<binary.count where probability[index] >= threshold {
            binary[index] = 1
        }

        let kernel = kernelSize(width: width, height: height)
        if kernel > 1 {
            binary = morphologicalClose(binary, width: width, height: height, kernel: kernel)
        }

        let (labels, stats) = connectedComponents(binary, width: width, height: height)
        guard !stats.isEmpty else { return nil }

        let minArea = max(1.0, minCoverage * Double(width * height))
        let candidates = stats.indices.filter { Double(stats[$0].area) >= minArea }
        guard let seed = candidates.max(by: { stats[$0].area < stats[$1].area }) else { return nil }

        let seedStat = stats[seed]
        var keep: Set<Int> = [seed]
        let marginX = attachedMargin * Double(seedStat.width)
        let marginY = attachedMargin * Double(seedStat.height)
        for index in candidates where index != seed {
            let stat = stats[index]
            guard Double(stat.area) >= attachedAreaRatio * Double(seedStat.area) else { continue }
            let touches = Double(stat.x) <= Double(seedStat.x + seedStat.width) + marginX
                && Double(stat.x + stat.width) >= Double(seedStat.x) - marginX
                && Double(stat.y) <= Double(seedStat.y + seedStat.height) + marginY
                && Double(stat.y + stat.height) >= Double(seedStat.y) - marginY
            if touches { keep.insert(index) }
        }

        var pixels = [UInt8](repeating: 0, count: width * height)
        for index in 0..<pixels.count where keep.contains(Int(labels[index])) {
            pixels[index] = 1
        }
        return PersonMask(width: width, height: height, pixels: pixels)
    }

    /// Fraction of visible landmarks that fall on the person, with tolerance.
    ///
    /// Landmarks are flat `(x, y, visibility)` triples; only visible points
    /// (visibility >= 0.5) are checked. A landmark just outside the silhouette
    /// still counts when any mask pixel lies within a tolerance band (~0.8% of
    /// the short frame side). Returns 1.0 when nothing is visible.
    static func landmarkInsideFraction(_ mask: PersonMask, landmarks: [Double]) -> Double {
        let count = min(landmarks.count / 3, 33)
        let radius = max(3, Int(maskDilateFraction * Double(min(mask.width, mask.height))))
        var visible = 0
        var inside = 0

        for index in 0..<count {
            guard landmarks[index * 3 + 2] >= 0.5 else { continue }
            visible += 1
            let x = min(max(Int(landmarks[index * 3] * Double(mask.width)), 0), mask.width - 1)
            let y = min(max(Int(landmarks[index * 3 + 1] * Double(mask.height)), 0), mask.height - 1)
            if mask.isPerson(x: x, y: y) {
                inside += 1
                continue
            }
            // Only the few off-silhouette landmarks pay for a window lookup.
            var found = false
            let y0 = max(0, y - radius), y1 = min(mask.height - 1, y + radius)
            let x0 = max(0, x - radius), x1 = min(mask.width - 1, x + radius)
            if y0 <= y1 && x0 <= x1 {
                outer: for wy in y0...y1 {
                    for wx in x0...x1 where mask.isPerson(x: wx, y: wy) {
                        found = true
                        break outer
                    }
                }
            }
            if found { inside += 1 }
        }

        return visible == 0 ? 1.0 : Double(inside) / Double(visible)
    }

    /// Overwrite every non-person pixel of a BGRA pixel buffer with `fill`.
    ///
    /// The mask is resampled nearest-neighbour, so a mask at a different
    /// resolution than the frame still lines up.
    static func suppressBackground(
        pixelBuffer: CVPixelBuffer,
        mask: PersonMask,
        fill: UInt8 = backgroundFill
    ) {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pointer = base.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            let maskY = min(mask.height - 1, y * mask.height / height)
            let row = pointer + y * bytesPerRow
            for x in 0..<width {
                let maskX = min(mask.width - 1, x * mask.width / width)
                guard !mask.isPerson(x: maskX, y: maskY) else { continue }
                let pixel = row + x * 4
                pixel[0] = fill
                pixel[1] = fill
                pixel[2] = fill
                pixel[3] = 255
            }
        }
    }

    // MARK: - Morphology

    /// Odd morphological kernel side, ~0.5% of the short frame side.
    private static func kernelSize(width: Int, height: Int) -> Int {
        let size = Int(0.005 * Double(min(width, height)))
        return size | 1
    }

    /// Binary close (dilate then erode) with an elliptical structuring element,
    /// matching OpenCV's `MORPH_CLOSE` + `MORPH_ELLIPSE`.
    private static func morphologicalClose(_ binary: [UInt8], width: Int, height: Int, kernel: Int) -> [UInt8] {
        let dilated = morphology(binary, width: width, height: height, kernel: kernel, dilate: true)
        return morphology(dilated, width: width, height: height, kernel: kernel, dilate: false)
    }

    private static func morphology(_ source: [UInt8], width: Int, height: Int, kernel: Int, dilate: Bool) -> [UInt8] {
        let radius = (kernel - 1) / 2
        let offsets = ellipseOffsets(radius: radius)
        var result = [UInt8](repeating: dilate ? 0 : 1, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                var hit = !dilate
                for (dx, dy) in offsets {
                    // Replicate the border, as OpenCV's default morphology border does.
                    let nx = min(max(x + dx, 0), width - 1)
                    let ny = min(max(y + dy, 0), height - 1)
                    let value = source[ny * width + nx]
                    if dilate {
                        if value == 1 { hit = true; break }
                    } else if value == 0 {
                        hit = false
                        break
                    }
                }
                result[y * width + x] = hit ? 1 : 0
            }
        }
        return result
    }

    private static func ellipseOffsets(radius: Int) -> [(Int, Int)] {
        guard radius > 0 else { return [(0, 0)] }
        var offsets: [(Int, Int)] = []
        for dy in -radius...radius {
            for dx in -radius...radius where dx * dx + dy * dy <= radius * radius {
                offsets.append((dx, dy))
            }
        }
        return offsets
    }

    // MARK: - Connected components

    private struct ComponentStat {
        var x = Int.max
        var y = Int.max
        var maxX = -1
        var maxY = -1
        var area = 0
        var width: Int { maxX - x + 1 }
        var height: Int { maxY - y + 1 }
    }

    /// 8-connected components with area and bounding box, mirroring
    /// `cv2.connectedComponentsWithStats`.
    private static func connectedComponents(
        _ binary: [UInt8],
        width: Int,
        height: Int
    ) -> ([Int32], [ComponentStat]) {
        var labels = [Int32](repeating: -1, count: width * height)
        var stats: [ComponentStat] = []
        var stack: [Int] = []
        stack.reserveCapacity(width * height / 8)

        for start in 0..<binary.count {
            guard binary[start] == 1, labels[start] < 0 else { continue }
            let label = Int32(stats.count)
            var stat = ComponentStat()
            labels[start] = label
            stack.removeAll(keepingCapacity: true)
            stack.append(start)

            while let index = stack.popLast() {
                let x = index % width
                let y = index / width
                stat.area += 1
                if x < stat.x { stat.x = x }
                if x > stat.maxX { stat.maxX = x }
                if y < stat.y { stat.y = y }
                if y > stat.maxY { stat.maxY = y }

                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0, ny < height else { continue }
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nx = x + dx
                        guard nx >= 0, nx < width else { continue }
                        let neighbour = ny * width + nx
                        if binary[neighbour] == 1 && labels[neighbour] < 0 {
                            labels[neighbour] = label
                            stack.append(neighbour)
                        }
                    }
                }
            }
            stats.append(stat)
        }

        return (labels, stats)
    }
}
