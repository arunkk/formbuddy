import Foundation

struct ReportJSONEncoder {
    static func encode(_ report: SquatReport) -> [String: Any] {
        var dict: [String: Any] = [
            "exercise": report.exercise,
            "video_meta": report.videoMeta,
            "warnings": report.warnings,
        ]

        dict["summary"] = [
            "total_reps": report.summary.totalReps,
            "partial_reps": report.summary.partialReps,
            "reps_below_parallel": report.summary.repsBelowParallel,
            "reps_at_parallel": report.summary.repsAtParallel,
            "reps_above_parallel": report.summary.repsAboveParallel,
            "avg_eccentric_seconds": report.summary.avgEccentricSeconds,
            "avg_concentric_seconds": report.summary.avgConcentricSeconds,
            "avg_bottom_pause_seconds": report.summary.avgBottomPauseSeconds,
            "avg_torso_angle_at_bottom": report.summary.avgTorsoAngleAtBottom,
            "max_torso_angle": report.summary.maxTorsoAngle,
        ] as [String : Any]

        dict["reps"] = report.reps.map { rep in
            [
                "rep_number": rep.repNumber,
                "depth": rep.depth,
                "bottom_knee_angle": rep.bottomKneeAngle,
                "torso_angle_at_bottom": rep.torsoAngleAtBottom,
                "eccentric_seconds": rep.eccentricSeconds,
                "concentric_seconds": rep.concentricSeconds,
                "bottom_pause_seconds": rep.bottomPauseSeconds,
                "faults": rep.faults,
                "partial": rep.partial,
            ] as [String : Any]
        }

        return dict
    }

    static func write(_ report: SquatReport, to url: URL) throws {
        let dict = encode(report)
        let data = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
        try data.write(to: url)
    }
}
