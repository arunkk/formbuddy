import XCTest
import CoreVideo
@testable import FormBuddy

final class FrameScalerTests: XCTestCase {

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
        return buffer
    }

    func testDownscalesLongSideToMaxDimension() throws {
        let buffer = try XCTUnwrap(makePixelBuffer(width: 1080, height: 1920))
        let scaled = try XCTUnwrap(FrameScaler.scaled(buffer, maxDimension: 512))
        XCTAssertEqual(CVPixelBufferGetHeight(scaled), 512)
        XCTAssertEqual(CVPixelBufferGetWidth(scaled), 288) // 1080 * 512 / 1920
    }

    func testScalesLandscapeFramesOnWidth() throws {
        let buffer = try XCTUnwrap(makePixelBuffer(width: 1920, height: 1080))
        let scaled = try XCTUnwrap(FrameScaler.scaled(buffer, maxDimension: 512))
        XCTAssertEqual(CVPixelBufferGetWidth(scaled), 512)
        XCTAssertEqual(CVPixelBufferGetHeight(scaled), 288)
    }

    func testReturnsNilWhenAlreadySmallEnough() throws {
        let buffer = try XCTUnwrap(makePixelBuffer(width: 320, height: 240))
        XCTAssertNil(FrameScaler.scaled(buffer, maxDimension: 512))
    }
}
