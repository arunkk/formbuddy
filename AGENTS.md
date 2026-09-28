# AGENTS.md

FormBuddy is a **native mobile app** for weight-training form analysis. The iOS
client in `FormBuddy/` is implemented; there is no Android app yet (see the
Roadmap in `README.md`).

Analysis runs **on device**. `FormBuddy/AnalysisCore/` is the portable engine
(geometry, pose-frame types, smoothing, rep segmentation, the squat analyzer,
report models). It must stay free of UIKit, AVFoundation, and MediaPipe imports
so it can be ported to Android — that boundary is the single most important
convention in this repo. `PersonMask` is the one file that already leaks a
platform pixel type (`import CoreVideo`), so expect light adaptation when
porting it.

- `FormBuddy/AnalysisCore/` — platform-neutral analysis engine.
- `FormBuddy/Pose/` — MediaPipe wrappers + bundled models.
- `FormBuddy/UI/`, `FormBuddy/Video/`, `FormBuddy/Persistence/` — iOS-only layers.
- `Tests/FormBuddyTests/` — iOS unit tests.

## Commands

```bash
make ios-generate  # xcodegen generate (postGenCommand runs `pod install`)
make ios-build     # xcodebuild -workspace FormBuddy.xcworkspace
make ios-test      # same, `test` action
make ios-run       # build, install, launch on the booted simulator
```

Single Swift test: append `-only-testing:FormBuddyTests/SquatAnalyzerTests` to
the `ios-test` command. Override the simulator with `make ios-test SIMULATOR="iPhone 17"`.

## Gotchas (verify these before trusting tooling)

- **Never open or build `FormBuddy.xcodeproj`.** MediaPipeTasksVision comes from
  CocoaPods and only resolves in `FormBuddy.xcworkspace`. Always pass
  `-workspace`, never `-project`.
- **`FormBuddy.xcodeproj` is generated output.** Change `project.yml` (or the
  `Podfile`), then run `make ios-generate`. Hand edits are overwritten.
- **`Pods/` is gitignored but required to build.** After a fresh clone or a
  dependency change, `pod install` (or `make ios-generate`) before
  `make ios-build`.
- **`Tests/` and `tests/` are the same directory** on macOS's case-insensitive
  filesystem. Swift tests live in `Tests/FormBuddyTests` (capital T); the
  XcodeGen source path is case-sensitive, so keep the exact casing.
- **`testdata/` is gitignored**, so no video fixture ships in the repo. Tests
  must use synthetic landmark trajectories (see `SquatAnalyzerTests.swift`);
  never assume a sample clip exists.
- `Podfile`'s `post_install` strips a `force_load` flag from the **test target**
  only. Removing it re-breaks XCTest bundle injection. Leave it.
- `scripts/generate_app_icon.swift` is a Swift script, not part of the app
  build. Regenerate icons with `swift scripts/generate_app_icon.swift`; the
  assets in `FormBuddy/Assets.xcassets` are generated, not hand-edited.

## Architecture notes that are not obvious from filenames

- **The analysis pipeline order is load-bearing:** segment person → mask
  background to grey → pose → reject landmarks mostly outside the silhouette →
  one-euro smoothing → rep detection → scoring. Keep any port in this order.
- **Smoothing intentionally carries the last landmarks forward through
  detected-pose gaps.** Do not count "empty" or missing frames from the
  smoother's return value — the pipeline counts those at the detection level.
  This is a known trap when porting.
- **Tuning constants are module-level and must match across platforms.**
  `SquatAnalyzer` (`standingKneeAngle`, `hysteresisAngle`, `riseConfirmAngle`,
  `depthAbove`, `depthParallel`, `excessiveLeanDegrees`, `minEccentricSeconds`),
  `LandmarkSmoother` (visibility gate), and `PersonMask`
  (`minLandmarkInsideFraction`). Change them alongside the tests.
- **Depth classes come from the bottom knee angle:** `<90°` → `below_parallel`,
  `>100°` → `above_parallel`, otherwise (90–100° inclusive) → `parallel`.
- **MediaPipe models are bundled, not downloaded at runtime.**
  `FormBuddy/Pose/pose_landmarker_lite.task` and `selfie_segmenter.tflite`.
- **The report JSON is the cross-platform interchange format.** Keep its shape
  stable when adding fields so a future Android app can read and write it.

## Conventions

- Analyzers stay **pure**: no I/O, no MediaPipe imports — operate on landmark
  arrays (`ExerciseAnalyzer.analyze(_:) -> ExerciseReport`).
- Add new exercises by adding an `ExerciseAnalyzer` conformer in
  `AnalysisCore/` and registering it where the app selects an analyzer.
- No Swift linter/formatter config exists. Match surrounding style.
- Verify with `make ios-test` before treating a change as done.
