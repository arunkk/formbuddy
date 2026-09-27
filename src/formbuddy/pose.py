"""MediaPipe pose estimation wrapper.

Converts BGR video frames into ``(33, 3)`` normalized ``(x, y, visibility)``
landmark arrays — the format consumed by ``formbuddy.analyzers``.
"""

from __future__ import annotations

from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

# Pose landmarker model asset (MediaPipe pose_landmarker_lite, float16).
_MODEL_PATH = Path(__file__).parent / "assets" / "pose_landmarker_lite.task"

# Milliseconds between synthetic video frames (~30 fps); timestamps passed to
# detect_for_video must be strictly increasing.
_FRAME_INTERVAL_MS = 33


class PoseEstimator:
    """Detect pose landmarks in BGR frames.

    Wraps ``mediapipe.tasks.vision.PoseLandmarker`` in video mode.  The
    landmarker instance is created once and kept alive for the estimator's
    lifetime so frames are tracked temporally.  The model asset ships with
    the package (``assets/pose_landmarker_lite.task``).

    Parameters
    ----------
    min_detection_confidence : float
        Minimum confidence for a pose detection to be considered successful.
    min_tracking_confidence : float
        Minimum confidence for pose tracking to be considered successful.
    """

    def __init__(
        self,
        min_detection_confidence: float = 0.5,
        min_tracking_confidence: float = 0.5,
    ) -> None:
        options = mp.tasks.vision.PoseLandmarkerOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=str(_MODEL_PATH)),
            running_mode=mp.tasks.vision.RunningMode.VIDEO,
            num_poses=1,
            min_pose_detection_confidence=min_detection_confidence,
            min_tracking_confidence=min_tracking_confidence,
        )
        self._landmarker = mp.tasks.vision.PoseLandmarker.create_from_options(options)
        self._frame_index = 0

    def process(self, bgr_frame: np.ndarray) -> np.ndarray | None:
        """Detect the pose in *bgr_frame*.

        Returns
        -------
        np.ndarray of shape (33, 3) or None
            Normalized ``(x, y, visibility)`` per landmark, or None when no
            pose is detected.
        """
        rgb = cv2.cvtColor(bgr_frame, cv2.COLOR_BGR2RGB)
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        self._frame_index += 1
        timestamp_ms = self._frame_index * _FRAME_INTERVAL_MS
        result = self._landmarker.detect_for_video(image, timestamp_ms)

        if not result.pose_landmarks:
            return None
        landmarks = result.pose_landmarks[0]
        return np.array(
            [
                [lm.x, lm.y, lm.visibility if lm.visibility is not None else 0.0]
                for lm in landmarks
            ],
            dtype=float,
        )

    def close(self) -> None:
        """Release the native landmarker resources."""
        self._landmarker.close()

    def __enter__(self) -> "PoseEstimator":
        return self

    def __exit__(self, *exc_info) -> None:
        self.close()
