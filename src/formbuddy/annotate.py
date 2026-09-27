"""Annotate BGR frames with the pose skeleton and a per-frame HUD.

The skeleton is drawn with MediaPipe's ``draw_landmarks`` (normalized
landmarks, pose connections); the HUD adds knee/torso angles, phase, rep
count, and active faults in red via ``cv2.putText``.
"""

from __future__ import annotations

import cv2
import numpy as np

# mediapipe >= 0.10.2 removed the legacy ``mediapipe.solutions`` API; the
# drawing utilities and pose connections live under the tasks API.
from mediapipe.tasks.python.components.containers.landmark import NormalizedLandmark
from mediapipe.tasks.python.vision.drawing_utils import DrawingSpec, draw_landmarks
from mediapipe.tasks.python.vision.pose_landmarker import PoseLandmarksConnections

POSE_CONNECTIONS = PoseLandmarksConnections.POSE_LANDMARKS

from formbuddy.analyzers.squat import FrameAnnotation


def annotate_frame(
    bgr_frame: np.ndarray,
    landmarks: np.ndarray | None,
    ann: FrameAnnotation,
) -> np.ndarray:
    """Draw the pose skeleton and analysis HUD onto *bgr_frame*.

    Landmarks are normalized ``(x, y, visibility)`` rows (see
    ``formbuddy.pose.PoseEstimator``).  When *landmarks* is None no pose was
    detected, so the frame is returned unchanged.
    """
    if landmarks is None:
        return bgr_frame

    landmark_list = [
        NormalizedLandmark(x=float(x), y=float(y), visibility=float(v))
        for x, y, v in landmarks
    ]
    draw_landmarks(
        bgr_frame,
        landmark_list,
        connections=POSE_CONNECTIONS,
        landmark_drawing_spec=DrawingSpec(
            color=(0, 0, 255), thickness=2, circle_radius=2
        ),
        connection_drawing_spec=DrawingSpec(color=(224, 224, 224), thickness=2),
    )
    _draw_hud(bgr_frame, ann)
    return bgr_frame


def _draw_hud(bgr_frame: np.ndarray, ann: FrameAnnotation) -> None:
    """Overlay per-frame measurements and active faults (red)."""
    h, w = bgr_frame.shape[:2]
    font_scale = max(0.5, min(h, w) / 480.0)
    line_height = int(28 * font_scale)
    white = (255, 255, 255)
    green = (0, 255, 0)
    red = (0, 0, 255)

    def fmt(value: float | None) -> str:
        return "N/A" if value is None else f"{value:.0f}deg"

    lines = [
        (f"Knee: {fmt(ann.knee_angle)}  Torso: {fmt(ann.torso_angle)}", white),
        (f"Phase: {ann.phase}  Reps: {ann.rep_count}", white),
    ]
    if ann.faults:
        lines.append(("Faults: " + ", ".join(ann.faults), red))
    else:
        lines.append(("Faults: none", green))

    y = line_height
    for text, color in lines:
        cv2.putText(
            bgr_frame,
            text,
            (10, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            font_scale,
            color,
            2,
            cv2.LINE_AA,
        )
        y += line_height


class VideoWriter:
    """Write BGR frames to an MP4 file (mp4v codec)."""

    def __init__(self, path: str, fps: float, frame_size: tuple[int, int]) -> None:
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        self._writer = cv2.VideoWriter(path, fourcc, fps, frame_size)

    def write(self, frame: np.ndarray) -> None:
        self._writer.write(frame)

    def close(self) -> None:
        self._writer.release()
