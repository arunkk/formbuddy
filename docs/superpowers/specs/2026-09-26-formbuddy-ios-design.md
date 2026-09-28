# FormBuddy iOS — Mobile Port Design

> **Status note:** this document is the original port design and is kept for
> rationale. It was written while the analysis engine also existed as a Python
> CLI; that implementation has since been removed and FormBuddy is now
> mobile-only. References below to `src/formbuddy/*.py`, `pipeline.run`, the
> CLI, and Python-generated parity fixtures describe the engine the Swift
> `AnalysisCore` was ported from, not code that still lives in this repo. The
> current layout and Android plan are in `README.md` and `AGENTS.md`.

**Date:** 2026-09-26
**Status:** Proposed design, pending review

## Overview

FormBuddy iOS is the first native client of the FormBuddy analysis engine: the
user records (or imports) a side-view squat clip, the app estimates pose per
frame with the same MediaPipe model the engine bundles, runs the same
biomechanical rules, and presents a rep-by-rep report with annotated playback.

**Hard constraint: no cloud.** No account, no upload, no network calls of any
kind. The model bundle ships inside the app; all video, landmarks, and reports
stay in the app sandbox. This is a feature, not a limitation — it makes the App
Store privacy label "Data Not Collected" and removes an entire class of backend
work.

**Sequencing:** iOS first (SwiftUI), Android later (Kotlin + Jetpack Compose).
Native per platform, no cross-platform UI framework. The Android port is made
cheap not by shared code but by a shared *contract*: JSON landmark fixtures and
a byte-compatible `report.json` schema (see "Parity strategy").

### Goals

1. Numerical parity with the reference squat analyzer, provable by test.
2. A streaming pipeline that fits in phone memory.
3. Analysis-core code that is pure and unit-testable with no ML runtime.
4. An architecture where "live coaching" (v2) is a small step, not a rewrite.

### Non-goals (v1)

- Live/real-time camera feedback. Designed for, not built.
- Annotated-MP4 export (baking the overlay into a new video file). The overlay
  is rendered at playback time instead. Optional later milestone.
- New exercises. Squat only.
- Front-view faults: knee valgus, left/right asymmetry, heel lift. Same
  limitation as the reference side-view analyzer — surfaced in UI copy, not
  silently dropped.
- Multi-person. `numPoses = 1`.
- Any cloud service, sync, or analytics.

## Technology decisions

### Pose runtime: MediaPipe Tasks Vision (same model file as the CLI)

`src/formbuddy/assets/pose_landmarker_lite.task` (5,777,746 bytes, verified
byte-size-identical to the currently published `float16/latest` bundle) loads
directly into the native iOS API. No conversion, no retraining, no Core ML
export step. The 33-landmark topology and the per-landmark `visibility` score
both carry over — which matters, because the squat analyzer is written *against*
visibility:

- `SquatAnalyzer._measure` bails out unless mean hip/knee/ankle visibility on at
  least one side is `>= 0.5` (`_MIN_SIDE_VISIBILITY`).
- `geometry.select_side` picks the near side by comparing mean visibility, ties
  breaking to `"left"`.

Any runtime without a visibility/score channel per landmark breaks both.

### Alternatives considered

| Runtime | Platforms | Keypoints | Per-point score | Verdict |
| --- | --- | --- | --- | --- |
| **MediaPipe Tasks Vision** | iOS + Android | 33 (BlazePose) + `worldLandmarks` | `visibility` + `presence` | **Chosen.** Same `.task` bundle as the CLI, so parity is provable. |
| Apple Vision `VNDetectHumanBodyPoseRequest` | iOS only | 19 | `confidence` | Viable for squat (has hip/knee/ankle/shoulder), zero added binary size, GPU/ANE accelerated. Rejected: no Android equivalent (ML Kit Pose is Android-only), and it lacks landmarks 29–32 (heel, foot index) — exactly the points a future heel-lift fault needs. `VNDetectHumanBodyPose3DRequest` exists (iOS 16+) but is a different contract again. |
| TFLite/LiteRT + MoveNet | Both | 17 (COCO) | keypoint scores | Rejected: loses BlazePose topology, needs a re-derived visibility contract, and you would maintain the inference wrapper yourself. |
| ML Kit Pose Detection | Android only | 33 | yes | Not available on iOS; breaks the two-platform story. |
| Ship the Python code (`Chaquopy`, `PythonKit`, Kivy/BeeWare) | Android mostly | — | — | **Dead end.** There is no CPython `mediapipe` wheel for iOS. Do not plan around embedding Python. |

### App framework: native SwiftUI, then native Compose

Rejected cross-platform options, for a project whose hardest surface is
per-frame camera + ML work:

- **Kotlin Multiplatform** — genuinely attractive (the analysis core is exactly
  what KMP shares well) but it adds a Gradle/KMP toolchain on top of learning
  Swift, Xcode, and AVFoundation simultaneously. Not the right time.
- **Flutter / React Native** — MediaPipe reaches these through community
  plugins or platform channels, and per-frame buffer streaming is more glue
  with weaker frame-accurate guarantees. You would also rewrite the algorithm
  in Dart/TS, giving up the Swift ↔ Python proximity that makes parity review
  easy.

The analysis core is ~300 lines (`geometry.py` + `smoothing.py` + the squat
state machine). Porting it twice is a smaller cost than fighting a bridge on the
frame-processing path.

### UI framework layer

SwiftUI throughout, with UIKit/AppKit-free AVFoundation underneath for capture
and decode. No Storyboards, no Interface Builder — everything in code so the
project diffs cleanly.

## Verified library reference

Facts below were checked against upstream docs and registries on 2026-09-26;
re-verify at implementation time, MediaPipe releases frequently.

**iOS**

| Item | Value |
| --- | --- |
| Swift Package Manager | `https://github.com/google-ai-edge/mediapipe`, product `MediaPipeTasksVision` (`MediaPipeTasksCommon` comes in automatically) |
| Current SPM binary target | prebuilt `MediaPipeTasksVision-1.0.1.xcframework.zip` (no Bazel/source build) |
| CocoaPods alternative | `pod 'MediaPipeTasksVision'`, latest published `1.0.0` |
| Minimum iOS | **15.0** |
| Minimum Xcode | **14.1** |
| Acceleration | **CPU only.** Upstream: "On iOS, MediaPipe Tasks only supports running models on standard CPU processors." No GPU delegate. |
| Simulator | 64-bit only (arm64, x86_64); simulator has no device camera |
| Model | `pose_landmarker_lite.task` — 5.5 MiB. (`full` = 9.0 MiB, `heavy` = 29.2 MiB.) |

Swift API surface (verbatim from upstream docs):

```swift
import MediaPipeTasksVision

let options = PoseLandmarkerOptions()
options.baseOptions.modelAssetPath = modelPath
options.runningMode = .video          // .image | .video | .liveStream
options.numPoses = 1
options.minPoseDetectionConfidence = 0.5
options.minTrackingConfidence = 0.5
let landmarker = try PoseLandmarker(options: options)

let image = try MPImage(pixelBuffer: pixelBuffer)   // or uiImage: / sampleBuffer:
let result = try landmarker.detect(videoFrame: image, timestampInMilliseconds: ts)
// .liveStream uses detectAsync(image:timestampInMilliseconds:) + PoseLandmarkerLiveStreamDelegate
```

**Android (later)**

| Item | Value |
| --- | --- |
| Gradle | `implementation 'com.google.mediapipe:tasks-vision:1.0.0'` (pin; do not use `latest.release`) |
| Minimum SDK | **24** |
| Acceleration | GPU available — `BaseOptions.builder().useGpu().build()` (default is CPU) |
| API | `PoseLandmarker.createFromOptions`, `detectForVideo(mpImage, timestampMs)`, `detectAsync` for `LIVE_STREAM` |

Note the asymmetry: **Android has a GPU delegate, iOS does not.** Live mode will
behave differently across platforms; budget for it in v2.

**SPM gotcha.** The `google-ai-edge/mediapipe` repository is ~595 MB, and SPM
clones it to read the manifest even though the target itself is a prebuilt
XCFramework. First resolve will be slow and disk-hungry. If that becomes
painful, CocoaPods (`pod 'MediaPipeTasksVision'`) downloads a prebuilt pod
instead — at the cost of a `Podfile`, a `.xcworkspace`, and `pod install` in the
loop. Start with SPM; switch only if it hurts.

**Other iOS libraries**

| Need | Choice | Why |
| --- | --- | --- |
| Camera capture | `AVCaptureSession` + `AVCaptureMovieFileOutput` | Writes a correct MOV/MP4 with orientation metadata in a few lines. Avoid hand-rolling `AVAssetWriter` for capture. |
| Video decode for analysis | `AVAssetReader` + `AVAssetReaderTrackOutput` | Sequential frame-by-frame `CVPixelBuffer`, no OpenCV, no whole-file buffering. |
| Import from Photos | SwiftUI `PhotosPicker` | No photo-library permission needed for reads via the picker. |
| Persistence | SwiftData | iOS 17+, `@Model` + `@Query`, least boilerplate for a beginner. Escape hatch: `Codable` + JSON in Application Support. |
| Charts | Swift Charts | Replaces the knee-angle trace that `annotate.py` bakes into the video. |
| Overlay rendering | SwiftUI `Canvas` over an `AVPlayerLayer` | No Metal, no Core Image, no re-encode. Toggleable layers for free. |
| Tests | XCTest | Plus JSON fixtures generated by the Python suite. |

## Architecture & data flow

The CLI's flow (`pipeline.run`) is batch and **holds every decoded frame in
memory** (`frames: list[np.ndarray]`). On a phone that is fatal: 60 s of 1080p
BGR is 1920×1080×3×30×60 ≈ **11.2 GB**. The mobile pipeline is streaming —
pixels are decoded, converted, inferred on, and dropped, one buffer at a time.

```
AVCaptureMovieFileOutput (or PhotosPicker import)
        ↓  .mov in app sandbox, 720p30
AVAssetReader → CVPixelBuffer (one at a time; never retained)
        ↓
PoseEstimator (MediaPipe .video mode, CPU)  → Landmarks? (33 × x,y,visibility)
        ↓
LandmarkSmoother (visibility-gated EMA, α = 0.5)
        ↓
SquatAnalyzer.process(frame) → FrameAnnotation        ← incremental, not batch
        ↓ (on finish)
SquatReport { reps, summary, warnings, videoMeta }
        ↓
        ├── SwiftData  (Session + Rep rows, queryable history)
        ├── annotations sidecar (per-frame landmarks + angles + phase)
        └── report.json (schema-identical to the Python ReportBuilder)

Playback: AVPlayer(original clip) + Canvas(overlay from sidecar) + Swift Charts
```

**The annotated video is not re-encoded.** `annotate.py` draws into pixels and
`VideoWriter` writes a second MP4. On mobile, store the per-frame annotation
sidecar instead and draw over the original clip at playback time. Benefits: no
re-encode cost, no duplicate storage, layers are toggleable, and adding a new
overlay does not require re-analyzing anything. Baked-MP4 export becomes an
optional share feature later (`AVAssetReader` → Core Graphics into a
`CVPixelBuffer` → `AVAssetWriter`).

Sidecar size is trivial: 900 frames (30 s @ 30 fps) × 33 × 3 × `Float32` ≈ 356 KB.

### Two clocks (a real trap)

Python conflates two timestamps, and the port must not:

1. **MediaPipe timestamp** — `pose.py` synthesizes `frame_index * 33 ms` purely
   because `detect_for_video` requires strictly increasing values. On mobile,
   pass the real presentation timestamp in ms from `CMSampleBufferGetOutput PTS`
   converted via `CMTimeGetSeconds`. It only affects internal tracking.
2. **Analysis timestamp** — `pipeline.py` sets `timestamps.append(index / fps)`,
   i.e. frame index over nominal fps, *not* container PTS. Every tempo number in
   the report (eccentric, concentric, bottom pause) and the `uncontrolled_descent`
   fault derive from this. **Keep `index / fps` exactly** or you lose parity.

They must be separate values threaded separately. Also preserve the fps fallback:
`if fps <= 0: fps = 30.0`.

### Orientation (the most common iOS video-ML bug)

iPhone clips are stored as a landscape pixel buffer plus a `preferredTransform`
(usually 90°). MediaPipe returns landmarks normalized to the **buffer**, not to
the displayed image. If the overlay ignores `preferredTransform`, the skeleton
will be rotated or mirrored relative to the video.

Rule: read the track's `preferredTransform` once per clip, store it on the
`Session`, and apply it when mapping normalized landmark coordinates into view
space. Add an explicit unit test using a fixture clip with a 90° transform. This
applies equally to recorded and Photos-imported clips.

## Module breakdown

```
FormBuddy/
├── FormBuddy.xcodeproj
├── Package.swift                     # SPM: google-ai-edge/mediapipe → MediaPipeTasksVision
├── FormBuddy/
│   ├── App/
│   │   ├── FormBuddyApp.swift        # @main, SwiftData ModelContainer
│   │   └── RootView.swift
│   ├── AnalysisCore/                 # PURE SWIFT — no MediaPipe, no AVFoundation
│   │   ├── Landmarks.swift           # 33 × (x, y, visibility) value type
│   │   ├── PoseFrame.swift           # ↔ analyzers/base.py Frame
│   │   ├── Geometry.swift            # ↔ geometry.py
│   │   ├── LandmarkSmoother.swift    # ↔ smoothing.py
│   │   ├── ExerciseAnalyzer.swift    # ↔ analyzers/base.py protocol
│   │   ├── SquatAnalyzer.swift       # ↔ analyzers/squat.py (incremental)
│   │   └── ReportModels.swift        # ↔ SquatReport/SquatSummary/RepResult + Codable keys
│   ├── Pose/
│   │   ├── PoseEstimator.swift       # ↔ pose.py — ONLY file importing MediaPipe
│   │   └── pose_landmarker_lite.task # copied from src/formbuddy/assets/
│   ├── Video/
│   │   ├── VideoFrameReader.swift    # AVAssetReader wrapper, streaming
│   │   ├── CameraRecorder.swift      # AVCaptureSession + AVCaptureMovieFileOutput
│   │   └── OrientationMapper.swift   # preferredTransform → view-space mapping
│   ├── Pipeline/
│   │   └── AnalysisPipeline.swift    # ↔ pipeline.py, streaming, cancellable, progress
│   ├── Persistence/
│   │   ├── Session.swift             # @Model
│   │   ├── RepRecord.swift           # @Model
│   │   ├── AnnotationStore.swift     # sidecar read/write
│   │   └── ReportJSONEncoder.swift   # ↔ report.py schema
│   ├── UI/
│   │   ├── SessionListView.swift
│   │   ├── CaptureView.swift
│   │   ├── AnalyzingView.swift
│   │   ├── SessionDetailView.swift
│   │   ├── AnnotatedPlaybackView.swift
│   │   ├── KneeAngleChart.swift
│   │   ├── GuidanceView.swift
│   │   └── SettingsView.swift
│   ├── PrivacyInfo.xcprivacy
│   └── Info.plist                    # NSCameraUsageDescription, NSPhotoLibraryAddUsageDescription
└── FormBuddyTests/
    ├── GeometryTests.swift           # ↔ tests/test_geometry.py
    ├── SmoothingTests.swift          # ↔ tests/test_smoothing.py
    ├── SquatAnalyzerTests.swift      # ↔ tests/test_squat.py
    ├── FixtureParityTests.swift      # NEW: runs Python-generated JSON fixtures
    └── Fixtures/*.json               # generated by the Python suite, checked in
```

`AnalysisCore` mirrors the discipline the Python design already states: *"`pose.py`
— the only module touching MediaPipe. Everything downstream works on plain
landmark arrays, so tests never need the ML runtime."* Keep that invariant. It is
what makes M1 (the whole analysis core) testable before a camera exists.

## Porting rules

### Ports 1:1 (translate, do not redesign)

| Python | Swift | Notes |
| --- | --- | --- |
| `joint_angle(a, b, c)` | `jointAngle(_:_:_:)` | Clamp cosine to `[-1, 1]` before `acos`, as the Python does. |
| `segment_angle_vs_vertical(top, bottom)` | `segmentAngleVsVertical(_:_:)` | Image coords, y down; upright = 0°. |
| `select_side(landmarks)` | `selectSide(_:)` | `>=` comparison — **ties break to left**. |
| `SIDE_LANDMARKS` | constant | left hip/knee/ankle = 23/25/27; right = 24/26/28. |
| `LandmarkSmoother` | `LandmarkSmoother` | α = 0.5; visibility gate `>= 0.5`; carry forward last state when input is `nil`; return `nil` until first detection. |
| All squat thresholds | constants | `STANDING_KNEE_ANGLE 160`, `HYSTERESIS_ANGLE 150`, `RISE_CONFIRM_ANGLE 10`, `DEPTH_ABOVE 100`, `DEPTH_PARALLEL 90`, `EXCESSIVE_LEAN_DEGREES 45`, `MIN_ECCENTRIC_SECONDS 1.0`. |
| Depth classification | `_classifyDepth` | `<90` below, `>100` above, else parallel — note the boundary asymmetry. |
| Fault names | string constants | `insufficient_depth`, `excessive_forward_lean`, `uncontrolled_descent`, and the warning `no_person_in_most_frames`. Keep the exact strings; they are the report contract. |
| Empty-frame warning | pipeline | Counted at the **detection** level (estimator returned `nil`), *not* from the smoother's output, because the smoother carries forward. Threshold is strictly `> 0.2`. |

**Compute angles in `Double`.** `geometry.py` goes through numpy `float64`
(`np.array(...)` of Python floats). Landmark inputs are `Float32` from MediaPipe;
upcast before the trig so results match the Python to ~1e-9 rather than ~1e-6.

**One simplification comes free:** `pipeline.py` must copy the smoother's output
(`smoothed.copy()`) because the Python smoother returns its internal mutable
array. Swift arrays are value types, so that whole class of aliasing bug
disappears. Do not "port" the copy.

### Must be redesigned

**1. `SquatAnalyzer` becomes incremental.** Python's `analyze(frames)` is a batch
pass. The logic is already a pure streaming state machine — the only batch-ness
is the post-loop "clip ended mid-rep → close a partial rep" step, which uses
`frames[-1].timestamp`. Split it:

```swift
final class SquatAnalyzer: ExerciseAnalyzer {
    /// Mirrors one iteration of the Python for-loop. Returns the annotation for
    /// this frame; appends to `report.frames` exactly as the Python does,
    /// including empty frames (nil landmarks → nil angles, untouched state).
    func process(_ frame: PoseFrame) -> FrameAnnotation

    /// Mirrors the Python post-loop partial-rep close. Uses the last processed
    /// frame's timestamp, or 0.0 when no frames were processed.
    func finish() -> SquatReport
}

extension SquatAnalyzer {
    /// Batch convenience = the Python `analyze()`; used by tests and by
    /// recorded-clip analysis. Keep the invariant: one annotation per input frame.
    func analyze(_ frames: [PoseFrame]) -> SquatReport
}
```

This is the single change that makes v2 live coaching incremental rather than a
rewrite: live mode is the same `process(_:)` fed from a camera callback.

**2. `pipeline.run` becomes a cancellable async stream.** No frame retention,
progress reporting, and cooperative cancellation:

```swift
@Observable
final class AnalysisPipeline {
    private(set) var progress: Double = 0
    func analyze(videoAt url: URL, exercise: String) async throws -> SquatReport
}
```

Decode → infer → smooth → `process` in one loop; drop the pixel buffer each
iteration. Run off the main actor; publish progress for `AnalyzingView`.
`exercise` is validated against a registry mirroring `ANALYZERS`, so adding a
future exercise is a new file plus one dictionary entry.

**3. `annotate.py` becomes a playback overlay.** No OpenCV, no `cv2.putText`, no
`VideoWriter`. `AnnotatedPlaybackView` syncs a `Canvas` to `AVPlayer` via
`addPeriodicTimeObserver`, looks up the annotation for the current frame index,
and draws: skeleton (pose connections), knee-angle trace, phase, rep count, and
active faults in red — the same visual vocabulary as the Python HUD, with layers
the user can toggle.

**4. No OpenCV anywhere.** OpenCV exists in the Python for decode, colour
conversion, drawing, and MP4 muxing; AVFoundation + SwiftUI replace all four. Do
not add an OpenCV-for-iOS dependency (~100 MB+ of static libs) to preserve code
shape.

### Documentation-vs-code discrepancy to respect

The Python README describes smoothing as a "one-euro-style filter"; `smoothing.py`
implements a visibility-gated **exponential moving average** with α = 0.5 (its own
docstring says so). Port the *implementation*. Do not upgrade it to a real
one-euro filter during the port — that would silently break parity with every
existing tempo number. Fixing the README wording is a separate, safe change.

## Parity strategy

Parity is the thing most likely to go wrong and least likely to be noticed, so it
gets a harness rather than a hope. Two tiers, because they prove different things.

### Tier 1 — exact, on synthetic fixtures (the contract)

The existing Python test corpus already encodes the intended behaviour:
`tests/test_squat.py::make_frames` builds `(33, 3)` landmark arrays that realize
requested knee/torso angle trajectories, and the tests assert rep counts, depth
categories, faults, partials, and summary aggregates. Export those scenarios as
JSON and run them through the Swift port.

Add `scripts/export_fixtures.py` to the Python repo (reuses `make_frames` and
`SquatAnalyzer` directly — no new test logic):

```json
{
  "name": "two_clean_reps",
  "frames": [
    { "timestamp": 0.0, "landmarks": [0.5, 0.5, 1.0, "... 99 floats total"] },
    { "timestamp": 0.1, "landmarks": null }
  ],
  "expected": {
    "summary": { "total_reps": 2, "partial_reps": 0, "reps_below_parallel": 2,
                 "avg_eccentric_seconds": 0.0, "max_torso_angle": 0.0 },
    "reps": [{ "rep_number": 1, "depth": "below_parallel",
               "bottom_knee_angle": 80.0, "torso_angle_at_bottom": 0.0,
               "eccentric_seconds": 1.9, "concentric_seconds": 1.9,
               "bottom_pause_seconds": 0.0, "faults": [], "partial": false }],
    "frame_annotations": [{ "knee_angle": 170.0, "torso_angle": 0.0,
                            "phase": "standing", "rep_count": 0, "faults": [] }]
  }
}
```

Flat 99-float arrays (33 × x,y,visibility) keep decoding trivial in Swift
`JSONDecoder`, Kotlin `kotlinx.serialization`, and Python alike. `landmarks: null`
represents the empty-frame path.

`FixtureParityTests.swift` loads every fixture, feeds frames through
`SquatAnalyzer.analyze`, and asserts:

- summary fields equal within `1e-9`
- rep count, per-rep depth string, fault set, and `partial` flag equal **exactly**
- one frame annotation per input frame, with equal `phase` and `rep_count`

Scenarios to export from the current suite: two clean reps; bottom at 95°
(parallel); bottom at 110° (above parallel + `insufficient_depth`); 50° torso at
bottom (`excessive_forward_lean`); 0.5 s eccentric (`uncontrolled_descent`);
clip ending mid-rep (partial); all-zero visibility (0 reps, no crash); and the two
torso-summary cases (avg over all reps, max over all *measured frames* — including
the mid-descent spike case where max ≠ bottom value).

This tier runs in CI with **no ML runtime and no camera**, so it is fast and
cannot flake.

### Tier 2 — tolerance, on real video (the runtime)

Same clip through the CLI and through the app will not produce bit-identical
landmarks: different MediaPipe builds and backends (desktop CPU vs iOS CPU) can
differ slightly. Assert a tolerance band instead, on one short reference clip
committed to the repo:

- rep count: exact
- `depth` classification and fault set: exact (choose a clip whose reps are not
  near a threshold, so the band cannot flip a category)
- per-rep angles: within ±2°
- report structure: `report.json` key-for-key identical

Document any residual difference in the fixture README rather than widening the
band silently.

### Tier 3 — `report.json` interchange

The iOS app writes `report.json` with the exact schema `ReportBuilder.build`
produces: top-level `exercise`, `video_meta` (`fps`, `frame_count`, `duration`),
`summary`, `reps`, `warnings` — all snake_case, via explicit `CodingKeys`. A
report from the app should be readable by anything consuming the CLI's output,
and vice versa. Preserve the quirk that `duration = frame_count / fps`
(frame-derived, not container duration).

The per-frame annotation sidecar is a **mobile-only artifact** and is deliberately
not added to `report.json`, so the interchange schema stays clean.

## Data model

```swift
@Model final class Session {
    var id: UUID
    var exercise: String                 // "squat"
    var createdAt: Date
    var videoFilename: String            // relative to Application Support
    var orientationTransform: Data       // CGAffineTransform, for overlay mapping
    var fps: Double
    var frameCount: Int
    var duration: Double
    var warnings: [String]
    var summary: Summary                 // Codable struct, mirrors SquatSummary
    var annotationFilename: String       // sidecar
    @Relationship(deleteRule: .cascade, inverse: \RepRecord.session)
    var reps: [RepRecord]
}

@Model final class RepRecord {
    var repNumber: Int
    var depth: String                    // above_parallel | parallel | below_parallel
    var bottomKneeAngle: Double
    var torsoAngleAtBottom: Double
    var eccentricSeconds: Double
    var concentricSeconds: Double
    var bottomPauseSeconds: Double
    var faults: [String]
    var partial: Bool
    var session: Session?
}
```

Deleting a session deletes its video file and sidecar from disk — wire that into
the delete path explicitly, SwiftData will not do it. Show total on-device storage
used in Settings, since keeping source clips is the dominant cost.

**Deployment target: iOS 17.** SwiftData requires it. MediaPipe's floor is iOS
15, so it is not the constraint, and iOS 17 also brings Swift Charts maturity and
the `@Observable` macro. If wider reach is later required, swap SwiftData for
`Codable` + JSON and drop to iOS 16 — the `AnalysisCore` and `Pipeline` layers do
not change.

## Screens

1. **Sessions** (root) — history list, newest first: date, exercise, rep count,
   below-parallel count, fault badge. Empty state points at Capture and Guidance.
2. **Capture** — rear camera, portrait, 720p30 (`AVCaptureSessionPreset1280x720`;
   pose needs far less than 1080p and it cuts decode and inference cost).
   Full-body framing guide overlay (head-to-toe box with margin, feet inside the
   frame — the README's guidance drawn as UI), a side-view reminder, elapsed
   timer, and a 60 s cap. Plus "Import from Photos" via `PhotosPicker`.
3. **Analyzing** — determinate progress, cancellable, and an honest note that
   analysis may take longer than the clip itself (iOS is CPU-only).
4. **Session detail** — summary cards (total reps, partials, below/at/above
   parallel, avg eccentric/concentric/pause, avg and max torso angle); rep list
   with depth chip and fault chips; Swift Charts knee-angle trace with rep
   boundaries marked; annotated playback with layer toggles and a rep scrubber;
   warnings surfaced prominently when present.
5. **Guidance** — the README's filming guidance ported verbatim: side view,
   camera perpendicular to travel at hip height, full body in frame with feet
   visible, bright diffuse light, no backlighting, 30 fps+. Plus the documented
   limitations (no valgus / asymmetry / heel-lift detection from side view).
6. **Settings** — storage used, delete-all, export data (share sheet with
   `report.json`), privacy statement, and an "advanced" section exposing the
   seven thresholds for experimentation (defaults matching the constants).

## Performance & memory budget

- **Memory:** peak additional memory should be O(1) in clip length — one pixel
  buffer plus the landmark/annotation arrays (≈ 400 bytes/frame). A 60 s clip
  accumulates ~350 KB of annotations, not gigabytes of pixels. Add an Instruments
  Allocations check to M2's definition of done.
- **Inference:** the model internally resizes to 224×224 (detector) and 256×256
  (landmarker), so feeding 720p rather than 1080p mostly saves conversion and
  decode, not model time. Expect CPU-bound inference on iOS. **Measure in M0
  before building anything else** — this is the largest unknown in the project.
- **Throughput plan:** if measured speed is ≥ 30 fps on a mid-tier device, keep
  30 fps capture. If not, do *not* drop frames during analysis (that perturbs
  `index / fps` timing and breaks parity); instead reduce the capture frame rate
  and re-derive fps accordingly, or shorten the clip cap.
- **Backpressure:** irrelevant in v1 (batch analysis of a recorded file). Becomes
  real in v2 live mode — design for "drop the newest frame if the analyzer is
  still busy", never queue unboundedly.
- **Thermal:** sustained CPU inference throttles. Show progress, keep the screen
  on only during analysis, and cap clip length.

## Privacy, permissions, App Store

- `NSCameraUsageDescription` — recording exercise clips.
- `NSPhotoLibraryAddUsageDescription` — only if "save annotated export to Photos"
  is added later. Reading via `PhotosPicker` needs no permission string.
- No microphone permission: do not record audio. If `AVCaptureMovieFileOutput`
  defaults to including an audio connection, disable it explicitly — a squat clip
  does not need gym audio, and it removes a permission prompt and a privacy
  question.
- `PrivacyInfo.xcprivacy` — declare no data collection. Verify the bundled
  MediaPipe XCFramework satisfies required-reason API declarations and address any
  build-time privacy warning rather than suppressing it.
- **No networking code at all.** Nothing to disable; simply never add URLSession.
- App Review: this is fitness feedback, not medical advice. Keep UI copy
  descriptive ("3 reps above parallel", "descent under 1 s") and avoid diagnosis,
  treatment, or injury-prevention claims.

## Environment prerequisites (this machine)

Verified 2026-09-26, after fixing the active developer directory:

| Item | Value |
| --- | --- |
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| Xcode | 27.0 (build `27A266a`), license already accepted |
| Swift | 6.4 (`swiftlang-6.4.0.34.1`), target `arm64-apple-macosx27.0.0` |
| SDKs | `iphoneos27.0`, `iphonesimulator27.0` |
| Simulator runtime | iOS 27.0 (`24A434`) — iPhone 18 Pro, 18 Pro Max, 17, 17e, iPhone Air, iPad Pro 13" (M5) |
| Physical device | **none connected** |
| macOS | 27.0 |
| CocoaPods | not installed (not needed if SPM is used) |

The original blocker: `xcode-select -p` pointed at
`/Library/Developer/CommandLineTools`, so `xcodebuild` refused with *"tool
'xcodebuild' requires Xcode, but active developer directory ... is a command line
tools instance"*. Fixed with
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`; reversible via
`sudo xcode-select -r`. A per-shell `DEVELOPER_DIR` override does the same without
root, but do not persist it in a shell rc file — it pins the toolchain and fails
confusingly after an Xcode upgrade.

**Two consequences for the plan:**

1. **M0 needs hardware that is not attached.** MediaPipe on iOS is CPU-only, and a
   simulator runs that code on the Mac's Apple Silicon — far faster than any phone,
   and with no camera. Simulator timings would be optimistic by an unknown factor
   and therefore cannot answer the M0 go/no-go question. Benchmark a mid-tier
   device rather than a current flagship, so the number represents the *slowest*
   phone you intend to support. Until a device is available M0 is blocked, which
   makes **M1 the unblocked path**: the `AnalysisCore` port needs no camera, no ML
   runtime, and no device — it runs as a plain XCTest target.
2. **Swift 6.4 means strict concurrency is likely the default** for a new Xcode 27
   project. Expect `Sendable` diagnostics around the ObjC-based MediaPipe delegate
   callbacks (`PoseLandmarkerLiveStreamDelegate`). Setting the target to Swift 5
   language mode (`SWIFT_VERSION = 5`) is a legitimate way to reduce friction while
   learning Swift, with migration later. `AnalysisCore` should be written
   concurrency-clean regardless — it is pure value types with no excuse.

## Android follow-on

Same architecture, translated. The shared contract (fixtures + `report.json`) is
what makes this a port rather than a redesign.

| iOS | Android |
| --- | --- |
| SwiftUI | Jetpack Compose |
| `AVCaptureSession` / `AVCaptureMovieFileOutput` | CameraX (`androidx.camera:camera-*`) |
| `AVAssetReader` | `MediaMetadataRetriever` (simple) or Media3 `Transformer` / `MediaExtractor` + `MediaCodec` (streaming) |
| `MediaPipeTasksVision` (SPM/CocoaPods) | `com.google.mediapipe:tasks-vision:1.0.0` |
| `PoseEstimator.swift` | `PoseEstimator.kt` — same single-file ML boundary |
| SwiftData | Room |
| Swift Charts | Compose `Canvas`, or Vico/MPAndroidChart |
| `Canvas` over `AVPlayerLayer` | Compose `Canvas` over Media3 `PlayerView` |
| `PhotosPicker` | Photo Picker (`ActivityResultContracts.PickVisualMedia`) |
| XCTest + fixtures | JUnit + the same fixtures |
| CPU-only inference | GPU delegate available (`useGpu()`) |

Android-specific notes: `preferredTransform` becomes rotation metadata from
`MediaMetadataRetriever`/ExoPlayer; `minSdk 24`; and because a GPU delegate
exists, v2 live mode may run materially better on Android than iOS — measure
both before promising a feature parity date.

## Milestones

**M0 — Environment + performance spike (go/no-go).** Fix `xcode-select`, create
the app target, add MediaPipe via SPM, bundle `pose_landmarker_lite.task`, run
`.image` mode on a single still photo **on a physical device** (the simulator has
no camera and is not representative). Record ms/frame. **Exit criterion: a
measured inference number and a decision on capture fps/clip length.** Do not
proceed to M3 on an unmeasured assumption.

**M1 — AnalysisCore port + Tier 1 parity.** Add `scripts/export_fixtures.py` to
the Python repo, commit the JSON, then port `Geometry`, `LandmarkSmoother`,
`SquatAnalyzer` (incremental), and `ReportModels`. No ML, no camera, no UI.
**Exit criterion: every fixture passes in Swift, plus Swift mirrors of
`test_geometry.py` and `test_smoothing.py`.** This is the highest-value,
lowest-risk milestone and is achievable while still learning SwiftUI.

**M2 — Pose adapter + imported-clip analysis.** `PoseEstimator` (`.video` mode)
and `VideoFrameReader`; run `AnalysisPipeline` over a clip chosen in
`PhotosPicker`; emit `report.json`. **Exit criterion: Tier 2 tolerance parity
against the CLI on the reference clip; flat memory vs clip length verified in
Instruments; orientation handled correctly on a 90°-transform clip.**

**M3 — Capture + persistence + history.** `CameraRecorder`, SwiftData models,
Sessions list, Analyzing progress. **Exit criterion: record → analyze → reopen
the app → session still there.**

**M4 — Annotated playback + charts.** Sidecar storage, `Canvas` overlay synced to
`AVPlayer`, layer toggles, rep scrubber, Swift Charts knee-angle trace.
**Exit criterion: overlay stays registered with the skeleton while scrubbing.**

**M5 — Detail screen, Guidance, Settings, export, TestFlight.**

**M6 (v2) — Live coaching.** `.liveStream` mode + `PoseLandmarkerLiveStreamDelegate`
feeding the same `SquatAnalyzer.process`, with a live HUD and audio/haptic cues
(rep completion, "slow the descent", depth target). Enabled by M1's incremental
design; needs the M0 latency number first.

**M7 — Android port**, from the fixtures and this document.

## Risks & open questions

| Risk | Impact | Mitigation |
| --- | --- | --- |
| CPU-only iOS inference too slow | Analysis feels broken; blocks v2 live mode | M0 spike before any UI work; 720p; lite model; 60 s cap |
| MediaPipe version drift (iOS 1.0.1 vs Android 1.0.0) | Silent behaviour change | Pin exact versions both platforms; re-run Tier 1 + Tier 2 on every bump |
| SPM resolves a ~595 MB repo | Slow first build, disk pressure | Tolerate once; fall back to CocoaPods if it hurts |
| Orientation/transform bugs | Skeleton misaligned with video | Explicit `OrientationMapper` + a dedicated 90°-transform test |
| Overlays drift during scrubbing | Visible jitter, erodes trust | Frame-index lookup keyed on PTS, not on a timer tick |
| Parity assumed rather than tested | Wrong rep counts in production, hard to notice | Tier 1 fixtures in CI from M1 onward |
| Storage growth from retained clips | User-visible disk cost | Per-session delete, Settings storage readout, clip-length cap |
| App Review of fitness claims | Rejection | Descriptive copy only, no medical framing |

**Open questions to settle before M0:**

1. Does the recorded clip stay in the sandbox by default, or is the user offered
   "delete video, keep report" after analysis? (Storage vs. re-watchable
   playback.)
2. Is 60 s the right cap, or should it be rep-count-driven (stop after N reps)?
3. Should the advanced threshold settings ship in v1, or stay hidden until there
   is demand? They are cheap to add and change the analysis contract, so if they
   ship, the fixture suite needs a parameterized variant.
4. iPad support in v1, or iPhone-only? Affects layout work only, not the core.

## Extensibility

Adding an exercise keeps the Python shape: a new file in `AnalysisCore/`
conforming to `ExerciseAnalyzer`, registered in one dictionary, picked up by the
UI's exercise chooser automatically — mirroring how `pipeline.ANALYZERS` drives
the CLI's argparse choices. `PoseEstimator`, `LandmarkSmoother`, `Geometry`,
`VideoFrameReader`, persistence, and playback are all exercise-agnostic and need
no changes.

Front-view faults (valgus, heel lift) become reachable without a new model:
landmarks 29–32 (heel, foot index) are already in the 33-point output and are
simply unused today. They need a front/rear camera angle and their own analyzer —
a v3 concern, and a good reason the MediaPipe runtime was chosen over Apple
Vision.
