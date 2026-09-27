"""Pure-math geometry helpers for pose analysis.

No MediaPipe dependency — all functions work on plain array-like points.
"""

from __future__ import annotations

import math
from typing import Sequence

import numpy as np

# Landmark indices for each side's key squat joints.
SIDE_LANDMARKS = {
    "left": {"hip": 23, "knee": 25, "ankle": 27},
    "right": {"hip": 24, "knee": 26, "ankle": 28},
}


def joint_angle(
    a: Sequence[float],
    b: Sequence[float],
    c: Sequence[float],
) -> float:
    """Angle at vertex *b* formed by points a→b→c, in degrees [0, 180].

    Parameters
    ----------
    a, b, c : array-like of two floats (x, y)
        The three points.  *b* is the vertex.
    """
    ba = np.array(a) - np.array(b)
    bc = np.array(c) - np.array(b)
    cos_angle = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc))
    # Clamp to [-1, 1] to guard against floating-point drift.
    cos_angle = max(-1.0, min(1.0, cos_angle))
    return float(math.degrees(math.acos(cos_angle)))


def segment_angle_vs_vertical(
    top: Sequence[float],
    bottom: Sequence[float],
) -> float:
    """Unsigned angle (degrees [0, 180]) between a segment and the vertical.

    In image coordinates *y* increases downward, so an upright segment
    (top directly above bottom) has 0° deviation.

    Parameters
    ----------
    top : array-like of two floats (x, y)
        The higher point (e.g. shoulder).
    bottom : array-like of two floats (x, y)
        The lower point (e.g. hip).
    """
    dx = bottom[0] - top[0]
    dy = bottom[1] - top[1]
    # Vertical reference: straight down in image coords → (0, 1).
    cos_angle = dy / math.sqrt(dx * dx + dy * dy)
    cos_angle = max(-1.0, min(1.0, cos_angle))
    return float(math.degrees(math.acos(cos_angle)))


def select_side(landmarks: np.ndarray) -> str:
    """Pick the visible side ("left" or "right") from MediaPipe landmarks.

    Compares mean *visibility* (column 2) of the hip/knee/ankle indices
    for each side.  Ties break to "left".

    Parameters
    ----------
    landmarks : np.ndarray of shape (33, 3)
        MediaPipe pose landmarks with columns (x, y, visibility).
    """
    left_ids = [SIDE_LANDMARKS["left"]["hip"],
                SIDE_LANDMARKS["left"]["knee"],
                SIDE_LANDMARKS["left"]["ankle"]]
    right_ids = [SIDE_LANDMARKS["right"]["hip"],
                 SIDE_LANDMARKS["right"]["knee"],
                 SIDE_LANDMARKS["right"]["ankle"]]
    left_vis = float(np.mean(landmarks[left_ids, 2]))
    right_vis = float(np.mean(landmarks[right_ids, 2]))
    return "left" if left_vis >= right_vis else "right"
