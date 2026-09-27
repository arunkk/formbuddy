import Foundation

final class LandmarkSmoother {
    let alpha: Double
    private var smoothed: [Double]?

    init(alpha: Double = 0.5) { self.alpha = alpha }

    func update(_ landmarks: [Double]?) -> [Double]? {
        guard let landmarks = landmarks else { return smoothed }
        if smoothed == nil {
            smoothed = landmarks
            return smoothed
        }
        for i in 0..<33 {
            let visIdx = i*3+2
            if landmarks[visIdx] >= 0.5 {
                smoothed![i*3]   = alpha * landmarks[i*3]   + (1-alpha) * smoothed![i*3]
                smoothed![i*3+1] = alpha * landmarks[i*3+1] + (1-alpha) * smoothed![i*3+1]
                smoothed![i*3+2] = alpha * landmarks[visIdx] + (1-alpha) * smoothed![visIdx]
            }
        }
        return smoothed
    }
}
