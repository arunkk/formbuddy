"""Tests for the end-to-end analysis pipeline."""

from __future__ import annotations

import math

import cv2
import numpy as np
import pytest

from formbuddy.analyzers.squat import SquatReport
from formbuddy.geometry import SIDE_LANDMARKS
from formbuddy.pipeline import ANALYZERS, run


# ---------------------------------------------------------------------------
# Synthetic estimator helpers (Task 2 construction style, right side visible)
# ---------------------------------------------------------------------------

def _landmarks_for_knee_angle(knee_angle: float, side: str = "right") -> np.ndarray:
    """Synthetic (33, 3) landmarks realizing *knee_angle* (Task 2 style).

    Knee at (0.5, 0.5), hip directly above, ankle placed so that
    joint_angle(hip, knee, ankle) == *knee_angle*; shoulder directly above
    hip (zero torso lean).  The given side gets visibility 1.0, the other 0.
    """
    lm = np.zeros((33, 3), dtype=np.float32)
    knee = np.array([0.5, 0.5])
    hip = np.array([0.5, -0.5])
    ka_rad = math.radians(knee_angle)
    ankle = knee + np.array([math.sin(ka_rad), -math.cos(ka_rad)])
    shoulder = hip + np.array([0.0, -1.0])

    ids = SIDE_LANDMARKS[side]
    shoulder_idx = 11 if side == "left" else 12
    lm[ids["hip"], :2] = hip
    lm[ids["knee"], :2] = knee
    lm[ids["ankle"], :2] = ankle
    lm[shoulder_idx, :2] = shoulder
    lm[ids["hip"], 2] = 1.0
    lm[ids["knee"], 2] = 1.0
    lm[ids["ankle"], 2] = 1.0
    lm[shoulder_idx, 2] = 1.0
    return lm


def _two_rep_trajectory(n_frames: int = 30) -> list[float]:
    """Two clean reps (down 170→80, up 80→170) sized to *n_frames*.

    Layout for 30 frames: down5, up5, hold5, down5, up5, hold5.  The first
    hold is unnecessary (the smoother initializes on the first observation)
    and the final hold lets the smoothed angle converge back past the
    standing threshold so both reps complete.
    """
    down = np.linspace(170.0, 80.0, 5).tolist()
    up = np.linspace(80.0, 170.0, 5).tolist()
    hold = [170.0] * 5
    return down + up + hold + down + up + hold


class FakeEstimator:
    """Synthetic pose estimator playing back a fixed knee-angle trajectory.

    Ignores the frame content; each ``process`` call advances the
    trajectory.  Extra calls clamp to the final (standing) pose.
    """

    def __init__(self, trajectory: list[float] | None = None) -> None:
        self._trajectory = trajectory if trajectory is not None else _two_rep_trajectory()
        self._index = 0

    def process(self, bgr_frame: np.ndarray) -> np.ndarray | None:
        angle = self._trajectory[min(self._index, len(self._trajectory) - 1)]
        self._index += 1
        return _landmarks_for_knee_angle(angle, side="right")


class EmptyEstimator:
    """Estimator that never detects a pose (always returns None)."""

    def process(self, bgr_frame: np.ndarray) -> None:
        return None


# ---------------------------------------------------------------------------
# Video helper
# ---------------------------------------------------------------------------

def _write_noise_video(path, n_frames: int = 30, fps: float = 30.0) -> None:
    """Write a tiny mp4 of pure noise (content is ignored by the estimator)."""
    writer = cv2.VideoWriter(
        str(path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (64, 48)
    )
    rng = np.random.default_rng(42)
    for _ in range(n_frames):
        writer.write(rng.integers(0, 256, (48, 64, 3), dtype=np.uint8))
    writer.release()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestRunEndToEnd:
    """run() on a real mp4 with an injected synthetic estimator."""

    def test_two_reps_report_and_outputs(self, tmp_path):
        """2-rep trajectory → SquatReport with total_reps == 2; report.json
        and the annotated mp4 are written."""
        video_path = tmp_path / "squat.mp4"
        _write_noise_video(video_path)

        report = run(
            str(video_path), estimator=FakeEstimator(), output_dir=str(tmp_path)
        )

        assert isinstance(report, SquatReport)
        assert report.summary.total_reps == 2
        assert (tmp_path / "report.json").exists()
        assert (tmp_path / "squat_annotated.mp4").exists()

    def test_video_meta(self, tmp_path):
        """The report carries fps, frame count, and duration."""
        video_path = tmp_path / "squat.mp4"
        _write_noise_video(video_path, n_frames=30, fps=30.0)

        report = run(
            str(video_path), estimator=FakeEstimator(), output_dir=str(tmp_path)
        )

        assert report.video_meta["fps"] == 30.0
        assert report.video_meta["frame_count"] == 30
        assert report.video_meta["duration"] == pytest.approx(1.0)

    def test_no_annotated_video_when_write_video_false(self, tmp_path):
        """write_video=False → no annotated mp4, but report.json is written."""
        video_path = tmp_path / "squat.mp4"
        _write_noise_video(video_path)

        run(
            str(video_path),
            estimator=FakeEstimator(),
            output_dir=str(tmp_path),
            write_video=False,
        )

        assert (tmp_path / "report.json").exists()
        assert not (tmp_path / "squat_annotated.mp4").exists()

    def test_unknown_exercise_raises_value_error(self, tmp_path):
        """An exercise name missing from ANALYZERS → ValueError."""
        video_path = tmp_path / "squat.mp4"
        _write_noise_video(video_path)

        with pytest.raises(ValueError):
            run(
                str(video_path),
                exercise="deadlift",
                estimator=FakeEstimator(),
                output_dir=str(tmp_path),
            )


class TestRunMissingVideo:
    """run() on a path OpenCV cannot open."""

    def test_missing_video_raises_file_not_found(self, tmp_path):
        """Non-existent input → FileNotFoundError naming the path."""
        missing = tmp_path / "does_not_exist.mp4"

        with pytest.raises(FileNotFoundError, match=str(missing)):
            run(str(missing), estimator=FakeEstimator(), output_dir=str(tmp_path))


class TestRunEmptyFrames:
    """A clip where no person is ever detected."""

    def test_all_empty_frames_warns_and_zero_reps(self, tmp_path):
        """Estimator returning None always → 0 reps + 'no_person_in_most_frames'."""
        video_path = tmp_path / "squat.mp4"
        _write_noise_video(video_path)

        report = run(
            str(video_path), estimator=EmptyEstimator(), output_dir=str(tmp_path)
        )

        assert report.summary.total_reps == 0
        assert "no_person_in_most_frames" in report.warnings
        assert (tmp_path / "report.json").exists()


class TestRegistry:
    """The exercise→analyzer registry lives in pipeline."""

    def test_squat_registered(self):
        assert ANALYZERS["squat"].__name__ == "SquatAnalyzer"
