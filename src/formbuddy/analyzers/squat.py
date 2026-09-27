"""Squat form analyzer.

Detects reps by running a hysteresis state machine on the knee angle
(hip–knee– ankle) and scores depth, tempo, and torso lean per rep.
All thresholds are module constants so callers (and tests) can reference
them by name.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from formbuddy.analyzers.base import ExerciseAnalyzer, ExerciseReport, Frame
from formbuddy.geometry import (
    SIDE_LANDMARKS,
    joint_angle,
    segment_angle_vs_vertical,
    select_side,
)

# --- Threshold constants (spec values) ------------------------------------
STANDING_KNEE_ANGLE = 160.0   # knee angle that confirms the lifter is standing
HYSTERESIS_ANGLE = 150.0      # crossing below this starts the descent
RISE_CONFIRM_ANGLE = 10.0     # rise above the bottom that confirms the ascent
DEPTH_ABOVE = 100.0           # bottom knee angle shallower than this = above parallel
DEPTH_PARALLEL = 90.0         # bottom knee angle at/below this = at/below parallel
EXCESSIVE_LEAN_DEGREES = 45.0  # torso-from-vertical beyond this = excessive lean
MIN_ECCENTRIC_SECONDS = 1.0   # faster descent than this = uncontrolled

# --- Phase names -----------------------------------------------------------
PHASE_STANDING = "standing"
PHASE_DESCENDING = "descending"
PHASE_ASCENDING = "ascending"

# --- Fault names -----------------------------------------------------------
FAULT_INSUFFICIENT_DEPTH = "insufficient_depth"
FAULT_EXCESSIVE_LEAN = "excessive_forward_lean"
FAULT_UNCONTROLLED_DESCENT = "uncontrolled_descent"

# MediaPipe shoulder indices per side (used for the torso segment).
_SHOULDER_LANDMARKS = {"left": 11, "right": 12}

# Mean hip/knee/ankle visibility below which a side is considered missing.
_MIN_SIDE_VISIBILITY = 0.5

_SIDE_KEY = ("hip", "knee", "ankle")


@dataclass
class RepResult:
    """Scoring for one detected squat rep."""

    rep_number: int
    depth: str  # "above_parallel" | "parallel" | "below_parallel"
    bottom_knee_angle: float
    torso_angle_at_bottom: float
    eccentric_seconds: float
    concentric_seconds: float
    bottom_pause_seconds: float
    faults: list[str] = field(default_factory=list)
    partial: bool = False


@dataclass
class SquatSummary:
    """Aggregate statistics over all detected reps."""

    total_reps: int
    partial_reps: int
    reps_below_parallel: int
    reps_at_parallel: int
    reps_above_parallel: int
    avg_eccentric_seconds: float
    avg_concentric_seconds: float
    avg_bottom_pause_seconds: float
    avg_torso_angle_at_bottom: float
    max_torso_angle: float


@dataclass
class FrameAnnotation:
    """Per-frame measurements and state-machine output."""

    knee_angle: float | None
    torso_angle: float | None
    phase: str
    rep_count: int
    faults: list[str] = field(default_factory=list)


@dataclass
class SquatReport(ExerciseReport):
    """Full squat analysis result."""

    reps: list[RepResult] = field(default_factory=list)
    summary: SquatSummary = field(
        default_factory=lambda: SquatSummary(
            total_reps=0,
            partial_reps=0,
            reps_below_parallel=0,
            reps_at_parallel=0,
            reps_above_parallel=0,
            avg_eccentric_seconds=0.0,
            avg_concentric_seconds=0.0,
            avg_bottom_pause_seconds=0.0,
            avg_torso_angle_at_bottom=0.0,
            max_torso_angle=0.0,
        )
    )
    frames: list[FrameAnnotation] = field(default_factory=list)


def _classify_depth(bottom_knee_angle: float) -> str:
    """Classify rep depth from the bottom knee angle."""
    if bottom_knee_angle < DEPTH_PARALLEL:
        return "below_parallel"
    if bottom_knee_angle > DEPTH_ABOVE:
        return "above_parallel"
    return "parallel"


class SquatAnalyzer(ExerciseAnalyzer):
    """Detect and score squat reps from pose frames."""

    def analyze(self, frames: list[Frame]) -> SquatReport:
        report = SquatReport(exercise="squat")

        state = PHASE_STANDING
        rep_count = 0

        # Per-rep tracking (valid between the standing→descending transition
        # and the following ascending→standing transition, or clip end).
        descent_start_time: float | None = None
        bottom_knee_angle: float | None = None
        bottom_time: float | None = None
        bottom_torso_angle: float | None = None
        ascent_start_time: float | None = None

        for frame in frames:
            knee_angle, torso_angle = self._measure(frame)

            if knee_angle is None:
                # Empty frame: no person visible.  Annotate with null angles
                # and leave the state machine untouched.
                report.frames.append(
                    FrameAnnotation(
                        knee_angle=None,
                        torso_angle=None,
                        phase=state,
                        rep_count=rep_count,
                        faults=[],
                    )
                )
                continue

            faults: list[str] = []
            if torso_angle is not None and torso_angle > EXCESSIVE_LEAN_DEGREES:
                faults.append(FAULT_EXCESSIVE_LEAN)

            if state == PHASE_STANDING:
                if knee_angle < HYSTERESIS_ANGLE:
                    state = PHASE_DESCENDING
                    rep_count += 1
                    descent_start_time = frame.timestamp
                    bottom_knee_angle = knee_angle
                    bottom_time = frame.timestamp
                    bottom_torso_angle = torso_angle
                    ascent_start_time = None
            elif state == PHASE_DESCENDING:
                if knee_angle < bottom_knee_angle:
                    bottom_knee_angle = knee_angle
                    bottom_time = frame.timestamp
                    bottom_torso_angle = torso_angle
                elif (
                    ascent_start_time is None
                    and knee_angle > bottom_knee_angle + RISE_CONFIRM_ANGLE
                ):
                    ascent_start_time = frame.timestamp
                    state = PHASE_ASCENDING
            else:  # PHASE_ASCENDING
                if knee_angle >= STANDING_KNEE_ANGLE:
                    report.reps.append(
                        self._build_rep(
                            rep_number=rep_count,
                            end_time=frame.timestamp,
                            partial=False,
                            descent_start_time=descent_start_time,
                            bottom_knee_angle=bottom_knee_angle,
                            bottom_time=bottom_time,
                            bottom_torso_angle=bottom_torso_angle,
                            ascent_start_time=ascent_start_time,
                        )
                    )
                    state = PHASE_STANDING
                    descent_start_time = None
                    bottom_knee_angle = None
                    bottom_time = None
                    bottom_torso_angle = None
                    ascent_start_time = None

            report.frames.append(
                FrameAnnotation(
                    knee_angle=knee_angle,
                    torso_angle=torso_angle,
                    phase=state,
                    rep_count=rep_count,
                    faults=faults,
                )
            )

        # Clip ended mid-rep: close a partial rep unless we are standing.
        if state != PHASE_STANDING and bottom_knee_angle is not None:
            report.reps.append(
                self._build_rep(
                    rep_number=rep_count,
                    end_time=frames[-1].timestamp if frames else 0.0,
                    partial=True,
                    descent_start_time=descent_start_time,
                    bottom_knee_angle=bottom_knee_angle,
                    bottom_time=bottom_time,
                    bottom_torso_angle=bottom_torso_angle,
                    ascent_start_time=ascent_start_time,
                )
            )

        report.summary = self._summarize(report.reps, report.frames)
        return report

    # ------------------------------------------------------------------
    # Per-frame measurement
    # ------------------------------------------------------------------

    @staticmethod
    def _measure(frame: Frame) -> tuple[float | None, float | None]:
        """Compute (knee_angle, torso_angle) for one frame.

        Returns ``(None, None)`` when neither side is visible enough to
        measure (empty frame).
        """
        landmarks = frame.landmarks
        if landmarks is None:
            return None, None
        left_ids = [SIDE_LANDMARKS["left"][k] for k in _SIDE_KEY]
        right_ids = [SIDE_LANDMARKS["right"][k] for k in _SIDE_KEY]
        left_vis = float(np.mean(landmarks[left_ids, 2]))
        right_vis = float(np.mean(landmarks[right_ids, 2]))
        if left_vis < _MIN_SIDE_VISIBILITY and right_vis < _MIN_SIDE_VISIBILITY:
            return None, None

        side = select_side(landmarks)
        ids = SIDE_LANDMARKS[side]
        hip = landmarks[ids["hip"], :2]
        knee = landmarks[ids["knee"], :2]
        ankle = landmarks[ids["ankle"], :2]
        shoulder = landmarks[_SHOULDER_LANDMARKS[side], :2]
        return (
            joint_angle(hip, knee, ankle),
            segment_angle_vs_vertical(shoulder, hip),
        )

    # ------------------------------------------------------------------
    # Rep scoring
    # ------------------------------------------------------------------

    @staticmethod
    def _build_rep(
        rep_number: int,
        end_time: float,
        partial: bool,
        descent_start_time: float | None,
        bottom_knee_angle: float | None,
        bottom_time: float | None,
        bottom_torso_angle: float | None,
        ascent_start_time: float | None,
    ) -> RepResult:
        """Assemble a RepResult from the tracked state of one rep."""
        assert bottom_knee_angle is not None and bottom_time is not None
        assert descent_start_time is not None

        eccentric = bottom_time - descent_start_time
        if ascent_start_time is None:
            # Never left the bottom (clip ended during the descent).
            bottom_pause = 0.0
            concentric = 0.0
        else:
            bottom_pause = ascent_start_time - bottom_time
            concentric = end_time - ascent_start_time

        faults: list[str] = []
        if _classify_depth(bottom_knee_angle) == "above_parallel":
            faults.append(FAULT_INSUFFICIENT_DEPTH)
        if (
            bottom_torso_angle is not None
            and bottom_torso_angle > EXCESSIVE_LEAN_DEGREES
        ):
            faults.append(FAULT_EXCESSIVE_LEAN)
        if eccentric < MIN_ECCENTRIC_SECONDS:
            faults.append(FAULT_UNCONTROLLED_DESCENT)

        return RepResult(
            rep_number=rep_number,
            depth=_classify_depth(bottom_knee_angle),
            bottom_knee_angle=bottom_knee_angle,
            torso_angle_at_bottom=(
                bottom_torso_angle if bottom_torso_angle is not None else 0.0
            ),
            eccentric_seconds=eccentric,
            concentric_seconds=concentric,
            bottom_pause_seconds=bottom_pause,
            faults=faults,
            partial=partial,
        )

    @staticmethod
    def _summarize(
        reps: list[RepResult],
        frames: list[FrameAnnotation] | None = None,
    ) -> SquatSummary:
        """Aggregate per-rep results into a SquatSummary.

        ``avg_torso_angle_at_bottom`` is the mean of the per-rep bottom
        torso angles over *all* reps: every rep has a measured bottom by
        construction (``_build_rep`` asserts ``bottom_knee_angle`` is not
        None), so none are excluded.  Reps whose torso was not measurable
        at the bottom carry the 0.0 fallback in ``torso_angle_at_bottom``
        and are included in the mean.

        ``max_torso_angle`` is the maximum torso angle over all *measured
        frames*, not just rep bottoms: the spec asks for the max without
        qualification, so a lifter who leans hard mid-descent but recovers
        by the bottom is still reflected in the summary.
        """
        max_torso_angle = 0.0
        if frames:
            measured = [
                ann.torso_angle for ann in frames if ann.torso_angle is not None
            ]
            if measured:
                max_torso_angle = max(measured)

        n = len(reps)
        if n == 0:
            return SquatSummary(
                total_reps=0,
                partial_reps=0,
                reps_below_parallel=0,
                reps_at_parallel=0,
                reps_above_parallel=0,
                avg_eccentric_seconds=0.0,
                avg_concentric_seconds=0.0,
                avg_bottom_pause_seconds=0.0,
                avg_torso_angle_at_bottom=0.0,
                max_torso_angle=max_torso_angle,
            )
        return SquatSummary(
            total_reps=n,
            partial_reps=sum(1 for r in reps if r.partial),
            reps_below_parallel=sum(1 for r in reps if r.depth == "below_parallel"),
            reps_at_parallel=sum(1 for r in reps if r.depth == "parallel"),
            reps_above_parallel=sum(1 for r in reps if r.depth == "above_parallel"),
            avg_eccentric_seconds=sum(r.eccentric_seconds for r in reps) / n,
            avg_concentric_seconds=sum(r.concentric_seconds for r in reps) / n,
            avg_bottom_pause_seconds=sum(r.bottom_pause_seconds for r in reps) / n,
            avg_torso_angle_at_bottom=(
                sum(r.torso_angle_at_bottom for r in reps) / n
            ),
            max_torso_angle=max_torso_angle,
        )
