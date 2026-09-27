import XCTest
@testable import FormBuddy

final class VideoImportServiceTests: XCTestCase {
    func testCopiesNonEmptyVideoIntoDestinationDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source.mov")
        let destinationDirectory = root.appendingPathComponent("imports")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x66, 0x6d, 0x70, 0x34]).write(to: source)

        let imported = try VideoImportService.copyVideo(from: source, to: destinationDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.path))
        XCTAssertEqual(try Data(contentsOf: imported), Data([0x66, 0x6d, 0x70, 0x34]))
        XCTAssertEqual(imported.pathExtension, "mov")
    }

    func testRejectsMissingSourceWithoutReturningDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try VideoImportService.copyVideo(
            from: root.appendingPathComponent("missing.mov"),
            to: root.appendingPathComponent("imports")
        ))
    }

    func testRejectsEmptySource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("empty.mov")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: source)

        XCTAssertThrowsError(try VideoImportService.copyVideo(
            from: source,
            to: root.appendingPathComponent("imports")
        ))
    }
}
