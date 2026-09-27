import XCTest
import CoreVideo
@testable import FormBuddy

final class PersonMaskTests: XCTestCase {

    // MARK: - bestPersonMask

    func testKeepsLargestComponentAndDropsNoise() throws {
        var probability = [Float](repeating: 0, count: 100) // 10 x 10
        // 3 x 3 person block at (1, 1).
        for y in 1...3 { for x in 1...3 { probability[y * 10 + x] = 1 } }
        // A single distant speck of noise.
        probability[8 * 10 + 8] = 1

        let mask = try XCTUnwrap(
            PersonMaskBuilder.bestPersonMask(probability: probability, width: 10, height: 10)
        )
        XCTAssertEqual(mask.coverage, 9.0 / 100.0, accuracy: 1e-9)
        XCTAssertTrue(mask.isPerson(x: 2, y: 2))
        XCTAssertFalse(mask.isPerson(x: 8, y: 8))
    }

    func testMergesAttachedLimb() throws {
        var probability = [Float](repeating: 0, count: 400) // 20 x 20
        // Main body 6 x 6 at (2, 2).
        for y in 2...7 { for x in 2...7 { probability[y * 20 + x] = 1 } }
        // Detached but touching 2 x 2 "hand" at (8, 2).
        for y in 2...3 { for x in 8...9 { probability[y * 20 + x] = 1 } }

        let mask = try XCTUnwrap(
            PersonMaskBuilder.bestPersonMask(probability: probability, width: 20, height: 20)
        )
        XCTAssertEqual(mask.coverage, 40.0 / 400.0, accuracy: 1e-9)
        XCTAssertTrue(mask.isPerson(x: 8, y: 2))
    }

    func testReturnsNilWhenNothingReachesMinCoverage() {
        var probability = [Float](repeating: 0, count: 100 * 100)
        probability[0] = 1
        XCTAssertNil(PersonMaskBuilder.bestPersonMask(probability: probability, width: 100, height: 100))
    }

    func testReturnsNilForEmptyProbability() {
        XCTAssertNil(PersonMaskBuilder.bestPersonMask(probability: [], width: 0, height: 0))
    }

    // MARK: - landmarkInsideFraction

    private func fullyPersonMask(width: Int, height: Int) -> PersonMask {
        PersonMask(width: width, height: height, pixels: [UInt8](repeating: 1, count: width * height))
    }

    func testLandmarksInsideReturnOne() {
        let mask = fullyPersonMask(width: 10, height: 10)
        var landmarks = [Double](repeating: 0, count: 99)
        landmarks[0] = 0.5; landmarks[1] = 0.5; landmarks[2] = 1
        XCTAssertEqual(PersonMaskBuilder.landmarkInsideFraction(mask, landmarks: landmarks), 1.0, accuracy: 1e-9)
    }

    func testLandmarksFarOutsideReturnZero() {
        var pixels = [UInt8](repeating: 0, count: 100)
        pixels[0] = 1 // person pixel only at (0, 0)
        let mask = PersonMask(width: 10, height: 10, pixels: pixels)
        var landmarks = [Double](repeating: 0, count: 99)
        landmarks[0] = 0.9; landmarks[1] = 0.9; landmarks[2] = 1
        XCTAssertEqual(PersonMaskBuilder.landmarkInsideFraction(mask, landmarks: landmarks), 0.0, accuracy: 1e-9)
    }

    func testInvisibleLandmarksCountAsInside() {
        var pixels = [UInt8](repeating: 0, count: 100)
        pixels[0] = 1
        let mask = PersonMask(width: 10, height: 10, pixels: pixels)
        let landmarks = [Double](repeating: 0, count: 99) // visibility 0 everywhere
        XCTAssertEqual(PersonMaskBuilder.landmarkInsideFraction(mask, landmarks: landmarks), 1.0, accuracy: 1e-9)
    }

    // MARK: - suppressBackground

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
        return buffer
    }

    func testSuppressBackgroundGreysOutNonPersonPixels() throws {
        let width = 10, height = 10
        let buffer = try XCTUnwrap(makePixelBuffer(width: width, height: height), "could not create pixel buffer")

        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let pointer = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let pixel = pointer + y * bytesPerRow + x * 4
                    pixel[0] = 255; pixel[1] = 255; pixel[2] = 255; pixel[3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        // Person on the left half only.
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<(width / 2) { pixels[y * width + x] = 1 } }
        let mask = PersonMask(width: width, height: height, pixels: pixels)

        PersonMaskBuilder.suppressBackground(pixelBuffer: buffer, mask: mask)

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pointer = base.assumingMemoryBound(to: UInt8.self)

        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let p = pointer + y * bytesPerRow + x * 4
            return [p[0], p[1], p[2], p[3]]
        }

        XCTAssertEqual(pixel(0, 0), [255, 255, 255, 255]) // person kept
        XCTAssertEqual(pixel(9, 0), [114, 114, 114, 255]) // background filled
    }
}
