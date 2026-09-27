# FormBuddy — Squat Form Analyzer Design

**Date:** 2026-09-26
**Status:** Approved design, ready for implementation planning

## Overview

FormBuddy is a Python CLI tool that analyzes weight training form from a recorded
video file. It estimates the lifter's pose per frame, applies biomechanical rules
for the selected exercise, and produces:

1. An **annotated video** (pose skeleton, joint angles, rep counter, fault flags)
2. A **form report** (JSON + human-readable text)

Phase 1 targets the **back squat from a side-view camera**. The architecture makes
adding further exercises (deadlift, bench press, etc.) a matter of adding one
analyzer module — no changes to the pose pipeline or CLI dispatch.

## Usage

```bash
python -m formbuddy.cli --input squat_video.mp4 --exercise squat \
    --output-dir ./out
```

Produces `out/squat_video_annotated.mp4`, `out/report.json`, `out/report.txt`.

## Architecture & Data Flow

```
video file → FrameReader (OpenCV)
           → PoseEstimator (MediaPipe, per frame → 33 landmarks + visibility)
           → LandmarkSmoother (temporal smoothing to kill jitter)
           → ExerciseAnalyzer (plugin interface; SquatAnalyzer in phase 1)
                ├── rep detection (state machine on knee/hip angle)
                ├── depth scoring at bottom of each rep
                ├── forward-lean angle per frame
                └── phase timing (eccentric/concentric duration, total tempo)
           → ReportBuilder (JSON + human-readable summary)
           → VideoWriter (annotated video: skeleton, angles, rep counter, fault flags)
           → CLI entry point (argparse)
```

## Module Breakdown

```
formbuddy/
├── pyproject.toml              # package metadata, dependencies, CLI entry point
├── src/formbuddy/
│   ├── cli.py                  # argparse: --input, --output-dir, --exercise, --no-video
│   ├── pipeline.py             # orchestrates: video → pose → smooth → analyze → outputs
│   ├── pose.py                 # PoseEstimator: MediaPipe wrapper, per-frame landmarks
│   ├── smoothing.py            # LandmarkSmoother: EMA/One-Euro filter on landmarks
│   ├── geometry.py             # angle math: joint angles, segment angles, visibility weighting
│   ├── analyzers/
│   │   ├── base.py             # ExerciseAnalyzer interface + ExerciseReport dataclass
│   │   └── squat.py            # SquatAnalyzer: reps, depth, lean, tempo
│   ├── report.py               # ReportBuilder: JSON + human-readable text summary
│   └── annotate.py             # VideoWriter: skeleton overlay, angle arcs, rep counter, fault flags
├── tests/
│   ├── test_geometry.py        # angle math on synthetic landmarks
│   ├── test_squat.py            # rep state machine + depth on synthetic trajectories
│   └── test_pipeline.py        # end-to-end on a tiny generated video (optional, marked slow)
└── README.md                   # install, usage, how to film (side view, lighting, full body)
```

### Responsibilities & Dependencies

- `geometry.py` — pure math, no MediaPipe dependency; the most unit-testable module.
- `pose.py` — the only module touching MediaPipe. Everything downstream works on
  plain landmark arrays, so tests never need the ML runtime.
- `analyzers/base.py` — contract: `analyze(frames: list[Frame]) -> ExerciseReport`,
  where `Frame` holds smoothed landmarks + timestamp. New exercises = new files in
  `analyzers/`, zero changes to the pipeline.
- `annotate.py` — draws on frames independently of analysis; skeleton overlay works
  even if an exercise analyzer fails.

### Dependencies

`mediapipe`, `opencv-python`, `numpy`. No torch, no GPU.

## Squat Analysis Rules (Side View)

Landmarks used (near side): shoulder, hip, knee, knee-adjacent ankle.

- **Rep detection** — state machine on knee angle (hip–knee–ankle) with hysteresis:
  `standing (>160°) → descending → bottom (local minimum) → ascending → standing`.
  One full cycle = 1 rep. Hysteresis prevents flicker at thresholds. Partial reps
  (never return to standing) counted separately and flagged.
- **Depth** — knee angle at each rep's bottom position:
  - `>100°` = above parallel
  - `90–100°` = parallel
  - `<90°` = below parallel
  Per-rep verdict + session summary (% reps below parallel).
- **Forward lean** — torso angle (shoulder→hip line vs vertical) per frame;
  report average at bottom and max. Flagged excessive if bottom-of-rep torso
  angle >45° from vertical.
- **Tempo** — per rep: eccentric duration (standing→bottom), concentric duration
  (bottom→standing), bottom pause. Flagged "uncontrolled descent" if eccentric <1s.

### Not Detectable From Side View (Documented Limitations)

- Knee valgus, left/right asymmetry — need front view.
- Heel lift — needs foot landmarks / different angle.

These require front view or additional landmarks — explicitly out of scope for
phase 1, not silently ignored.

## Error Handling

- **No person in frame** → skip frame, track gap ratio; warn in report if >20% of
  frames empty.
- **Low landmark visibility** → angles computed only when key landmarks exceed
  visibility threshold; unreliable frames excluded from metrics.
- **Unreadable video / unsupported exercise flag** → clear CLI error messages,
  non-zero exit code.

## Testing Strategy

- `test_geometry.py` — angle math on hand-computed landmark positions (pure, no ML).
- `test_squat.py` — synthetic knee-angle trajectories (sine waves, known rep counts,
  known depths) through the state machine; assert rep count, depth categories,
  tempo values.
- `test_pipeline.py` — end-to-end on a tiny generated video, marked optional/slow.
- README documents filming guidance: side view, full body in frame, good lighting,
  30fps+.

## Extensibility

New exercises implement `ExerciseAnalyzer` in `src/formbuddy/analyzers/`. The CLI
dispatches via `--exercise <name>`. Pose pipeline, smoothing, report builder, and
video annotator are exercise-agnostic and require no changes per exercise.
