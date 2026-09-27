# FormBuddy

AI-powered form analysis for weight training. FormBuddy watches a video of
you lifting and scores your form rep by rep — starting with the squat.

## Install

```bash
pip install -e .
```

Requires Python 3.10+ (developed on 3.12). This installs the `formbuddy`
command; the MediaPipe pose model is bundled as package data.

## Usage

```bash
formbuddy --input squat.mp4
formbuddy --input squat.mp4 --exercise squat --output-dir ./out
formbuddy --input squat.mp4 --no-video   # reports only, no annotated video
```

| Flag | Default | Description |
| --- | --- | --- |
| `--input` | (required) | Path to the input video file. |
| `--exercise` | `squat` | Exercise to analyze. Choices come from the analyzer registry in `src/formbuddy/pipeline.py`. |
| `--output-dir` | `./out` | Where the reports and annotated video are written. |
| `--no-video` | off | Skip the annotated MP4. |
| `--no-segmentation` | off | Skip person segmentation and run pose on the raw frames. |

On success the command prints a one-line summary and exits 0:

```bash
$ formbuddy --input squat.mp4
reps=3 below_parallel=1
```

Exit codes: `0` success, `1` missing or unreadable input file, `2` usage
error (including an unsupported `--exercise`).

## Filming guidance

- **Side view.** All angles are measured in the sagittal (side) plane, so
  the camera must be roughly perpendicular to the lifter's direction of
  travel — tripod to the side of the platform, about hip height.
- **Full body in frame.** Head to toe, with margin, for the whole rep. The
  feet must stay visible at the bottom of the frame — ankle position is
  part of the depth estimate.
- **Good lighting.** Bright, even, diffuse light. Avoid backlighting and
  harsh shadows, which degrade landmark detection.
- **30 fps or faster.** Rep timing (eccentric / concentric / bottom pause)
  is computed from frame timestamps, so frame rate sets the time
  resolution.

## Output

`--output-dir` (default `./out`) receives:

- `report.json` — the full machine-readable report: video metadata, summary
  counts, per-rep depth / timing / faults, and warnings.
- `report.txt` — the same report as human-readable text.
- `<stem>_annotated.mp4` — the input video with pose landmarks, the
  knee-angle trace, and per-rep depth labels overlaid (skipped with
  `--no-video`).

## How analysis works

1. **Person segmentation.** Each frame is run through MediaPipe selfie
   segmentation (`selfie_segmenter.tflite`).  The largest connected person
   component — the best person in the scene — is kept and every other pixel
   is suppressed to a flat grey, so the pose model never sees the rack,
   plates or benches.  Pose results whose visible landmarks fall mostly
   outside the silhouette are dropped as environment lock-on.
   `report.json` records `segmented_frames` and
   `pose_rejected_outside_person` under `video_meta`.
2. **Pose estimation.** Each (person-only) frame is run through MediaPipe
   Pose (`pose_landmarker_lite.task`), yielding 33 body landmarks.
3. **Temporal smoothing.** Landmarks pass through a one-euro-style filter
   that removes jitter without adding perceptible lag.
4. **Rep detection.** A hysteresis state machine on the knee angle
   (hip–knee–ankle) segments the clip into reps: a rep starts as the
   lifter leaves standing, bottoms out, and returns to standing.
5. **Form scoring.** Per rep, depth is classified from the bottom knee
   angle (below / at / above parallel), and faults are recorded:
   `insufficient_depth`, `excessive_forward_lean` (torso angle from
   vertical at the bottom), and `uncontrolled_descent` (eccentric faster
   than 1 s).
6. **Reporting.** Counts and per-rep details are written to `report.json`
   / `report.txt`, and the annotated video is rendered from the smoothed
   landmarks.

## Known limitations

- **Segmentation is a gate, not a guarantee.** Frames where the selfie
  model finds no person fall back to raw-frame pose estimation, and the
  model can struggle with unusual framing (a very small or seated lifter).
  If a clip segments poorly, rerun with `--no-segmentation`.
- **Side view only.** The model reasons about a single 2D projection, so it
  cannot detect **knee valgus** (knees caving inward), **left/right
  asymmetries**, or **heel lift** — those need a front or rear view (or
  3D). Film additional angles and analyze them separately if you need
  those cues.
- Depth classification is approximate near the parallel boundary.
- The lifter must be clearly visible; clips where no person is detected in
  most frames produce a `no_person_in_most_frames` warning and a 0-rep
  report.

## Adding an exercise

1. Create `src/formbuddy/analyzers/<exercise>.py` with a class that
   subclasses `ExerciseAnalyzer` (see `analyzers/squat.py` for the
   pattern). Implement `analyze(frames) -> ExerciseReport` returning
   per-rep metrics and a summary.
2. Register it in the `ANALYZERS` dict in `src/formbuddy/pipeline.py`:

   ```python
   ANALYZERS = {"squat": SquatAnalyzer, "deadlift": DeadliftAnalyzer}
   ```

3. The CLI picks the new name up automatically — `--exercise deadlift`
   works with no CLI changes, because the argparse choices come from
   `ANALYZERS`.

## iOS app

The native app lives in `FormBuddy/` and ships the same analyzer on device. Its
MediaPipe dependency comes from CocoaPods, so **always open the workspace, not
the project**:

```bash
xcodegen generate     # regenerate FormBuddy.xcodeproj (runs pod install)
open FormBuddy.xcworkspace
```

> Opening `FormBuddy.xcodeproj` directly fails with
> `Unable to resolve module dependency: 'MediaPipeTasksVision'` — the CocoaPods
> products only exist in `FormBuddy.xcworkspace`.

Build and test from the command line:

```bash
make ios-build        # or: make ios-test
```

`xcodegen generate` runs `pod install` automatically (`postGenCommand` in
`project.yml`), so the workspace stays integrated after regenerating.

The app turns the report into a feedback experience: an annotated video that
highlights faults on the body, a per-rep strip (tap a rep to loop it) with a
plain-language note per fault, and a shareable "coach's card" still that shows
every rep's faults at a glance.

Pose is gated by person segmentation (the same `selfie_segmenter.tflite` the
CLI ships): each frame is masked to the best person before pose estimation, and
pose results that fall mostly outside the person silhouette are dropped, so the
rack uprights, plates and benches are ignored. `report.json` records
`segmented_frames` and `pose_rejected_outside_person` under `video_meta`, as the
Python pipeline does.

## Development

```bash
pip install -e ".[dev]"
pytest
```
