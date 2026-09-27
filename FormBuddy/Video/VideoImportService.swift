import Foundation
import CoreTransferable
import PhotosUI
import UniformTypeIdentifiers

struct ImportedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            ImportedVideo(url: try VideoImportService.copyVideo(from: received.file))
        }
    }
}

enum VideoImportError: LocalizedError {
    case sourceMissing
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            return "The selected video file is no longer available. Please select it again."
        case .emptyFile:
            return "The selected video is empty and could not be imported."
        }
    }
}

enum VideoImportService {
    @discardableResult
    static func copyVideo(
        from source: URL,
        to destinationDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw VideoImportError.sourceMissing
        }
        let sourceSize = try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber
        guard let sourceSize, sourceSize.int64Value > 0 else {
            throw VideoImportError.emptyFile
        }

        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        let fileExtension = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let destination = destinationDirectory
            .appendingPathComponent("imported_\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        do {
            try FileManager.default.copyItem(at: source, to: destination)
            let destinationSize = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
            guard let destinationSize, destinationSize.int64Value > 0 else {
                try? FileManager.default.removeItem(at: destination)
                throw VideoImportError.emptyFile
            }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
