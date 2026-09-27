"""Tests for formbuddy.geometry — pure math, no ML."""

import numpy as np
import pytest

from formbuddy.geometry import (
    SIDE_LANDMARKS,
    joint_angle,
    segment_angle_vs_vertical,
    select_side,
)


# ── joint_angle ────────────────────────────────────────────────────────

class TestJointAngle:
    def test_right_angle_at_origin(self):
        """a=(0,0) → b=(1,0) → c=(1,1): angle at b = 90°."""
        assert joint_angle((0, 0), (1, 0), (1, 1)) == 90.0

    def test_straight_line(self):
        """a=(0,0) → b=(1,0) → c=(2,0): angle at b = 180°."""
        assert joint_angle((0, 0), (1, 0), (2, 0)) == 180.0

    def test_obtuse_angle_other_direction(self):
        """a=(0,0) → b=(1,0) → c=(0,1): angle at b = 45°."""
        assert joint_angle((0, 0), (1, 0), (0, 1)) == pytest.approx(45.0)


# ── segment_angle_vs_vertical ─────────────────────────────────────────

class TestSegmentAngleVsVertical:
    def test_upright_segment(self):
        """Top directly above bottom → 0° from vertical."""
        assert segment_angle_vs_vertical((1, 0), (1, 1)) == 0.0

    def test_45_degree_segment(self):
        """Segment at 45° from vertical."""
        assert segment_angle_vs_vertical((1, 0), (2, 1)) == pytest.approx(45.0)


# ── select_side ────────────────────────────────────────────────────────

class TestSelectSide:
    def _make_landmarks(self, left_vis: float, right_vis: float):
        """Create a (33, 3) zeros array with visibility at key indices.

        MediaPipe landmarks: [x, y, visibility].
        Left side indices:  23 (hip), 25 (knee), 27 (ankle).
        Right side indices: 24 (hip), 26 (knee), 28 (ankle).
        """
        lm = np.zeros((33, 3))
        for i in (23, 25, 27):
            lm[i, 2] = left_vis
        for i in (24, 26, 28):
            lm[i, 2] = right_vis
        return lm

    def test_left_visible(self):
        lm = self._make_landmarks(left_vis=1.0, right_vis=0.0)
        assert select_side(lm) == "left"

    def test_right_visible(self):
        lm = self._make_landmarks(left_vis=0.0, right_vis=1.0)
        assert select_side(lm) == "right"

    def test_equal_tie_breaks_left(self):
        lm = self._make_landmarks(left_vis=0.5, right_vis=0.5)
        assert select_side(lm) == "left"


# ── SIDE_LANDMARKS constant ───────────────────────────────────────────

class TestSideLandmarks:
    def test_structure(self):
        expected = {
            "left": {"hip": 23, "knee": 25, "ankle": 27},
            "right": {"hip": 24, "knee": 26, "ankle": 28},
        }
        assert SIDE_LANDMARKS == expected
