import Foundation
import AVFoundation
import CoreVideo

final class VideoFrameReader {
    private let asset: AVURLAsset
    private let track: AVAssetTrack

    init(url: URL) throws {
        self.asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoFrameReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        self.track = track
    }

    func frames() -> AsyncThrowingStream<(CVPixelBuffer, Double), Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let reader = try AVAssetReader(asset: asset)
                    let outputSettings: [String: Any] = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                    let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
                    reader.add(trackOutput)
                    reader.startReading()

                    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
                        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            let timestamp = CMTimeGetSeconds(pts)
                            continuation.yield((pixelBuffer, timestamp))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    var fps: Double {
        track.nominalFrameRate > 0 ? Double(track.nominalFrameRate) : 30.0
    }

    var preferredTransform: CGAffineTransform {
        track.preferredTransform
    }
}
