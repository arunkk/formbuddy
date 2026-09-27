import Foundation
import AVFoundation
import CoreVideo
import OSLog

private actor FrameDemandGate {
    private var credits = 0
    private var waiter: CheckedContinuation<Void, Never>?
    private var cancelled = false

    func waitForAcknowledgement() async {
        if cancelled { return }
        if credits > 0 {
            credits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    func acknowledge() {
        if let waiter {
            self.waiter = nil
            waiter.resume()
        } else {
            credits += 1
        }
    }

    func cancel() {
        cancelled = true
        waiter?.resume()
        waiter = nil
    }
}

final class VideoFrameReader {
    private static let logger = Logger(subsystem: "com.formbuddy.app", category: "video-decode")
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let nominalFrameRate: Double
    private let duration: CMTime
    private let transform: CGAffineTransform
    private let demand = FrameDemandGate()

    init(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoFrameReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        self.asset = asset
        self.track = track
        self.nominalFrameRate = Double((try? await track.load(.nominalFrameRate)) ?? 0)
        self.duration = (try? await track.load(.timeRange).duration) ?? .zero
        self.transform = (try? await track.load(.preferredTransform)) ?? .identity
    }

    /// Yields at most one decoded pixel buffer at a time. The consumer must
    /// acknowledge each yielded frame after inference so decode stays bounded.
    func frames() -> AsyncThrowingStream<(CVPixelBuffer, Double), Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(1)) { continuation in
            let producer = Task {
                let reader: AVAssetReader
                do {
                    reader = try AVAssetReader(asset: asset)
                    let outputSettings: [String: Any] = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                    let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
                    trackOutput.alwaysCopiesSampleData = false
                    guard reader.canAdd(trackOutput) else {
                        throw NSError(domain: "VideoFrameReader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot attach video track output"])
                    }
                    reader.add(trackOutput)
                    guard reader.startReading() else {
                        throw reader.error ?? NSError(domain: "VideoFrameReader", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to start video decoding"])
                    }
                    Self.logger.info("Started sequential video decode")

                    while !Task.isCancelled {
                        guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }
                        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
                        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                        guard timestamp.isFinite else {
                            throw NSError(domain: "VideoFrameReader", code: 4, userInfo: [NSLocalizedDescriptionKey: "Video frame has an invalid presentation timestamp"])
                        }

                        switch continuation.yield((pixelBuffer, timestamp)) {
                        case .enqueued:
                            await demand.waitForAcknowledgement()
                        case .dropped:
                            // This should not occur with the one-frame handshake;
                            // fail rather than silently perturb analysis timing.
                            throw NSError(domain: "VideoFrameReader", code: 5, userInfo: [NSLocalizedDescriptionKey: "Video frame buffer overflowed"])
                        case .terminated:
                            reader.cancelReading()
                            return
                        @unknown default:
                            reader.cancelReading()
                            return
                        }
                    }

                    if Task.isCancelled {
                        reader.cancelReading()
                        continuation.finish()
                    } else if reader.status == .failed {
                        let error = reader.error ?? NSError(domain: "VideoFrameReader", code: 6, userInfo: [NSLocalizedDescriptionKey: "Video decoding failed"])
                        Self.logger.error("Video decode failed: \(error.localizedDescription, privacy: .public)")
                        continuation.finish(throwing: error)
                    } else if reader.status == .completed {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: NSError(domain: "VideoFrameReader", code: 7, userInfo: [NSLocalizedDescriptionKey: "Video decoding stopped unexpectedly (status: \(reader.status.rawValue))"]))
                    }
                } catch {
                    Self.logger.error("Video reader stage failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                producer.cancel()
                Task { await self.demand.cancel() }
            }
        }
    }

    func acknowledgeFrame() async {
        await demand.acknowledge()
    }

    var fps: Double {
        nominalFrameRate > 0 ? Double(nominalFrameRate) : 30.0
    }

    var estimatedFrameCount: Int {
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return max(Int((seconds * fps).rounded()), 1)
    }

    var preferredTransform: CGAffineTransform {
        transform
    }
}
