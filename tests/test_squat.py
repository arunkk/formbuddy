"""Tests for the squat form analyzer."""

from __future__ import annotations

import math

import numpy as np
import pytest

from formbuddy.geometry import SIDE_LANDMARKS, joint_angle, select_side
from formbuddy.analyzers.base import Frame
from formbuddy.analyzers.squat import (
    DEPTH_ABOVE,
    DEPTH_PARALLEL,
    EXCESSIVE_LEAN_DEGREES,
    HYSTERESIS_ANGLE,
    MIN_ECCENTRIC_SECONDS,
    RISE_CONFIRM_ANGLE,
    STANDING_KNEE_ANGLE,
    SquatAnalyzer,
)


# ---------------------------------------------------------------------------
# Test helper
# ---------------------------------------------------------------------------

def make_frames(
    knee_angles: list[float],
    torso_angles: list[float] | float = 0.0,
    dt: float = 0.1,
    visibility_side: str | None = "left",
    zero_visibility: bool = False,
) -> list[Frame]:
    """Build synthetic Frame objects that realize the requested angles.

    Places the knee at the origin, hip directly above (0, -1), and ankle
    positioned so that joint_angle(hip, knee, ankle) equals *knee_angle*.
    Shoulder is offset from hip so segment_angle_vs_vertical equals *torso_angle*.

    Parameters
    ----------
    knee_angles : list of float
        Desired knee angle (degrees) per frame.
    torso_angles : list of float or single float
        Desired torso lean angle (degrees) per frame.  A single value is
        broadcast to all frames.
    dt : float
        Seconds between frames.
    visibility_side : str or None
        Which side to make visible ("left" or "right").  None means both
        sides have equal visibility (select_side picks left by default).
    zero_visibility : bool
        If True, override all landmarks to zero visibility.
    """
    if isinstance(torso_angles, (int, float)):
        torso_angles = [torso_angles] * len(knee_angles)

    frames: list[Frame] = []
    for i, (ka, ta) in enumerate(zip(knee_angles, torso_angles)):
        lm = np.zeros((33, 3), dtype=np.float32)

        # Place knee at origin
        knee = np.array([0.5, 0.5])
        # Hip directly above knee
        hip = np.array([0.5, 0.5 - 1.0])

        # Ankle positioned to realize the desired knee angle.
        # joint_angle(hip, knee, ankle) = ka
        # With hip at (0, -1) from knee, ankle at distance 1:
        #   cos(ka) = (-1) * (-sin(ka_rad)) => angle = ka
        ka_rad = math.radians(ka)
        ankle = knee + np.array([math.sin(ka_rad), -math.cos(ka_rad)])

        # Shoulder positioned to realize the desired torso angle.
        # segment_angle_vs_vertical(shoulder, hip) = ta
        shoulder = hip + np.array([-math.sin(math.radians(ta)), -math.cos(math.radians(ta))])

        # Assign to the chosen side
        side = visibility_side or "left"
        ids = SIDE_LANDMARKS[side]
        lm[ids["hip"], 0] = hip[0]
        lm[ids["hip"], 1] = hip[1]
        lm[ids["knee"], 0] = knee[0]
        lm[ids["knee"], 1] = knee[1]
        lm[ids["ankle"], 0] = ankle[0]
        lm[ids["ankle"], 1] = ankle[1]

        # Shoulder is landmark 11 (left) or 12 (right)
        shoulder_idx = 11 if side == "left" else 12
        lm[shoulder_idx, 0] = shoulder[0]
        lm[shoulder_idx, 1] = shoulder[1]

        # Set visibility
        if zero_visibility:
            lm[:, 2] = 0.0
        else:
            # Visible side: 1.0
            lm[ids["hip"], 2] = 1.0
            lm[ids["knee"], 2] = 1.0
            lm[ids["ankle"], 2] = 1.0
            lm[shoulder_idx, 2] = 1.0
            # Other side: 0.0
            other = "right" if side == "left" else "left"
            o_ids = SIDE_LANDMARKS[other]
            lm[o_ids["hip"], 2] = 0.0
            lm[o_ids["knee"], 2] = 0.0
            lm[o_ids["ankle"], 2] = 0.0

        frames.append(Frame(landmarks=lm, timestamp=i * dt))

    return frames


# ---------------------------------------------------------------------------
# Helper geometry verification
# ---------------------------------------------------------------------------

class TestMakeFramesGeometry:
    """Verify that make_frames produces the expected angles."""

    def test_knee_angle_170(self):
        """170° knee angle → hip and ankle nearly collinear through knee."""
        frames = make_frames([170.0])
        lm = frames[0].landmarks
        ids = SIDE_LANDMARKS["left"]
        actual = joint_angle(lm[ids["hip"], :2], lm[ids["knee"], :2], lm[ids["ankle"], :2])
        assert abs(actual - 170.0) < 0.5

    def test_knee_angle_90(self):
        """90° knee angle → right angle at knee."""
        frames = make_frames([90.0])
        lm = frames[0].landmarks
        ids = SIDE_LANDMARKS["left"]
        actual = joint_angle(lm[ids["hip"], :2], lm[ids["knee"], :2], lm[ids["ankle"], :2])
        assert abs(actual - 90.0) < 0.5

    def test_knee_angle_80(self):
        """80° knee angle → deep squat."""
        frames = make_frames([80.0])
        lm = frames[0].landmarks
        ids = SIDE_LANDMARKS["left"]
        actual = joint_angle(lm[ids["hip"], :2], lm[ids["knee"], :2], lm[ids["ankle"], :2])
        assert abs(actual - 80.0) < 0.5

    def test_torso_angle_0(self):
        """0° torso → shoulder directly above hip."""
        frames = make_frames([170.0], torso_angles=0.0)
        lm = frames[0].landmarks
        ids = SIDE_LANDMARKS["left"]
        actual = _segment_angle(lm[11, :2], lm[ids["hip"], :2])
        assert abs(actual) < 0.5

    def test_torso_angle_50(self):
        """50° torso lean → shoulder offset to produce 50° from vertical."""
        frames = make_frames([170.0], torso_angles=50.0)
        lm = frames[0].landmarks
        ids = SIDE_LANDMARKS["left"]
        actual = _segment_angle(lm[11, :2], lm[ids["hip"], :2])
        assert abs(actual - 50.0) < 0.5

    def test_visibility_side_right(self):
        """visibility_side='right' → right landmarks visible, left invisible."""
        frames = make_frames([170.0], visibility_side="right")
        lm = frames[0].landmarks
        right_ids = SIDE_LANDMARKS["right"]
        assert lm[right_ids["knee"], 2] == 1.0
        left_ids = SIDE_LANDMARKS["left"]
        assert lm[left_ids["knee"], 2] == 0.0


def _segment_angle(top, bottom):
    """Compute segment_angle_vs_vertical without importing it at module level."""
    from formbuddy.geometry import segment_angle_vs_vertical
    return segment_angle_vs_vertical(top, bottom)


# ---------------------------------------------------------------------------
# Module constants
# ---------------------------------------------------------------------------

class TestModuleConstants:
    """Verify the spec'd constants exist with the right values."""

    def test_standing_knee_angle(self):
        assert STANDING_KNEE_ANGLE == 160

    def test_hysteresis_angle(self):
        assert HYSTERESIS_ANGLE == 150

    def test_rise_confirm_angle(self):
        assert RISE_CONFIRM_ANGLE == 10

    def test_depth_above(self):
        assert DEPTH_ABOVE == 100

    def test_depth_parallel(self):
        assert DEPTH_PARALLEL == 90

    def test_excessive_lean(self):
        assert EXCESSIVE_LEAN_DEGREES == 45

    def test_min_eccentric_seconds(self):
        assert MIN_ECCENTRIC_SECONDS == 1.0


# ---------------------------------------------------------------------------
# Rep detection & depth classification
# ---------------------------------------------------------------------------

class TestRepDetection:
    """Two clean reps, depth classification, fault detection."""

    def _two_clean_reps(self) -> list[float]:
        """170→80→170→170→80→170 at 10 fps (dt=0.1), ~2s per rep."""
        down = np.linspace(170, 80, 20).tolist()
        up = np.linspace(80, 170, 20).tolist()
        hold = [170.0] * 5
        return hold + down + up + hold + down + up + hold

    def test_two_clean_reps_count(self):
        angles = self._two_clean_reps()
        report = SquatAnalyzer().analyze(make_frames(angles, dt=0.1))
        assert report.summary.total_reps == 2

    def test_two_clean_reps_below_parallel(self):
        angles = self._two_clean_reps()
        report = SquatAnalyzer().analyze(make_frames(angles, dt=0.1))
        for rep in report.reps:
            assert rep.depth == "below_parallel"

    def test_two_clean_reps_no_faults(self):
        angles = self._two_clean_reps()
        report = SquatAnalyzer().analyze(make_frames(angles, dt=0.1))
        for rep in report.reps:
            assert rep.faults == []

    def test_two_clean_reps_no_partial(self):
        angles = self._two_clean_reps()
        report = SquatAnalyzer().analyze(make_frames(angles, dt=0.1))
        assert report.summary.partial_reps == 0


# ---------------------------------------------------------------------------
# Depth at specific angles
# ---------------------------------------------------------------------------

class TestDepthClassification:
    """Test depth at specific bottom angles."""

    def test_parallel_depth_at_95(self):
        """Bottoming at 95° → depth == 'parallel'."""
        down = np.linspace(170, 95, 20).tolist()
        up = np.linspace(95, 170, 20).tolist()
        hold = [170.0] * 5
        angles = hold + down + up + hold
        report = SquatAnalyzer().analyze(make_frames(angles, dt=0.1))
        assert len(report.reps) == 1
        assert report.reps[0].depth == "parallel"

    def test_above_parallel_at_110(self):
        """Bottoming at 110° → depth == 'above_parallel', fault 'insufficient_depth'."""
        down = np.linspace(170, 110, 20).tolist()
        up = np.linspace(110, 170, 20).tolist()
        hold = [170.0] * 5
        angles = hold + down + up + hold
        report = SquatAnalyzer().analyze(make_frames(angles, dt=0.1))
        assert len(report.reps) == 1
        assert report.reps[0].depth == "above_parallel"
        assert "insufficient_depth" in report.reps[0].faults


# ---------------------------------------------------------------------------
# Torso lean fault
# ---------------------------------------------------------------------------

class TestTorsoLeanFault:
    """Excessive forward lean at bottom → 'excessive_forward_lean' fault."""

    def test_excessive_lean_at_bottom(self):
        """Torso 50° at bottom → fault 'excessive_forward_lean'."""
        down = np.linspace(170, 80, 20).tolist()
        up = np.linspace(80, 170, 20).tolist()
        hold = [170.0] * 5
        angles = hold + down + up + hold

        # Torso: upright during stand/hold, 50° during the rep
        t_hold = [0.0] * 5
        t_down = [0.0] + list(np.linspace(0, 50, 19))  # ramp up lean
        t_up = list(np.linspace(50, 0, 20))  # ramp down lean
        torso = t_hold + t_down + t_up + t_hold

        report = SquatAnalyzer().analyze(make_frames(angles, torso_angles=torso, dt=0.1))
        assert len(report.reps) == 1
        assert "excessive_forward_lean" in report.reps[0].faults


# ---------------------------------------------------------------------------
# Uncontrolled descent fault
# ---------------------------------------------------------------------------

class TestUncontrolledDescent:
    """Eccentric phase < 1.0s → fault 'uncontrolled_descent'."""

    def test_fast_descent(self):
        """0.5s eccentric (5 frames at 10fps) → 'uncontrolled_descent'."""
        down = np.linspace(170, 80, 5).tolist()
        up = np.linspace(80, 170, 20).tolist()
        hold = [170.0] * 5
        angles = hold + down + up + hold
        report = SquatAnalyzer().analyze(make_frames(angles, dt=0.1))
        assert len(report.reps) == 1
        assert "uncontrolled_descent" in report.reps[0].faults


# ---------------------------------------------------------------------------
# Partial reps
# ---------------------------------------------------------------------------

class TestPartialReps:
    """Clip ending mid-rep → partial rep counted."""

    def test_clip_ending_mid_rep(self):
        """Clip ending mid-rep → that rep has partial == True."""
        down = np.linspace(170, 80, 20).tolist()
        # Only go partway back up
        up_partial = np.linspace(80, 120, 10).tolist()
        hold = [170.0] * 5
        angles = hold + down + up_partial
        report = SquatAnalyzer().analyze(make_frames(angles, dt=0.1))
        assert len(report.reps) >= 1
        assert report.reps[-1].partial is True
        assert report.summary.partial_reps >= 1


# ---------------------------------------------------------------------------
# Frame annotations
# ---------------------------------------------------------------------------

class TestFrameAnnotations:
    """FrameAnnotation list length and phase values."""

    def test_annotation_count_matches_frames(self):
        """FrameAnnotation list length equals input frame count."""
        down = np.linspace(170, 80, 20).tolist()
        up = np.linspace(80, 170, 20).tolist()
        hold = [170.0] * 5
        angles = hold + down + up + hold
        frames = make_frames(angles, dt=0.1)
        report = SquatAnalyzer().analyze(frames)
        assert len(report.frames) == len(frames)

    def test_phase_values(self):
        """Phase values come from {standing, descending, ascending}."""
        down = np.linspace(170, 80, 20).tolist()
        up = np.linspace(80, 170, 20).tolist()
        hold = [170.0] * 5
        angles = hold + down + up + hold
        report = SquatAnalyzer().analyze(make_frames(angles, dt=0.1))
        valid_phases = {"standing", "descending", "ascending"}
        for ann in report.frames:
            assert ann.phase in valid_phases, f"Invalid phase: {ann.phase}"


# ---------------------------------------------------------------------------
# Zero-visibility handling
# ---------------------------------------------------------------------------

class TestZeroVisibility:
    """All-zero visibility → zero reps, no crash."""

    def test_zero_visibility_no_crash(self):
        """Frames with all-zero visibility → zero reps computed, no crash."""
        angles = [170.0] * 30
        frames = make_frames(angles, zero_visibility=True)
        report = SquatAnalyzer().analyze(frames)
        assert report.summary.total_reps == 0

    def test_zero_visibility_no_partial(self):
        """Zero-visibility → no partial reps either."""
        angles = [170.0] * 30
        frames = make_frames(angles, zero_visibility=True)
        report = SquatAnalyzer().analyze(frames)
        assert report.summary.partial_reps == 0