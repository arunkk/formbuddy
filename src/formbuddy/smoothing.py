"""Temporal smoothing for pose landmarks."""

from __future__ import annotations

import numpy as np


class LandmarkSmoother:
    """Per-landmark exponential moving average with visibility gating.

    Landmarks observed with visibility >= 0.5 are smoothed per coordinate as
    ``alpha * observed + (1 - alpha) * previous``.  Less visible landmarks
    carry forward their last smoothed value.  Returns None until the first
    detection has been seen.

    Parameters
    ----------
    alpha : float
        Smoothing factor in [0, 1]; higher trusts new observations more.
    """

    def __init__(self, alpha: float = 0.5) -> None:
        self.alpha = alpha
        self._smoothed: np.ndarray | None = None

    def update(self, landmarks: np.ndarray | None) -> np.ndarray | None:
        """Incorporate one frame of landmarks (or None) and return the smoothed state."""
        if landmarks is None:
            return self._smoothed

        observed = np.asarray(landmarks, dtype=float)
        if self._smoothed is None:
            self._smoothed = observed.copy()
            return self._smoothed

        visible = observed[:, 2] >= 0.5
        self._smoothed[visible] = (
            self.alpha * observed[visible]
            + (1.0 - self.alpha) * self._smoothed[visible]
        )
        return self._smoothed
