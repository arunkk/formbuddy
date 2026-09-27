import Foundation
import SwiftData

@Model
final class RepRecord {
    var repNumber: Int
    var depth: String
    var bottomKneeAngle: Double
    var torsoAngleAtBottom: Double
    var eccentricSeconds: Double
    var concentricSeconds: Double
    var bottomPauseSeconds: Double
    var faults: [String]
    var partial: Bool
    var session: Session?

    init(repNumber: Int = 0, depth: String = "", bottomKneeAngle: Double = 0,
         torsoAngleAtBottom: Double = 0, eccentricSeconds: Double = 0,
         concentricSeconds: Double = 0, bottomPauseSeconds: Double = 0,
         faults: [String] = [], partial: Bool = false, session: Session? = nil) {
        self.repNumber = repNumber
        self.depth = depth
        self.bottomKneeAngle = bottomKneeAngle
        self.torsoAngleAtBottom = torsoAngleAtBottom
        self.eccentricSeconds = eccentricSeconds
        self.concentricSeconds = concentricSeconds
        self.bottomPauseSeconds = bottomPauseSeconds
        self.faults = faults
        self.partial = partial
        self.session = session
    }
}
