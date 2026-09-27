"""Export test fixtures from the Python squat analyzer as JSON for Swift parity tests."""
import json, math, sys
from pathlib import Path
import numpy as np

sys.path.insert(0, "/Users/arun/Hacks/github/formbuddy/tests")
sys.path.insert(0, "/Users/arun/Hacks/github/formbuddy/src")

from test_squat import make_frames
from formbuddy.analyzers.squat import SquatAnalyzer


def landmarks_to_array(lm):
    """Convert (33,3) numpy array to flat 99-float list."""
    return [float(x) for x in lm.flatten()]


def export_fixture(name, knee_angles, torso_angles=0.0, dt=0.1, zero_visibility=False):
    frames = make_frames(knee_angles, torso_angles=torso_angles, dt=dt, zero_visibility=zero_visibility)
    report = SquatAnalyzer().analyze(frames)
    fixture = {
        "name": name,
        "frames": [
            {"timestamp": f.timestamp, "landmarks": landmarks_to_array(f.landmarks) if f.landmarks is not None else None}
            for f in frames
        ],
        "expected": {
            "summary": {
                "total_reps": report.summary.total_reps,
                "partial_reps": report.summary.partial_reps,
                "reps_below_parallel": report.summary.reps_below_parallel,
                "reps_at_parallel": report.summary.reps_at_parallel,
                "reps_above_parallel": report.summary.reps_above_parallel,
                "avg_eccentric_seconds": report.summary.avg_eccentric_seconds,
                "avg_concentric_seconds": report.summary.avg_concentric_seconds,
                "avg_bottom_pause_seconds": report.summary.avg_bottom_pause_seconds,
                "avg_torso_angle_at_bottom": report.summary.avg_torso_angle_at_bottom,
                "max_torso_angle": report.summary.max_torso_angle,
            },
            "reps": [
                {
                    "rep_number": r.rep_number,
                    "depth": r.depth,
                    "bottom_knee_angle": r.bottom_knee_angle,
                    "torso_angle_at_bottom": r.torso_angle_at_bottom,
                    "eccentric_seconds": r.eccentric_seconds,
                    "concentric_seconds": r.concentric_seconds,
                    "bottom_pause_seconds": r.bottom_pause_seconds,
                    "faults": r.faults,
                    "partial": r.partial,
                }
                for r in report.reps
            ],
            "frame_annotations": [
                {
                    "knee_angle": a.knee_angle,
                    "torso_angle": a.torso_angle,
                    "phase": a.phase,
                    "rep_count": a.rep_count,
                    "faults": a.faults,
                }
                for a in report.frames
            ],
        },
    }
    return fixture


def main():
    out_dir = Path(__file__).parent.parent / "FormBuddyTests" / "Fixtures"
    out_dir.mkdir(parents=True, exist_ok=True)

    fixtures = {}

    # Two clean reps
    down = np.linspace(170, 80, 20).tolist()
    up = np.linspace(80, 170, 20).tolist()
    hold = [170.0] * 5
    fixtures["two_clean_reps"] = export_fixture("two_clean_reps", hold + down + up + hold + down + up + hold)

    # Parallel at 95
    down95 = np.linspace(170, 95, 20).tolist()
    up95 = np.linspace(95, 170, 20).tolist()
    fixtures["parallel_95"] = export_fixture("parallel_95", hold + down95 + up95 + hold)

    # Above parallel at 110
    down110 = np.linspace(170, 110, 20).tolist()
    up110 = np.linspace(110, 170, 20).tolist()
    fixtures["above_parallel_110"] = export_fixture("above_parallel_110", hold + down110 + up110 + hold)

    # Excessive lean
    t_hold = [0.0] * 5
    t_down = [0.0] + list(np.linspace(0, 50, 19))
    t_up = list(np.linspace(50, 0, 20))
    torso = t_hold + t_down + t_up + t_hold
    fixtures["excessive_lean"] = export_fixture("excessive_lean", hold + down + up + hold, torso_angles=torso)

    # Uncontrolled descent
    down_fast = np.linspace(170, 80, 5).tolist()
    fixtures["uncontrolled_descent"] = export_fixture("uncontrolled_descent", hold + down_fast + up + hold)

    # Partial rep
    up_partial = np.linspace(80, 120, 10).tolist()
    fixtures["partial_rep"] = export_fixture("partial_rep", hold + down + up_partial)

    # Zero visibility
    fixtures["zero_visibility"] = export_fixture("zero_visibility", [170.0] * 30, zero_visibility=True)

    # Torso summary
    torso2 = [0.0]*5 + [10.0]*40 + [0.0]*5 + [20.0]*40 + [0.0]*5
    fixtures["torso_summary"] = export_fixture("torso_summary", hold + down + up + hold + down + up + hold, torso_angles=torso2)

    for name, fixture in fixtures.items():
        path = out_dir / f"{name}.json"
        path.write_text(json.dumps(fixture, indent=2) + "\n")
        print(f"Exported {name} ({len(fixture['frames'])} frames)")


if __name__ == "__main__":
    main()
