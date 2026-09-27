"""Per-exercise form analyzers."""

from formbuddy.analyzers.base import ExerciseAnalyzer, ExerciseReport, Frame
from formbuddy.analyzers.squat import SquatAnalyzer, SquatReport

__all__ = [
    "ExerciseAnalyzer",
    "ExerciseReport",
    "Frame",
    "SquatAnalyzer",
    "SquatReport",
]
