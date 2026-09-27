import Foundation
import CoreGraphics

/// Owns the on-disk layout for a saved session:
///
///     Application Support/Sessions/<uuid>/video.<ext>
///     Application Support/Sessions/<uuid>/annotations.json
///     Application Support/Sessions/<uuid>/report.json
///
/// SwiftData owns the queryable index (`Session` + `RepRecord`); this type owns
/// the bulk bytes, which SwiftData should not try to store.
enum SessionStore {
    static let annotationsFilename = "annotations.json"
    static let reportFilename = "report.json"

    // MARK: - Locations

    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func directory(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    @discardableResult
    static func prepareDirectory(for id: UUID) throws -> URL {
        let directory = directory(for: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Video

    /// Moves the freshly captured/imported clip into the session folder and
    /// returns the filename to persist on `Session.videoFilename`.
    @discardableResult
    static func adoptVideo(from source: URL, for id: UUID) throws -> String {
        let directory = try prepareDirectory(for: id)
        let fileExtension = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let filename = "video.\(fileExtension)"
        let destination = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            // Imports can live in a read-only provider container; copy instead.
            try FileManager.default.copyItem(at: source, to: destination)
        }
        return filename
    }

    static func videoURL(for id: UUID, filename: String) -> URL {
        directory(for: id).appendingPathComponent(filename)
    }

    // MARK: - Annotation sidecar

    static func annotationsURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent(annotationsFilename)
    }

    static func saveAnnotations(_ sidecar: AnnotationSidecar, for id: UUID) throws {
        try prepareDirectory(for: id)
        try AnnotationStore.save(sidecar, to: annotationsURL(for: id))
    }

    static func loadAnnotations(for id: UUID) -> AnnotationSidecar? {
        let url = annotationsURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? AnnotationStore.load(from: url)
    }

    // MARK: - Feedback artifacts

    static let feedbackCardFilename = "feedback-card.png"

    static func feedbackCardURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent(feedbackCardFilename)
    }

    static func thumbnailURL(for id: UUID, rep: Int) -> URL {
        directory(for: id).appendingPathComponent("rep-\(rep)-thumb.png")
    }

    // MARK: - Report interchange

    static func reportURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent(reportFilename)
    }

    static func writeReportJSON(_ report: SquatReport, for id: UUID) throws {
        try prepareDirectory(for: id)
        try ReportJSONEncoder.write(report, to: reportURL(for: id))
    }

    static func reportURLIfExists(for id: UUID) -> URL? {
        let url = reportURL(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Lifecycle

    static func delete(for id: UUID) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    static func totalBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

extension CGAffineTransform {
    /// Pack the six components into `Data` for `Session.orientationTransform`.
    var storedData: Data {
        var components = [a, b, c, d, tx, ty].map { Double($0) }
        return Data(bytes: &components, count: MemoryLayout<Double>.size * components.count)
    }

    init?(storedData: Data) {
        let count = 6
        guard storedData.count == MemoryLayout<Double>.size * count else { return nil }
        var components = [Double](repeating: 0, count: count)
        _ = components.withUnsafeMutableBytes { storedData.copyBytes(to: $0) }
        self.init(a: components[0], b: components[1], c: components[2],
                  d: components[3], tx: components[4], ty: components[5])
    }
}
