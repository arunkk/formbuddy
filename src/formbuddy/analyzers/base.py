"""Base types shared by all exercise analyzers."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field

import numpy as np


@dataclass
class Frame:
    """One frame of pose landmarks with a timestamp.

    Parameters
    ----------
    landmarks : np.ndarray of shape (33, 3)
        Pose landmarks with columns (x, y, visibility).
    timestamp : float
        Seconds since the start of the clip.
    """

    landmarks: np.ndarray
    timestamp: float


@dataclass
class ExerciseReport:
    """Result of analyzing a clip of an exercise.

    Parameters
    ----------
    exercise : str
        Exercise identifier, e.g. ``"squat"``.
    warnings : list of str
        Non-fatal problems encountered during analysis.
    video_meta : dict
        Optional video metadata (fps, frame count, ...) filled in by the
        pipeline that produced the frames.
    """

    exercise: str
    warnings: list[str] = field(default_factory=list)
    video_meta: dict = field(default_factory=dict)


class ExerciseAnalyzer(ABC):
    """Interface for per-exercise form analyzers."""

    @abstractmethod
    def analyze(self, frames: list[Frame]) -> ExerciseReport:
        """Analyze a sequence of frames and return a report.

        Parameters
        ----------
        frames : list of Frame
            Pose landmarks per frame, in temporal order.

        Returns
        -------
        ExerciseReport
            The analysis result.
        """
        raise NotImplementedError
