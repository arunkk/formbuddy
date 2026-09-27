# FormBuddy iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native iOS SwiftUI app that ports the FormBuddy Python squat analyzer to on-device, with numerical parity proven by fixture tests.

**Architecture:** Streaming pipeline (AVAssetReader → MediaPipe pose → smoother → incremental SquatAnalyzer) that fits in phone memory. Pure-Swift AnalysisCore with no ML dependency, testable via XCTest. SwiftData persistence, Canvas overlay playback, Swift Charts.

**Tech Stack:** Swift 5 mode, iOS 17 target, SwiftUI, AVFoundation, MediaPipe Tasks Vision (SPM), SwiftData, Swift Charts, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-26-formbuddy-ios-design.md`

## Global Constraints

- Swift 5 language mode (`SWIFT_VERSION = 5`), iOS 17.0 deployment target.
- MediaPipe via SPM: `google-ai-edge/mediapipe`, product `MediaPipeTasksVision`, version 1.0.1.
- Model: `pose_landmarker_lite.task` copied from `/Users/arun/Hacks/github/formbuddy/src/formbuddy/assets/pose_landmarker_lite.task`.
- All angles computed in `Double` (upcast from Float32 landmarks before trig).
- Analysis timestamp = `index / fps` (frame index over nominal fps), NOT container PTS. fps fallback: `if fps <= 0 { fps = 30.0 }`.
- MediaPipe timestamp = real presentation timestamp in ms from `CMSampleBufferGetOutput PTS`.
- Thresholds (exact): `STANDING_KNEE_ANGLE=160`, `HYSTERESIS_ANGLE=150`, `RISE_CONFIRM_ANGLE=10`, `DEPTH_ABOVE=100`, `DEPTH_PARALLEL=90`, `EXCESSIVE_LEAN_DEGREES=45`, `MIN_ECCENTRIC_SECONDS=1.0`.
- Depth: `<90` below_parallel, `>100` above_parallel, else parallel.
- Fault strings: `insufficient_depth`, `excessive_forward_lean`, `uncontrolled_descent`, `no_person_in_most_frames`.
- Empty-frame warning: counted at detection level (estimator returned nil), threshold strictly `> 0.2`.
- `select_side`: `>=` comparison, ties break to left.
- No networking code. No OpenCV. No microphone/audio.
- Test video: `/Users/arun/Hacks/github/formbuddy/testdata/IMG_5192.mov` (58.83s, 1080×1920).

## Review Focus

1. **Two clocks conflated** — MediaPipe timestamp vs analysis timestamp must be separate values threaded separately.
2. **Orientation/transform bugs** — skeleton misaligned with video if `preferredTransform` ignored.
3. **Parity assumed rather than tested** — wrong rep counts in production, hard to notice without fixture tests.
4. **Overlay drift during scrubbing** — visible jitter erodes trust; frame-index lookup keyed on PTS.
5. **Empty-frame counting** — must count at detection level, not smoother output (smoother carries forward).

---

### Task 1: Project scaffold + fixture export

**Files:**
- Create: `Package.swift`
- Create: `FormBuddy/FormBuddyApp.swift`
- Create: `FormBuddy/Info.plist`
- Create: `FormBuddy/PrivacyInfo.xcprivacy`
- Create: `scripts/export_fixtures.py` (in Python repo)
- Create: `FormBuddyTests/Fixtures/two_clean_reps.json`
- Create: `FormBuddyTests/Fixtures/parallel_95.json`
- Create: `FormBuddyTests/Fixtures/above_parallel_110.json`
- Create: `FormBuddyTests/Fixtures/excessive_lean.json`
- Create: `FormBuddyTests/Fixtures/uncontrolled_descent.json`
- Create: `FormBuddyTests/Fixtures/partial_rep.json`
- Create: `FormBuddyTests/Fixtures/zero_visibility.json`
- Create: `FormBuddyTests/Fixtures/torso_summary.json`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `Package.swift` with MediaPipe SPM dependency and `FormBuddy` + `FormBuddyTests` targets.
  - `FormBuddyApp.swift` — `@main` struct with `SwiftData.ModelContainer`.
  - Fixture JSON files in `FormBuddyTests/Fixtures/` for Tier 1 parity tests.

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FormBuddy",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/google-ai-edge/mediapipe.git", exact: "1.0.1")
    ],
    targets: [
        .executableTarget(
            name: "FormBuddy",
            dependencies: [
                .product(name: "MediaPipeTasksVision", package: "mediapipe")
            ],
            resources: [.copy("pose_landmarker_lite.task")]
        ),
        .testTarget(
            name: "FormBuddyTests",
            dependencies: ["FormBuddy"],
            resources: [.copy("Fixtures")]
        )
    ]
)
```

- [ ] **Step 2: Copy model asset**

```bash
mkdir -p FormBuddy/Pose
cp /Users/arun/Hacks/github/formbuddy/src/formbuddy/assets/pose_landmarker_lite.task FormBuddy/Pose/
```

- [ ] **Step 3: Create `FormBuddy/FormBuddyApp.swift`**

```swift
import SwiftUI
import SwiftData

@main
struct FormBuddyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Session.self, RepRecord.self])
    }
}
```

- [ ] **Step 4: Create `FormBuddy/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSCameraUsageDescription</key>
    <string>FormBuddy records exercise clips to analyze your form.</string>
    <key>UILaunchScreen</key>
    <dict/>
</dict>
</plist>
```

- [ ] **Step 5: Create `FormBuddy/PrivacyInfo.xcprivacy`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array/>
</dict>
</plist>
```

- [ ] **Step 6: Create `scripts/export_fixtures.py` in the Python repo**

This script reuses `make_frames` and `SquatAnalyzer` from the Python test suite to export JSON fixtures. Each fixture has `name`, `frames` (timestamp + flat 99-float landmark array or null), and `expected` (summary, reps, frame_annotations).

```python
"""Export test fixtures from the Python squat analyzer as JSON for Swift parity tests."""
import json, math, sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).parent.parent / "tests"))
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
```

- [ ] **Step 7: Run fixture export**

```bash
cd /Users/arun/Hacks/github/formbuddy && python scripts/export_fixtures.py
```

Verify: 8 JSON files created in `FormBuddyTests/Fixtures/`.

- [ ] **Step 8: Commit**

```bash
git add Package.swift FormBuddy/ scripts/export_fixtures.py FormBuddyTests/Fixtures/
git commit -m "feat: scaffold iOS project and export parity fixtures"
```

---

### Task 2: Geometry port

**Files:**
- Create: `FormBuddy/AnalysisCore/Geometry.swift`
- Test: `FormBuddyTests/GeometryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `jointAngle(_ a: [Double], _ b: [Double], _ c: [Double]) -> Double` — angle at vertex b, degrees [0,180].
  - `segmentAngleVsVertical(_ top: [Double], _ bottom: [Double]) -> Double` — unsigned degrees from vertical, [0,180].
  - `selectSide(_ landmarks: [Double]) -> Side` — returns `.left` or `.right`, ties break to left.
  - `Side` enum with `.left`, `.right`.
  - `sideLandmarks: [String: [String: Int]]` — left hip/knee/ankle = 23/25/27, right = 24/26/28.

- [ ] **Step 1: Write failing tests in `GeometryTests.swift`**

```swift
import XCTest
@testable import FormBuddy

final class GeometryTests: XCTestCase {
    func testRightAngleAtOrigin() {
        XCTAssertEqual(jointAngle([0,0],[1,0],[1,1]), 90.0, accuracy: 1e-9)
    }
    func testStraightLine() {
        XCTAssertEqual(jointAngle([0,0],[1,0],[2,0]), 180.0, accuracy: 1e-9)
    }
    func testObtuseAngle() {
        XCTAssertEqual(jointAngle([0,0],[1,0],[0,1]), 45.0, accuracy: 1e-9)
    }
    func testUprightSegment() {
        XCTAssertEqual(segmentAngleVsVertical([1,0],[1,1]), 0.0, accuracy: 1e-9)
    }
    func test45DegreeSegment() {
        XCTAssertEqual(segmentAngleVsVertical([1,0],[2,1]), 45.0, accuracy: 1e-9)
    }
    func testSelectLeft() {
        var lm = [Double](repeating: 0, count: 99)
        for i in [23,25,27] { lm[i*3+2] = 1.0 }
        for i in [24,26,28] { lm[i*3+2] = 0.0 }
        XCTAssertEqual(selectSide(lm), .left)
    }
    func testSelectRight() {
        var lm = [Double](repeating: 0, count: 99)
        for i in [23,25,27] { lm[i*3+2] = 0.0 }
        for i in [24,26,28] { lm[i*3+2] = 1.0 }
        XCTAssertEqual(selectSide(lm), .right)
    }
    func testSelectTieBreaksLeft() {
        var lm = [Double](repeating: 0, count: 99)
        for i in [23,25,27,24,26,28] { lm[i*3+2] = 0.5 }
        XCTAssertEqual(selectSide(lm), .left)
    }
}
```

- [ ] **Step 2: Run tests, verify failure**

Run: `swift test --filter GeometryTests` → FAIL (type not found).

- [ ] **Step 3: Implement `Geometry.swift`**

```swift
import Foundation

enum Side: String { case left, right }

let sideLandmarks: [String: [String: Int]] = [
    "left": ["hip": 23, "knee": 25, "ankle": 27],
    "right": ["hip": 24, "knee": 26, "ankle": 28],
]

func jointAngle(_ a: [Double], _ b: [Double], _ c: [Double]) -> Double {
    let ba = [a[0]-b[0], a[1]-b[1]]
    let bc = [c[0]-b[0], c[1]-b[1]]
    let dot = ba[0]*bc[0] + ba[1]*bc[1]
    let normBA = (ba[0]*ba[0] + ba[1]*ba[1]).squareRoot()
    let normBC = (bc[0]*bc[0] + bc[1]*bc[1]).squareRoot()
    var cosAngle = dot / (normBA * normBC)
    cosAngle = max(-1.0, min(1.0, cosAngle))
    return acos(cosAngle) * 180.0 / .pi
}

func segmentAngleVsVertical(_ top: [Double], _ bottom: [Double]) -> Double {
    let dx = bottom[0] - top[0]
    let dy = bottom[1] - top[1]
    var cosAngle = dy / (dx*dx + dy*dy).squareRoot()
    cosAngle = max(-1.0, min(1.0, cosAngle))
    return acos(cosAngle) * 180.0 / .pi
}

func selectSide(_ landmarks: [Double]) -> Side {
    let leftIds = [23, 25, 27]
    let rightIds = [24, 26, 28]
    let leftVis = leftIds.map { landmarks[$0*3+2] }.reduce(0,+) / 3.0
    let rightVis = rightIds.map { landmarks[$0*3+2] }.reduce(0,+) / 3.0
    return leftVis >= rightVis ? .left : .right
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter GeometryTests` → PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add FormBuddy/AnalysisCore/Geometry.swift FormBuddyTests/GeometryTests.swift
git commit -m "feat: port geometry primitives to Swift"
```

---

### Task 3: LandmarkSmoother port

**Files:**
- Create: `FormBuddy/AnalysisCore/LandmarkSmoother.swift`
- Test: `FormBuddyTests/SmoothingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `LandmarkSmoother` class with `alpha: Double = 0.5`, `update(_ landmarks: [Double]?) -> [Double]?` — per-coordinate EMA on visible landmarks (visibility >= 0.5), carry forward when nil, return nil until first detection.

- [ ] **Step 1: Write failing tests in `SmoothingTests.swift`**

```swift
import XCTest
@testable import FormBuddy

final class SmoothingTests: XCTestCase {
    func makeFrame(offset: Double, visibility: Double = 1.0) -> [Double] {
        var lm = [Double](repeating: 0, count: 99)
        for i in 0..<33 {
            lm[i*3] = Double(i) * 0.01 + offset
            lm[i*3+1] = 0.5
            lm[i*3+2] = visibility
        }
        return lm
    }
    
    func testReturnsNilUntilFirstDetection() {
        let s = LandmarkSmoother()
        XCTAssertNil(s.update(nil))
        XCTAssertNil(s.update(nil))
    }
    func testFirstDetectionPassesThrough() {
        let s = LandmarkSmoother(alpha: 0.5)
        let out = s.update(makeFrame(offset: 0.0))
        XCTAssertEqual(out, makeFrame(offset: 0.0))
    }
    func testMissingDetectionCarriesForward() {
        let s = LandmarkSmoother(alpha: 0.5)
        _ = s.update(makeFrame(offset: 0.0))
        let afterSecond = s.update(makeFrame(offset: 0.1))
        let carried = s.update(nil)
        XCTAssertEqual(carried, afterSecond)
    }
    func testEMABetweenInputs() {
        let s = LandmarkSmoother(alpha: 0.5)
        _ = s.update(makeFrame(offset: 0.0))
        let out = s.update(makeFrame(offset: 0.1))
        XCTAssertGreaterThan(out![0], 0.0)
        XCTAssertLessThan(out![0], 0.1)
        XCTAssertEqual(out![0], 0.05, accuracy: 1e-9)
    }
    func testInvisibleLandmarksCarryForward() {
        let s = LandmarkSmoother(alpha: 0.5)
        _ = s.update(makeFrame(offset: 0.0))
        var moved = makeFrame(offset: 0.1)
        moved[5*3] = 0.9; moved[5*3+1] = 0.9; moved[5*3+2] = 0.2
        let out = s.update(moved)
        XCTAssertEqual(out![5*3], makeFrame(offset: 0.0)[5*3], accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run tests, verify failure**

Run: `swift test --filter SmoothingTests` → FAIL.

- [ ] **Step 3: Implement `LandmarkSmoother.swift`**

```swift
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
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test --filter SmoothingTests` → PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add FormBuddy/AnalysisCore/LandmarkSmoother.swift FormBuddyTests/SmoothingTests.swift
git commit -m "feat: port landmark smoother to Swift"
```

---

### Task 4: SquatAnalyzer port (incremental)

**Files:**
- Create: `FormBuddy/AnalysisCore/PoseFrame.swift`
- Create: `FormBuddy/AnalysisCore/ExerciseAnalyzer.swift`
- Create: `FormBuddy/AnalysisCore/ReportModels.swift`
- Create: `FormBuddy/AnalysisCore/SquatAnalyzer.swift`
- Test: `FormBuddyTests/SquatAnalyzerTests.swift`

**Interfaces:**
- Consumes: `jointAngle`, `segmentAngleVsVertical`, `selectSide`, `sideLandmarks` (Task 2).
- Produces:
  - `PoseFrame` struct: `landmarks: [Double]?`, `timestamp: Double`.
  - `FrameAnnotation` struct: `kneeAngle: Double?`, `torsoAngle: Double?`, `phase: String`, `repCount: Int`, `faults: [String]`.
  - `RepResult` struct: `repNumber`, `depth`, `bottomKneeAngle`, `torsoAngleAtBottom`, `eccentricSeconds`, `concentricSeconds`, `bottomPauseSeconds`, `faults`, `partial`.
  - `SquatSummary` struct: `totalReps`, `partialReps`, `repsBelowParallel`, `repsAtParallel`, `repsAboveParallel`, `avgEccentricSeconds`, `avgConcentricSeconds`, `avgBottomPauseSeconds`, `avgTorsoAngleAtBottom`, `maxTorsoAngle`.
  - `SquatReport` struct: `exercise`, `warnings`, `videoMeta`, `reps`, `summary`, `frames`.
  - `SquatAnalyzer` class: `process(_ frame: PoseFrame) -> FrameAnnotation`, `finish() -> SquatReport`, `analyze(_ frames: [PoseFrame]) -> SquatReport`.

- [ ] **Step 1: Write failing tests in `SquatAnalyzerTests.swift`**

Mirror the Python test_squat.py tests: two clean reps, parallel at 95, above parallel at 110, excessive lean, uncontrolled descent, partial rep, zero visibility, torso summary, frame annotations.

- [ ] **Step 2: Run tests, verify failure**

Run: `swift test --filter SquatAnalyzerTests` → FAIL.

- [ ] **Step 3: Implement `PoseFrame.swift`**

```swift
import Foundation

struct PoseFrame {
    let landmarks: [Double]?
    let timestamp: Double
}
```

- [ ] **Step 4: Implement `ExerciseAnalyzer.swift`**

```swift
import Foundation

protocol ExerciseAnalyzer {
    func process(_ frame: PoseFrame) -> FrameAnnotation
    func finish() -> SquatReport
}
```

- [ ] **Step 5: Implement `ReportModels.swift`**

```swift
import Foundation

struct FrameAnnotation {
    var kneeAngle: Double?
    var torsoAngle: Double?
    var phase: String
    var repCount: Int
    var faults: [String] = []
}

struct RepResult {
    var repNumber: Int
    var depth: String
    var bottomKneeAngle: Double
    var torsoAngleAtBottom: Double
    var eccentricSeconds: Double
    var concentricSeconds: Double
    var bottomPauseSeconds: Double
    var faults: [String] = []
    var partial: Bool = false
}

struct SquatSummary {
    var totalReps: Int = 0
    var partialReps: Int = 0
    var repsBelowParallel: Int = 0
    var repsAtParallel: Int = 0
    var repsAboveParallel: Int = 0
    var avgEccentricSeconds: Double = 0
    var avgConcentricSeconds: Double = 0
    var avgBottomPauseSeconds: Double = 0
    var avgTorsoAngleAtBottom: Double = 0
    var maxTorsoAngle: Double = 0
}

struct SquatReport {
    var exercise: String = "squat"
    var warnings: [String] = []
    var videoMeta: [String: Any] = [:]
    var reps: [RepResult] = []
    var summary: SquatSummary = SquatSummary()
    var frames: [FrameAnnotation] = []
}
```

- [ ] **Step 6: Implement `SquatAnalyzer.swift`**

Port the Python state machine exactly. Key constants: `STANDING_KNEE_ANGLE=160`, `HYSTERESIS_ANGLE=150`, `RISE_CONFIRM_ANGLE=10`, `DEPTH_ABOVE=100`, `DEPTH_PARALLEL=90`, `EXCESSIVE_LEAN_DEGREES=45`, `MIN_ECCENTRIC_SECONDS=1.0`. Shoulder indices: left=11, right=12. Min side visibility: 0.5.

- [ ] **Step 7: Run tests, verify pass**

Run: `swift test --filter SquatAnalyzerTests` → PASS (all tests).

- [ ] **Step 8: Commit**

```bash
git add FormBuddy/AnalysisCore/ FormBuddyTests/SquatAnalyzerTests.swift
git commit -m "feat: port squat analyzer to Swift (incremental)"
```

---

### Task 5: Fixture parity tests

**Files:**
- Create: `FormBuddyTests/FixtureParityTests.swift`

**Interfaces:**
- Consumes: `SquatAnalyzer` (Task 4), fixture JSON files (Task 1).
- Produces: Tier 1 parity test suite.

- [ ] **Step 1: Write `FixtureParityTests.swift`**

Load each JSON fixture, feed frames through `SquatAnalyzer.analyze`, assert summary fields within 1e-9, rep count/depth/faults/partial exact, frame annotations match.

- [ ] **Step 2: Run tests, verify pass**

Run: `swift test --filter FixtureParityTests` → PASS (8 fixtures).

- [ ] **Step 3: Commit**

```bash
git add FormBuddyTests/FixtureParityTests.swift
git commit -m "test: add Tier 1 fixture parity tests"
```

---

### Task 6: PoseEstimator (MediaPipe adapter)

**Files:**
- Create: `FormBuddy/Pose/PoseEstimator.swift`

**Interfaces:**
- Consumes: `pose_landmarker_lite.task` model asset.
- Produces:
  - `PoseEstimator` class: `process(pixelBuffer: CVPixelBuffer, timestampMs: Int64) -> [Double]?` — returns flat 99-float array or nil.

- [ ] **Step 1: Implement `PoseEstimator.swift`**

```swift
import Foundation
import MediaPipeTasksVision
import CoreVideo

final class PoseEstimator {
    private let landmarker: PoseLandmarker
    
    init?() {
        guard let modelPath = Bundle.main.url(forResource: "pose_landmarker_lite", withExtension: "task") else {
            return nil
        }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath.path
        options.runningMode = .video
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minTrackingConfidence = 0.5
        do {
            landmarker = try PoseLandmarker(options: options)
        } catch {
            return nil
        }
    }
    
    func process(pixelBuffer: CVPixelBuffer, timestampMs: Int64) -> [Double]? {
        let image = MPImage(pixelBuffer: pixelBuffer)
        do {
            let result = try landmarker.detect(videoFrame: image, timestampInMilliseconds: timestampMs)
            guard let landmarks = result.poseLandmarks.first, !landmarks.isEmpty else { return nil }
            var flat = [Double](repeating: 0, count: 99)
            for (i, lm) in landmarks.enumerated() {
                flat[i*3] = Double(lm.x)
                flat[i*3+1] = Double(lm.y)
                flat[i*3+2] = Double(lm.visibility)
            }
            return flat
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add FormBuddy/Pose/PoseEstimator.swift
git commit -m "feat: add MediaPipe pose estimator adapter"
```

---

### Task 7: VideoFrameReader + OrientationMapper

**Files:**
- Create: `FormBuddy/Video/VideoFrameReader.swift`
- Create: `FormBuddy/Video/OrientationMapper.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `VideoFrameReader` class: `frames(url: URL) -> AsyncThrowingStream<(CVPixelBuffer, Double), Error>` — yields pixel buffers one at a time with presentation timestamps.
  - `OrientationMapper` struct: `transform(for track: AVAssetTrack) -> CGAffineTransform`, `map(point: CGPoint, transform: CGAffineTransform, size: CGSize) -> CGPoint`.

- [ ] **Step 1: Implement `VideoFrameReader.swift`**

Use `AVAssetReader` + `AVAssetReaderTrackOutput` for sequential frame-by-frame `CVPixelBuffer` delivery.

- [ ] **Step 2: Implement `OrientationMapper.swift`**

Read `preferredTransform` from track, provide mapping from normalized landmark coordinates to view space.

- [ ] **Step 3: Commit**

```bash
git add FormBuddy/Video/
git commit -m "feat: add video frame reader and orientation mapper"
```

---

### Task 8: AnalysisPipeline

**Files:**
- Create: `FormBuddy/Pipeline/AnalysisPipeline.swift`

**Interfaces:**
- Consumes: `PoseEstimator` (Task 6), `LandmarkSmoother` (Task 3), `SquatAnalyzer` (Task 4), `VideoFrameReader` (Task 7).
- Produces:
  - `AnalysisPipeline` class: `analyze(videoAt url: URL) async throws -> SquatReport` — streaming, cancellable, progress reporting.

- [ ] **Step 1: Implement `AnalysisPipeline.swift`**

```swift
import Foundation
import AVFoundation
import CoreVideo
import Observation

@Observable
final class AnalysisPipeline {
    private(set) var progress: Double = 0
    
    func analyze(videoAt url: URL) async throws -> SquatReport {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let fps = try await track.load(.nominalFrameRate)
        let fps = fps > 0 ? fps : 30.0
        
        let estimator = PoseEstimator()!
        let smoother = LandmarkSmoother()
        let analyzer = SquatAnalyzer()
        
        var emptyFrames = 0
        var totalFrames = 0
        
        let reader = VideoFrameReader(url: url)
        for try await (pixelBuffer, pts) in reader.frames() {
            totalFrames += 1
            let timestampMs = Int64(pts * 1000)
            let detected = estimator.process(pixelBuffer: pixelBuffer, timestampMs: timestampMs)
            if detected == nil { emptyFrames += 1 }
            let smoothed = smoother.update(detected)
            let frame = PoseFrame(landmarks: smoothed, timestamp: Double(totalFrames-1) / fps)
            _ = analyzer.process(frame)
            progress = Double(totalFrames) / Double(totalFrames) // update with actual count
        }
        
        var report = analyzer.finish()
        report.videoMeta = ["fps": fps, "frame_count": totalFrames, "duration": Double(totalFrames) / fps]
        if totalFrames > 0 && Double(emptyFrames) / Double(totalFrames) > 0.2 {
            report.warnings.append("no_person_in_most_frames")
        }
        return report
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add FormBuddy/Pipeline/AnalysisPipeline.swift
git commit -m "feat: add streaming analysis pipeline"
```

---

### Task 9: SwiftData models + persistence

**Files:**
- Create: `FormBuddy/Persistence/Session.swift`
- Create: `FormBuddy/Persistence/RepRecord.swift`
- Create: `FormBuddy/Persistence/AnnotationStore.swift`
- Create: `FormBuddy/Persistence/ReportJSONEncoder.swift`

**Interfaces:**
- Consumes: `SquatReport` (Task 4).
- Produces:
  - `Session` @Model: id, exercise, createdAt, videoFilename, orientationTransform, fps, frameCount, duration, warnings, summary, annotationFilename, reps.
  - `RepRecord` @Model: repNumber, depth, bottomKneeAngle, torsoAngleAtBottom, eccentricSeconds, concentricSeconds, bottomPauseSeconds, faults, partial, session.
  - `AnnotationStore`: save/load per-frame annotation sidecar.
  - `ReportJSONEncoder`: encode SquatReport to schema-identical JSON.

- [ ] **Step 1: Implement `Session.swift` and `RepRecord.swift`**

- [ ] **Step 2: Implement `AnnotationStore.swift`**

- [ ] **Step 3: Implement `ReportJSONEncoder.swift`**

- [ ] **Step 4: Commit**

```bash
git add FormBuddy/Persistence/
git commit -m "feat: add SwiftData models and persistence"
```

---

### Task 10: CameraRecorder

**Files:**
- Create: `FormBuddy/Video/CameraRecorder.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `CameraRecorder` class: `startRecording()`, `stopRecording() async -> URL?` — AVCaptureSession + AVCaptureMovieFileOutput, 720p30, no audio.

- [ ] **Step 1: Implement `CameraRecorder.swift`**

- [ ] **Step 2: Commit**

```bash
git add FormBuddy/Video/CameraRecorder.swift
git commit -m "feat: add camera recorder"
```

---

### Task 11: UI — SessionListView + CaptureView + AnalyzingView

**Files:**
- Create: `FormBuddy/UI/SessionListView.swift`
- Create: `FormBuddy/UI/CaptureView.swift`
- Create: `FormBuddy/UI/AnalyzingView.swift`
- Create: `FormBuddy/UI/RootView.swift`

**Interfaces:**
- Consumes: `Session` @Model (Task 9), `AnalysisPipeline` (Task 8), `CameraRecorder` (Task 10).
- Produces: Sessions list, capture screen with camera preview, analyzing progress screen.

- [ ] **Step 1: Implement `SessionListView.swift`**

- [ ] **Step 2: Implement `CaptureView.swift`**

- [ ] **Step 3: Implement `AnalyzingView.swift`**

- [ ] **Step 4: Implement `RootView.swift`**

- [ ] **Step 5: Commit**

```bash
git add FormBuddy/UI/
git commit -m "feat: add main UI screens"
```

---

### Task 12: UI — SessionDetailView + AnnotatedPlaybackView + KneeAngleChart

**Files:**
- Create: `FormBuddy/UI/SessionDetailView.swift`
- Create: `FormBuddy/UI/AnnotatedPlaybackView.swift`
- Create: `FormBuddy/UI/KneeAngleChart.swift`

**Interfaces:**
- Consumes: `Session`, `RepRecord`, `AnnotationStore` (Task 9).
- Produces: Detail screen with summary cards, rep list, annotated playback with Canvas overlay, knee-angle chart.

- [ ] **Step 1: Implement `KneeAngleChart.swift`**

- [ ] **Step 2: Implement `AnnotatedPlaybackView.swift`**

- [ ] **Step 3: Implement `SessionDetailView.swift`**

- [ ] **Step 4: Commit**

```bash
git add FormBuddy/UI/
git commit -m "feat: add session detail, playback, and chart views"
```

---

### Task 13: UI — GuidanceView + SettingsView

**Files:**
- Create: `FormBuddy/UI/GuidanceView.swift`
- Create: `FormBuddy/UI/SettingsView.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: Guidance screen with filming instructions, settings screen with storage/export/thresholds.

- [ ] **Step 1: Implement `GuidanceView.swift`**

- [ ] **Step 2: Implement `SettingsView.swift`**

- [ ] **Step 3: Commit**

```bash
git add FormBuddy/UI/
git commit -m "feat: add guidance and settings views"
```

---

### Task 14: Build + simulator verification

**Files:**
- No new files.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: Working app on iOS simulator.

- [ ] **Step 1: Build the app**

```bash
cd /Users/arun/orca/workspaces/formbuddy/mobile_app_ios
swift build
```

- [ ] **Step 2: Run all tests**

```bash
swift test
```

Verify: all tests pass (Geometry, Smoothing, SquatAnalyzer, FixtureParity).

- [ ] **Step 3: Launch simulator and install**

```bash
xcrun simctl boot "iPhone 18 Pro" 2>/dev/null || true
swift build -c release
# Use xcodebuild or swift run to install on simulator
```

- [ ] **Step 4: Verify app launches**

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: address build and simulator issues"
```

---

### Task 15: End-to-end verification with test video

**Files:**
- No new files.

**Interfaces:**
- Consumes: test video at `/Users/arun/Hacks/github/formbuddy/testdata/IMG_5192.mov`.
- Produces: Verified analysis results.

- [ ] **Step 1: Copy test video to simulator**

```bash
xcrun simctl boot "iPhone 18 Pro" 2>/dev/null || true
xcrun simctl addmedia "iPhone 18 Pro" /Users/arun/Hacks/github/formbuddy/testdata/IMG_5192.mov
```

- [ ] **Step 2: Run analysis on test video**

Either through the app UI (import from Photos) or via a test harness. Verify rep count, depth classification, and faults match the Python CLI output.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: address end-to-end verification issues"
```
