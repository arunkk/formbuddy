"""Tests for landmark temporal smoothing."""

import numpy as np

from formbuddy.smoothing import LandmarkSmoother


def _frame(offset: float, visibility: float = 1.0) -> np.ndarray:
    """Synthetic (33, 3) landmark array with x = i * 0.01 + offset."""
    landmarks = np.zeros((33, 3), dtype=float)
    landmarks[:, 0] = np.arange(33) * 0.01 + offset
    landmarks[:, 1] = 0.5
    landmarks[:, 2] = visibility
    return landmarks


def test_returns_none_until_first_detection():
    smoother = LandmarkSmoother()
    assert smoother.update(None) is None
    assert smoother.update(None) is None


def test_output_length_matches_input():
    smoother = LandmarkSmoother()
    inputs = [None, _frame(0.0), _frame(0.1), None]
    outputs = [smoother.update(frame) for frame in inputs]
    assert len(outputs) == len(inputs)


def test_none_positions_return_none_when_nothing_seen_yet():
    smoother = LandmarkSmoother()
    outputs = [smoother.update(frame) for frame in [None, _frame(0.0), None]]
    assert outputs[0] is None
    assert outputs[2] is not None


def test_first_detection_passes_through():
    smoother = LandmarkSmoother(alpha=0.5)
    out = smoother.update(_frame(0.0))
    np.testing.assert_allclose(out, _frame(0.0))


def test_missing_detection_carries_forward_last_smoothed():
    smoother = LandmarkSmoother(alpha=0.5)
    smoother.update(_frame(0.0))
    after_second = smoother.update(_frame(0.1))
    carried = smoother.update(None)
    np.testing.assert_allclose(carried, after_second)


def test_ema_output_is_between_consecutive_inputs_for_moving_coordinate():
    smoother = LandmarkSmoother(alpha=0.5)
    smoother.update(_frame(0.0))
    out = smoother.update(_frame(0.1))
    # Landmark 0's x moved 0.00 -> 0.10; smoothed value must lie between.
    assert 0.0 < out[0, 0] < 0.1
    np.testing.assert_allclose(out[0, 0], 0.05)


def test_invisible_landmarks_carry_forward():
    smoother = LandmarkSmoother(alpha=0.5)
    smoother.update(_frame(0.0))
    moved = _frame(0.1)
    moved[5] = [0.9, 0.9, 0.2]  # Invisible landmark jumps; must be ignored.
    out = smoother.update(moved)
    np.testing.assert_allclose(out[5], _frame(0.0)[5])
    # Visible neighbors are still smoothed.
    assert 0.06 < out[6, 0] < 0.16
