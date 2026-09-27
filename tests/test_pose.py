"""Tests for MediaPipe pose estimation wrapper."""

import numpy as np
import pytest

from formbuddy.pose import PoseEstimator


@pytest.fixture(scope="module")
def estimator():
    est = PoseEstimator()
    yield est
    est.close()


def test_blank_frame_returns_none(estimator):
    """A black frame contains no person, so no landmarks are returned."""
    result = estimator.process(np.zeros((240, 320, 3), dtype=np.uint8))
    assert result is None


def test_constructor_accepts_confidence_kwargs():
    estimator = PoseEstimator(
        min_detection_confidence=0.7, min_tracking_confidence=0.6
    )
    estimator.close()


def test_process_returns_none_or_33x3_landmarks(estimator):
    rng = np.random.default_rng(0)
    for _ in range(3):
        frame = rng.integers(0, 255, size=(240, 320, 3), dtype=np.uint8)
        result = estimator.process(frame)
        if result is not None:
            assert result.shape == (33, 3)
