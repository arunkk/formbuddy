import Foundation

protocol ExerciseAnalyzer {
    func process(_ frame: PoseFrame) -> FrameAnnotation
    func finish() -> SquatReport
}
