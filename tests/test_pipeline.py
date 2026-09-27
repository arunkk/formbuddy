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


class FirstKEstimator:
    """Estimator that returns None for the first *k* calls, then plays a
    fixed knee-angle trajectory (person walks into frame late)."""

    def __init__(self, k: int, trajectory: list[float] | None = None) -> None:
        self._k = k
        self._trajectory = (
            trajectory if trajectory is not None else _two_rep_trajectory()
        )
        self._index = 0

    def process(self, bgr_frame: np.ndarray) -> np.ndarray | None:
        idx = self._index
        self._index += 1
        if idx < self._k:
            return None
        angle = self._trajectory[min(idx, len(self._trajectory) - 1)]
        return _landmarks_for_knee_angle(angle, side="right")


class GappyEstimator:
    """Estimator that returns None on a fixed set of frame indices and a
    valid trajectory elsewhere (person leaves the camera mid-clip)."""

    def __init__(
        self, empty_indices, trajectory: list[float] | None = None
    ) -> None:
        self._empty_indices = set(empty_indices)
        self._trajectory = (
            trajectory if trajectory is not None else _two_rep_trajectory()
        )
        self._index = 0

    def process(self, bgr_frame: np.ndarray) -> np.ndarray | None:
        idx = self._index
        self._index += 1
        if idx in self._empty_indices:
            return None
        angle = self._trajectory[min(idx, len(self._trajectory) - 1)]
        return _landmarks_for_knee_angle(angle, side="right")


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


class TestRunEmptyFrameAccounting:
    """Empty frames are counted at the detection (estimator) level, not
    at the smoother level (which carries landmarks forward across gaps)."""

    def test_late_arrival_below_threshold_no_warning(self, tmp_path):
        """First 5 of 30 frames undetected (ratio 0.167 < 0.2) → no
        'no_person_in_most_frames' warning; the 2-rep trajectory that
        follows is still analyzed."""
        video_path = tmp_path / "squat.mp4"
        _write_noise_video(video_path, n_frames=30)

        report = run(
            str(video_path),
            estimator=FirstKEstimator(k=5),
            output_dir=str(tmp_path),
        )

        assert "no_person_in_most_frames" not in report.warnings
        assert report.summary.total_reps == 2

    def test_interspersed_gaps_above_threshold_warns(self, tmp_path):
        """7 of 30 frames with no detection (ratio 0.233 > 0.2) → warning,
        even though the smoother carries landmarks across the gaps."""
        video_path = tmp_path / "squat.mp4"
        _write_noise_video(video_path, n_frames=30)

        report = run(
            str(video_path),
            estimator=GappyEstimator(empty_indices={0, 5, 10, 15, 20, 25, 29}),
            output_dir=str(tmp_path),
        )

        assert "no_person_in_most_frames" in report.warnings


class _FakeCapture:
    """Minimal cv2.VideoCapture stand-in for error-path tests."""

    def __init__(self, frames, fps: float, opened: bool = True) -> None:
        self._frames = list(frames)
        self._fps = fps
        self._opened = opened
        self._index = 0
        self.released = False

    def isOpened(self) -> bool:
        return self._opened

    def get(self, prop) -> float:
        return self._fps

    def read(self):
        if self._index < len(self._frames):
            frame = self._frames[self._index]
            self._index += 1
            return True, frame
        return False, None

    def release(self) -> None:
        self.released = True


class TestRunFpsZero:
    """A capture reporting fps == 0 must not crash the pipeline."""

    def test_fps_zero_falls_back_and_completes(self, tmp_path, monkeypatch):
        """fps == 0 → default fallback used for timestamps/duration; the
        run completes and reports the fallback fps."""
        frame = np.zeros((48, 64, 3), dtype=np.uint8)
        fake_cap = _FakeCapture([frame], fps=0.0)
        monkeypatch.setattr(
            "formbuddy.pipeline.cv2.VideoCapture", lambda path: fake_cap
        )

        report = run(
            str(tmp_path / "fake.mp4"),
            estimator=FakeEstimator(),
            output_dir=str(tmp_path / "out"),
            write_video=False,
        )

        assert report.video_meta["fps"] == 30.0
        assert report.video_meta["frame_count"] == 1
        assert report.video_meta["duration"] == pytest.approx(1.0 / 30.0)


class TestRunCaptureRelease:
    """The VideoCapture is released even when the file cannot be opened."""

    def test_unopenable_video_releases_capture(self, tmp_path, monkeypatch):
        """isOpened() False → FileNotFoundError, and the capture is
        released on the way out."""
        fake_cap = _FakeCapture([], fps=0.0, opened=False)
        monkeypatch.setattr(
            "formbuddy.pipeline.cv2.VideoCapture", lambda path: fake_cap
        )

        with pytest.raises(FileNotFoundError):
            run(
                str(tmp_path / "fake.mp4"),
                estimator=FakeEstimator(),
                output_dir=str(tmp_path / "out"),
            )

        assert fake_cap.released


class TestRegistry:
    """The exercise→analyzer registry lives in pipeline."""

    def test_squat_registered(self):
        assert ANALYZERS["squat"].__name__ == "SquatAnalyzer"
