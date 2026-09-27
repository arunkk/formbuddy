import XCTest
import AVFoundation
import CoreVideo
import Darwin
@testable import FormBuddy

private final class AssetWriterReference: @unchecked Sendable {
    let writer: AVAssetWriter
    init(_ writer: AVAssetWriter) { self.writer = writer }
}

final class VideoFrameReaderTests: XCTestCase {
    func testRejectsFileWithoutVideoTrack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("not-a-movie.mov")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a movie".utf8).write(to: url)

        XCTAssertThrowsError(try VideoFrameReader(url: url))
    }

    func testReadsEveryFrameWhenConsumerAcknowledgesSequentially() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("short-test.mov")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await makeTestMovie(at: url, frameCount: 3)

        let reader = try VideoFrameReader(url: url)
        var framesRead = 0
        for try await (pixelBuffer, _) in reader.frames() {
            XCTAssertEqual(CVPixelBufferGetWidth(pixelBuffer), 64)
            XCTAssertEqual(CVPixelBufferGetHeight(pixelBuffer), 64)
            framesRead += 1
            await reader.acknowledgeFrame()
        }

        XCTAssertEqual(framesRead, 3)
    }

    private func makeTestMovie(at url: URL, frameCount: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64,
        ])
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw NSError(domain: "VideoFrameReaderTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "No pixel buffer pool"])
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard let pixelBuffer else {
                throw NSError(domain: "VideoFrameReaderTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate pixel buffer"])
            }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(baseAddress, 0, CVPixelBufferGetDataSize(pixelBuffer))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }

        input.markAsFinished()
        let writerReference = AssetWriterReference(writer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting { [writerReference] in
                if writerReference.writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: writerReference.writer.error ?? NSError(domain: "VideoFrameReaderTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to finish test movie"]))
                }
            }
        }
    }
}
