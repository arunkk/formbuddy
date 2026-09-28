# FormBuddy

AI-powered form analysis for weight training. FormBuddy watches a video of
you lifting and scores your form rep by rep — starting with the squat.

FormBuddy ships as native mobile apps that run the analysis on device; no clip
leaves the phone. The iOS app is implemented today and an Android app is
planned (see [Roadmap](#roadmap)).

## Repository layout

| Path | What it is |
| --- | --- |
| `FormBuddy/` | iOS app (SwiftUI). `AnalysisCore/` is the portable analysis engine. |
| `FormBuddy/Pose/` | Bundled MediaPipe models (`pose_landmarker_lite.task`, `selfie_segmenter.tflite`). |
| `Tests/FormBuddyTests/` | iOS unit tests. |
| `project.yml` | XcodeGen source for `FormBuddy.xcodeproj`; `Podfile` supplies MediaPipe. |

## Build and run (iOS)

Requires Xcode, XcodeGen, and CocoaPods.

```bash
brew install xcodegen cocoapods   # once
make ios-generate                 # regenerate FormBuddy.xcodeproj (runs pod install)
open FormBuddy.xcworkspace
```

> Always open `FormBuddy.xcworkspace`, never `FormBuddy.xcodeproj`. Opening the
> project directly fails with `Unable to resolve module dependency:
> 'MediaPipeTasksVision'` — the CocoaPods products only exist in the workspace.

Build and test from the command line:

```bash
make ios-build        # or: make ios-test
make ios-run          # build, install, and launch on the booted simulator
```

`xcodegen generate` runs `pod install` automatically (`postGenCommand` in
`project.yml`), so the workspace stays integrated after regenerating.

`FormBuddy.xcodeproj` is generated output: change `project.yml` (or the
`Podfile`), then regenerate. Don't edit the project file by hand.

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

Each analysis produces a report — `video_meta`, summary counts, per-rep depth,
timing and faults, and any warnings — that the app renders as a feedback
experience: an annotated video that highlights faults on the body, a per-rep
strip (tap a rep to loop it) with a plain-language note per fault, and a
shareable "coach's card" still that shows every rep's faults at a glance.

Reports are the app's portable interchange format: the same JSON shape is what
a future Android app must produce and consume.

## How analysis works

1. **Person segmentation.** Each frame is run through MediaPipe selfie
   segmentation (`selfie_segmenter.tflite`). The largest connected person
   component — the best person in the scene — is kept and every other pixel is
   suppressed to a flat grey, so the pose model never sees the rack, plates or
   benches. Pose results whose visible landmarks fall mostly outside the
   silhouette are dropped as environment lock-on. The report records
   `segmented_frames` and `pose_rejected_outside_person` under `video_meta`.
2. **Pose estimation.** Each (person-only) frame is run through MediaPipe Pose
   (`pose_landmarker_lite.task`), yielding 33 body landmarks.
3. **Temporal smoothing.** Landmarks pass through a one-euro-style filter that
   removes jitter without adding perceptible lag. Landmarks below a visibility
   threshold are carried forward rather than smoothed.
4. **Rep detection.** A hysteresis state machine on the knee angle
   (hip–knee–ankle) segments the clip into reps: a rep starts as the lifter
   leaves standing, bottoms out, and returns to standing.
5. **Form scoring.** Per rep, depth is classified from the bottom knee angle
   (`<90°` below parallel, `>100°` above parallel, otherwise parallel), and
   faults are recorded: `insufficient_depth`, `excessive_forward_lean` (torso
   angle from vertical at the bottom), and `uncontrolled_descent` (eccentric
   faster than 1 s).
6. **Reporting.** Counts and per-rep details drive the annotated video, the
   rep strip, and the coach's card.

The analysis core is platform-neutral Swift. Keeping it free of UIKit and
AVFoundation types is what makes the planned Android port tractable.

## Known limitations

- **Segmentation is a gate, not a guarantee.** Frames where the selfie model
  finds no person fall back to raw-frame pose estimation, and the model can
  struggle with unusual framing (a very small or seated lifter).
- **Side view only.** The model reasons about a single 2D projection, so it
  cannot detect **knee valgus** (knees caving inward), **left/right
  asymmetries**, or **heel lift** — those need a front or rear view (or 3D).
  Film additional angles and analyze them separately if you need those cues.
- Depth classification is approximate near the parallel boundary.
- The lifter must be clearly visible; clips where no person is detected in
  most frames produce a `no_person_in_most_frames` warning and a 0-rep report.

## Roadmap

### Android

There is no Android app yet. The intended plan:

1. **Port the analysis core to Kotlin.** `FormBuddy/AnalysisCore/` is written
   to be portable: geometry, rep segmentation, smoothing, depth/fault scoring,
   and report models have no iOS-framework dependencies. Port them one type at
   a time, keeping the module-level tuning constants numerically identical.
2. **Wrap MediaPipe Tasks for Android.** The same two models
   (`pose_landmarker_lite.task`, `selfie_segmenter.tflite`) ship in
   `FormBuddy/Pose/` and are consumed through the MediaPipe Tasks Android API,
   mirroring `FormBuddy/Pose/PoseEstimator.swift` and `PersonSegmenter.swift`.
3. **Rebuild the capture and feedback UI** with CameraX and Jetpack Compose,
   following the iOS capture flow and feedback experience.
4. **Keep the report schema identical** across platforms so a report can move
   between devices, and cover the ported core with unit tests using synthetic
   landmark trajectories.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). `AGENTS.md` documents the build
commands and the non-obvious parts of the layout.
