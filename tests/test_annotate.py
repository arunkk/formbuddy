"""Tests for the video annotation module."""

from __future__ import annotations

import numpy as np

from formbuddy.annotate import VideoWriter, annotate_frame
from formbuddy.analyzers.squat import FrameAnnotation


def make_landmarks(n: int = 33, seed: int = 42) -> np.ndarray:
    """Synthetic fully-visible pose landmarks in normalized coordinates."""
    rng = np.random.default_rng(seed)
    landmarks = rng.random((n, 3), dtype=np.float32)
    landmarks[:, 2] = 1.0
    return landmarks


def test_annotate_frame_draws_something() -> None:
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    ann = FrameAnnotation(
        knee_angle=90, torso_angle=10, phase="descending", rep_count=1, faults=[]
    )
    out = annotate_frame(frame, make_landmarks(), ann)
    assert out.shape == frame.shape
    assert np.any(out != 0)


def test_annotate_frame_without_landmarks_is_unchanged() -> None:
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    ann = FrameAnnotation(
        knee_angle=None, torso_angle=None, phase="standing", rep_count=0, faults=[]
    )
    out = annotate_frame(frame, None, ann)
    assert out.shape == frame.shape
    assert not np.any(out)


def test_annotate_frame_with_faults_draws_red() -> None:
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    ann = FrameAnnotation(
        knee_angle=120,
        torso_angle=50,
        phase="descending",
        rep_count=1,
        faults=["excessive_forward_lean"],
    )
    out = annotate_frame(frame, make_landmarks(), ann)
    assert out.shape == frame.shape
    # Red text (BGR red = (0, 0, 255)) must be present for the active fault.
    red_mask = (out[:, :, 2] > 200) & (out[:, :, 0] < 50) & (out[:, :, 1] < 50)
    assert np.any(red_mask)


def test_video_writer_writes_file(tmp_path) -> None:
    path = tmp_path / "out.mp4"
    writer = VideoWriter(str(path), fps=30.0, frame_size=(640, 480))
    for i in range(3):
        writer.write(np.full((480, 640, 3), i * 20, dtype=np.uint8))
    writer.close()
    assert path.exists()
    assert path.stat().st_size > 0
