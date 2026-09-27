import Foundation

enum AnalysisProgress {
    static func fraction(processedFrames: Int, estimatedFrames: Int) -> Double {
        guard estimatedFrames > 0 else { return 0 }
        return min(max(Double(processedFrames) / Double(estimatedFrames), 0), 1)
    }
}
