# FormBuddy Squat Analyzer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Python CLI that analyzes back-squat form from a side-view recorded video, producing an annotated video and a JSON/text form report.

**Architecture:** Pipeline of OpenCV video I/O → MediaPipe pose estimation → temporal smoothing → pluggable exercise analyzers → report + annotated video. All thresholds and biomechanical rules come from the approved spec; new exercises plug in via the `ExerciseAnalyzer` interface.

**Tech Stack:** Python 3.10+, mediapipe, opencv-python, numpy, pytest.

**Spec:** `docs/superpowers/specs/2026-09-26-formbuddy-squat-design.md`

## Global Constraints

- Python >= 3.10; dependencies are exactly `mediapipe`, `opencv-python`, `numpy` (no torch, no GPU).
- Landmarks are stored normalized `(x, y, visibility)` with MediaPipe Pose indices; analysis picks the side (left/right) with higher mean visibility of hip/knee/ankle.
- Spec thresholds (exact values): standing knee angle >160°; hysteresis enter/exit at 150°; rise-confirm at minimum+10°; depth categories >100° above parallel, 90–100° parallel, <90° below parallel; excessive forward lean >45° torso-from-vertical at bottom; uncontrolled descent eccentric <1s; empty-frame warning if >20% of frames have no person.
- CLI flags: `--input` (required), `--exercise` (default `squat`), `--output-dir` (default `./out`), `--no-video`.
- Every task ends with tests passing and a commit.

## Review Focus

1. **No person in the video at all** → pipeline must still produce a report with zero reps and a warning, exit 0 — not crash.
2. **Key landmarks occluded/low visibility** → frame excluded from metrics; warn if many frames excluded.
3. **Multiple people in frame** → MediaPipe returns the most prominent person; documented limitation, no crash.
4. **Clip starts mid-movement or ends mid-rep** → partial rep counted and flagged, not silently dropped.
5. **Corrupt/unreadable video file** → clear CLI error message, non-zero exit.

---

### Task 1: Project scaffold + geometry primitives

**Files:**
- Create: `pyproject.toml`, `src/formbuddy/__init__.py`, `src/formbuddy/geometry.py`
- Test: `tests/test_geometry.py`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `joint_angle(a, b, c) -> float` — angle at vertex `b` formed by points a-b-c, degrees in [0,180]; points are array-like `(x, y)`.
  - `segment_angle_vs_vertical(top, bottom) -> float` — unsigned degrees of the segment vs an upright vertical line, `[0,180]`; `top` is the higher point (e.g. shoulder), `bottom` the lower (e.g. hip).
  - `select_side(landmarks) -> str` — `"left"` or `"right"`; mean visibility of hip/knee/ankle (indices 23,25,27 left; 24,26,28 right) decides.
  - `SIDE_LANDMARKS = {"left": {"hip": 23, "knee": 25, "ankle": 27}, "right": {"hip": 24, "knee": 26, "ankle": 28}}` — used by Task 2.

- [ ] **Step 1: Write failing tests** in `tests/test_geometry.py`:
  - `joint_angle((0,0),(1,0),(1,1)) == 90.0`; `joint_angle((0,0),(1,0),(2,0)) == 180.0`; `joint_angle((0,0),(1,0),(0,1))` ≈ 90.0.
  - `segment_angle_vs_vertical((1,0),(1,1)) == 0.0` (upright); `segment_angle_vs_vertical((1,0),(2,1)) == 45.0`.
  - `select_side` on a synthetic (33,3) zeros array with left-side visibility=1, right=0 → `"left"`; reversed → `"right"`; equal → `"left"` (tie-break).
- [ ] **Step 2: Run tests, verify failure** — `python -m pytest tests/test_geometry.py -v` → FAIL (module missing).
- [ ] **Step 3: Scaffold** — create `pyproject.toml` (name `formbuddy`, dependencies `mediapipe`, `opencv-python`, `numpy`, optional dev `pytest`; `[project.scripts] formbuddy = "formbuddy.cli:main"`), empty `src/formbuddy/__init__.py`. Implement `geometry.py` functions and `SIDE_LANDMARKS` per signatures above.
- [ ] **Step 4: Run tests, verify pass** — `python -m pytest tests/test_geometry.py -v` → PASS (use `pytest.approx` for floats).
- [ ] **Step 5: Commit** — `git add pyproject.toml src tests && git commit -m "feat: scaffold project and geometry primitives"`.

---

### Task 2: Analyzer interface + squat analyzer

**Files:**
- Create: `src/formbuddy/analyzers/__init__.py`, `src/formbuddy/analyzers/base.py`, `src/formbuddy/analyzers/squat.py`
- Test: `tests/test_squat.py`

**Interfaces:**
- Consumes: `geometry.joint_angle`, `geometry.segment_angle_vs_vertical`, `geometry.select_side`, `SIDE_LANDMARKS` (Task 1).
- Produces:
  - `Frame` dataclass: `landmarks: np.ndarray` (33,3), `timestamp: float` seconds.
  - `ExerciseReport` dataclass: `exercise: str`, `warnings: list[str]`, `video_meta: dict`.
  - `ExerciseAnalyzer` ABC: `analyze(frames: list[Frame]) -> ExerciseReport`.
  - `SquatReport(ExerciseReport)`: adds `reps: list[RepResult]`, `summary: SquatSummary`, `frames: list[FrameAnnotation]`.
  - `RepResult`: `rep_number: int`, `depth: str` (`"above_parallel"|"parallel"|"below_parallel"`), `bottom_knee_angle: float`, `torso_angle_at_bottom: float`, `eccentric_seconds: float`, `concentric_seconds: float`, `bottom_pause_seconds: float`, `faults: list[str]`, `partial: bool`.
  - `SquatSummary`: `total_reps: int`, `partial_reps: int`, `reps_below_parallel: int`, `reps_at_parallel: int`, `reps_above_parallel: int`, `avg_eccentric_seconds: float`, `avg_concentric_seconds: float`, `avg_bottom_pause_seconds: float`.
  - `FrameAnnotation`: `knee_angle: float|None`, `torso_angle: float|None`, `phase: str`, `rep_count: int`, `faults: list[str]`.
  - `SquatAnalyzer(ExerciseAnalyzer)` with module constants: `STANDING_KNEE_ANGLE=160`, `HYSTERESIS_ANGLE=150`, `RISE_CONFIRM_ANGLE=10`, `DEPTH_ABOVE=100`, `DEPTH_PARALLEL=90`, `EXCESSIVE_LEAN_DEGREES=45`, `MIN_ECCENTRIC_SECONDS=1.0`.

- [ ] **Step 1: Write failing tests** in `tests/test_squat.py` using a helper `make_frames(angles, torso_angles, dt=0.1, visibility_side="left")` building `Frame`s from synthetic landmark arrays where the knee angle is realized by placing hip/knee/ankle (left indices) accordingly, shoulder placed for the torso angle, all with visibility 1.0.
  - Two clean reps (170°→80°→170°, 10 fps, 2s each) → `total_reps == 2`, both `depth == "below_parallel"`, no faults, `partial_reps == 0`.
  - Rep bottoming at 95° → `depth == "parallel"`; at 110° → `"above_parallel"` and fault `"insufficient_depth"`.
  - Torso 50° at bottom → fault `"excessive_forward_lean"`.
  - Eccentric phase of 0.5s → fault `"uncontrolled_descent"`.
  - Clip ending mid-rep → that rep has `partial == True` and is counted in `partial_reps`.
  - `FrameAnnotation` list length equals input frame count; `phase` values come from `{standing, descending, ascending}`.
  - Frames with all-zero visibility → zero reps computed, no crash (frames excluded from metrics).
- [ ] **Step 2: Run tests, verify failure** — `python -m pytest tests/test_squat.py -v` → FAIL (modules missing).
- [ ] **Step 3: Implement `analyzers/base.py`** (dataclasses + ABC) and **`analyzers/squat.py`**: per frame, resolve side via `select_side` (skip frame if both sides' mean visibility < 0.5 — count as empty); compute knee and torso angles; run the state machine `standing → descending → ascending → standing` on knee angle with the hysteresis constants; at rep completion compute depth from bottom knee angle, faults from spec thresholds, and timings from timestamps; build `FrameAnnotation` per frame (phase, angles, current rep count, active faults: `"excessive_forward_lean"` when torso >45°); end-of-clip: if state != standing, close a partial rep.
- [ ] **Step 4: Run tests, verify pass** — `python -m pytest tests/test_squat.py -v` → PASS.
- [ ] **Step 5: Commit** — `git add src/formbuddy/analyzers tests/test_squat.py && git commit -m "feat: add squat form analyzer"`.

---

### Task 3: Pose estimation + landmark smoothing

**Files:**
- Create: `src/formbuddy/pose.py`, `src/formbuddy/smoothing.py`
- Test: `tests/test_pose.py`, `tests/test_smoothing.py`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `PoseEstimator(min_detection_confidence=0.5, min_tracking_confidence=0.5)` with `process(bgr_frame: np.ndarray) -> np.ndarray | None` returning (33,3) normalized `(x, y, visibility)` or None.
  - `LandmarkSmoother(alpha=0.5)` with `update(landmarks: np.ndarray | None) -> np.ndarray | None` — per-coordinate EMA on visible landmarks (visibility >= 0.5); invisible coordinates carry forward last smoothed value; returns None if never seen a detection.

- [ ] **Step 1: Write failing tests**:
  - `tests/test_pose.py`: `PoseEstimator().process(np.zeros((240, 320, 3), dtype=np.uint8)) is None` (blank frame → no person). Constructor accepts the two confidence kwargs.
  - `tests/test_smoothing.py`: feed `[None, frame0, frame1, None]`; output length matches input; None positions return None when nothing seen yet, then carry-forward values after a detection; EMA output is between consecutive inputs for a moving coordinate.
- [ ] **Step 2: Run tests, verify failure** — `python -m pytest tests/test_pose.py tests/test_smoothing.py -v` → FAIL.
- [ ] **Step 3: Implement** — `pose.py` wraps `mediapipe.solutions.pose.Pose` (keep the solution instance alive for the estimator's lifetime), converts BGR→RGB, returns `results.pose_landmarks.landmark` mapped to (33,3) or None. `smoothing.py` implements the EMA filter exactly as specified in Produces.
- [ ] **Step 4: Run tests, verify pass** — `python -m pytest tests/test_pose.py tests/test_smoothing.py -v` → PASS.
- [ ] **Step 5: Commit** — `git add src/formbuddy/pose.py src/formbuddy/smoothing.py tests/test_pose.py tests/test_smoothing.py && git commit -m "feat: add pose estimation and landmark smoothing"`.

---

### Task 4: Video annotation

**Files:**
- Create: `src/formbuddy/annotate.py`
- Test: `tests/test_annotate.py`

**Interfaces:**
- Consumes: `analyzers.base.FrameAnnotation` (Task 2), normalized landmarks (Task 3 contract).
- Produces:
  - `annotate_frame(bgr_frame: np.ndarray, landmarks: np.ndarray | None, ann: FrameAnnotation) -> np.ndarray` — draws the MediaPipe pose skeleton (via `mediapipe.solutions.drawing_utils.draw_landmarks` with `mp.solutions.pose.POSE_CONNECTIONS`), then a HUD via `cv2.putText`: knee angle, torso angle, phase, rep count, and active faults (red).
  - `VideoWriter(path: str, fps: float, frame_size: tuple[int,int])` with `write(frame)` and `close()` — wraps `cv2.VideoWriter` with mp4v codec.

- [ ] **Step 1: Write failing tests** in `tests/test_annotate.py`:
  - `annotate_frame` on a blank frame returns a frame of the same shape with non-zero pixels (something was drawn) when landmarks + a `FrameAnnotation(knee_angle=90, torso_angle=10, phase="descending", rep_count=1, faults=[])` are passed; returns frame unchanged (still all-zero) when landmarks is None.
  - `VideoWriter` writes 3 frames to a tmp mp4; file exists and has non-zero size (use `tmp_path` fixture).
- [ ] **Step 2: Run tests, verify failure** — `python -m pytest tests/test_annotate.py -v` → FAIL.
- [ ] **Step 3: Implement `annotate.py`** per Produces.
- [ ] **Step 4: Run tests, verify pass** — `python -m pytest tests/test_annotate.py -v` → PASS.
- [ ] **Step 5: Commit** — `git add src/formbuddy/annotate.py tests/test_annotate.py && git commit -m "feat: add annotated video writer"`.

---

### Task 5: Report builder

**Files:**
- Create: `src/formbuddy/report.py`
- Test: `tests/test_report.py`

**Interfaces:**
- Consumes: `analyzers.squat.SquatReport` (Task 2).
- Produces:
  - `ReportBuilder().build(report: SquatReport, out_dir: str) -> dict` — writes `report.json` and `report.txt` into `out_dir` (creates it), returns the JSON dict.
  - JSON shape: `{"exercise", "video_meta", "summary": {...SquatSummary fields...}, "reps": [RepResult fields...], "warnings"}`.
  - Text shape: one header line, summary lines, then one line per rep: `#n depth=X ecc=es conc=es pause=fs faults=[...] partial=bool`.

- [ ] **Step 1: Write failing tests** in `tests/test_report.py`: build a `SquatReport` with two reps (one below parallel, one partial above parallel with a fault), call `build(tmp_path)`; assert both files exist; assert JSON has `exercise == "squat"`, `summary["total_reps"] == 2`, `summary["partial_reps"] == 1`, `len(json["reps"]) == 2`; assert the text contains `#1` and `#2` and the fault string.
- [ ] **Step 2: Run tests, verify failure** — `python -m pytest tests/test_report.py -v` → FAIL.
- [ ] **Step 3: Implement `report.py`** per Produces (use `dataclasses.asdict`).
- [ ] **Step 4: Run tests, verify pass** — `python -m pytest tests/test_report.py -v` → PASS.
- [ ] **Step 5: Commit** — `git add src/formbuddy/report.py tests/test_report.py && git commit -m "feat: add report builder"`.

---

### Task 6: Pipeline orchestration

**Files:**
- Create: `src/formbuddy/pipeline.py`
- Test: `tests/test_pipeline.py`

**Interfaces:**
- Consumes: `PoseEstimator`, `LandmarkSmoother` (Task 3), `SquatAnalyzer` (Task 2), `ReportBuilder` (Task 5), `annotate_frame`/`VideoWriter` (Task 4), `Frame` (Task 2).
- Produces:
  - `run(input_path: str, exercise: str = "squat", output_dir: str = "./out", write_video: bool = True, estimator: PoseEstimator | None = None) -> ExerciseReport` — opens the video with OpenCV (raise `FileNotFoundError` with the path in the message if `cv2.VideoCapture` cannot open it), reads fps, loops frames: `estimator.process` → `smoother.update` → `Frame(landmarks, timestamp=i/fps)`; computes `empty_frame_ratio` (smoother returned None); if ratio > 0.2 appends warning `"no_person_in_most_frames"`; runs the analyzer; writes report and (optionally) annotated video `output_dir/<stem>_annotated.mp4`.

- [ ] **Step 1: Write failing tests** in `tests/test_pipeline.py` with a `FakeEstimator` class exposing `process(bgr)` returning synthetic landmarks that realize a 2-rep knee-angle trajectory (same construction as Task 2's helper, right side visible):
  - `run(str(video_path), estimator=FakeEstimator(), output_dir=str(tmp))` on a real tiny mp4 (generated in-test with `cv2.VideoWriter`, 30 frames of noise) → returns `SquatReport` with `total_reps == 2`; `report.json` exists; annotated mp4 exists when `write_video=True` and does not when `False`.
  - `run` on a non-existent path raises `FileNotFoundError`.
  - A `FakeEstimator` returning None always → report has `total_reps == 0` and warning `"no_person_in_most_frames"`.
- [ ] **Step 2: Run tests, verify failure** — `python -m pytest tests/test_pipeline.py -v` → FAIL.
- [ ] **Step 3: Implement `pipeline.py`** per Produces. Keep decoded frames in memory for the annotation pass (short clips; YAGNI — no streaming two-pass).
- [ ] **Step 4: Run tests, verify pass** — `python -m pytest tests/test_pipeline.py -v` → PASS.
- [ ] **Step 5: Commit** — `git add src/formbuddy/pipeline.py tests/test_pipeline.py && git commit -m "feat: add analysis pipeline"`.

---

### Task 7: CLI + package entry + README

**Files:**
- Create: `src/formbuddy/cli.py`, `src/formbuddy/__main__.py`, `README.md`
- Test: `tests/test_cli.py`

**Interfaces:**
- Consumes: `pipeline.run` (Task 6), `SquatAnalyzer` (Task 2).
- Produces:
  - `main(argv: list[str] | None = None) -> int` — argparse with flags from Global Constraints; `ANALYZERS = {"squat": SquatAnalyzer}`; unsupported exercise → stderr message + exit 2; missing/unreadable input → stderr message + exit 1; success → prints one-line summary (`reps=N below_parallel=M`) and returns 0.
  - `__main__.py` calls `sys.exit(main())`.

- [ ] **Step 1: Write failing tests** in `tests/test_cli.py`: `main(["--help"])` raises `SystemExit` with code 0; `main(["--input", "/nonexistent.mp4"])` returns 1; `main(["--input", "x.mp4", "--exercise", "deadlift"])` returns 2.
- [ ] **Step 2: Run tests, verify failure** — `python -m pytest tests/test_cli.py -v` → FAIL.
- [ ] **Step 3: Implement `cli.py` + `__main__.py`** per Produces, wiring `SquatAnalyzer()` as the default estimator factory into `run`.
- [ ] **Step 4: Run tests, verify pass** — `python -m pytest tests/test_cli.py -v` → PASS.
- [ ] **Step 5: Write `README.md`** — install (`pip install -e .`), usage, filming guidance (side view, full body, good lighting, 30fps+), output description, how analysis works, known limitations (side view only: no valgus/symmetry/heel-lift detection), how to add an exercise.
- [ ] **Step 6: Commit** — `git add src/formbuddy/cli.py src/formbuddy/__main__.py README.md tests/test_cli.py && git commit -m "feat: add CLI and README"`.

---

### Task 8: Full test suite green + manual verification

**Files:** none new.

- [ ] **Step 1: Run the whole suite** — `python -m pytest tests/ -v` → all PASS.
- [ ] **Step 2: CLI smoke test** — `python -m formbuddy.cli --help` and `formbuddy --help` both print usage and exit 0.
- [ ] **Step 3: Manual verification** — user records a side-view squat clip, runs the CLI on it, checks the annotated video and report are sensible; file any issues found as bugs (do not silently expand scope).
- [ ] **Step 4: Commit** any fixes with `git commit -m "fix: <description>"`.
