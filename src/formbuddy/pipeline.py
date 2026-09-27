"""End-to-end analysis pipeline.

Orchestrates the stages: video decode → pose estimation → temporal
smoothing → per-exercise analysis → report + annotated video output.
Decoded frames are kept in memory for the annotation pass (short clips;
no two-pass streaming).
"""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np

from formbuddy.annotate import VideoWriter, annotate_frame
from formbuddy.analyzers.base import ExerciseAnalyzer, ExerciseReport, Frame
from formbuddy.analyzers.squat import SquatAnalyzer
from formbuddy.pose import FRAME_INTERVAL_MS, PoseEstimator
from formbuddy.report import ReportBuilder
from formbuddy.segment import (
    MIN_LANDMARK_INSIDE_FRACTION,
    PersonSegmenter,
    landmark_inside_fraction,
    suppress_background,
)
from formbuddy.smoothing import LandmarkSmoother

# Exercise-name → analyzer registry.  This is the single source of truth;
# the CLI imports it for its argparse choices.
ANALYZERS: dict[str, type[ExerciseAnalyzer]] = {"squat": SquatAnalyzer}

# Warning appended when more than this fraction of frames had no person.
EMPTY_FRAME_WARNING = "no_person_in_most_frames"
_EMPTY_FRAME_RATIO_THRESHOLD = 0.2


def run(
    input_path: str,
    exercise: str = "squat",
    output_dir: str = "./out",
    write_video: bool = True,
    estimator: PoseEstimator | None = None,
    segment_person: bool = True,
    segmenter: PersonSegmenter | None = None,
) -> ExerciseReport:
    """Analyze one exercise clip end to end.

    Opens *input_path* with OpenCV and, per frame, segments the best person
    (``PersonSegmenter``), suppresses the background so the pose landmarker
    only sees person pixels, then runs ``estimator.process`` →
    ``LandmarkSmoother.update`` → ``Frame``.  Pose results whose visible
    landmarks fall mostly outside the person silhouette are dropped as
    environment lock-on.  The pose sequence is analyzed with the analyzer
    registered for *exercise*, and ``output_dir/report.json`` plus
    ``output_dir/report.txt`` are written.  When *write_video* is True an
    annotated ``<stem>_annotated.mp4`` is also written.

    Parameters
    ----------
    input_path : str
        Path to the input video file.
    exercise : str
        Exercise to analyze; must be a key of ``ANALYZERS``.
    output_dir : str
        Directory for report and annotated video (created if missing).
    write_video : bool
        Write the annotated MP4.
    estimator : PoseEstimator or None
        Pose estimator to use; a ``PoseEstimator`` is created when omitted.
    segment_person : bool
        Gate pose estimation on person segmentation (default).  When False
        the raw frames go straight to the pose estimator.
    segmenter : PersonSegmenter or None
        Segmenter to use when *segment_person*; created when omitted.

    Returns
    -------
    ExerciseReport
        The analysis result (also written to disk).

    Raises
    ------
    FileNotFoundError
        If *input_path* cannot be opened with OpenCV.
    ValueError
        If *exercise* is not in ``ANALYZERS``.
    """
    if exercise not in ANALYZERS:
        known = ", ".join(sorted(ANALYZERS))
        raise ValueError(f"unknown exercise {exercise!r} (known: {known})")

    cap = cv2.VideoCapture(input_path)

    own_estimator = estimator is None
    if own_estimator:
        estimator = PoseEstimator()

    # An injected segmenter is only honoured while segmentation is on.
    segmenter = segmenter if segment_person else None
    own_segmenter = segment_person and segmenter is None
    if own_segmenter:
        segmenter = PersonSegmenter()

    try:
        if not cap.isOpened():
            raise FileNotFoundError(f"cannot open video file: {input_path}")

        smoother = LandmarkSmoother()
        frames: list[np.ndarray] = []
        landmarks_per_frame: list[np.ndarray | None] = []
        timestamps: list[float] = []
        empty_frames = 0
        segmented_frames = 0
        rejected_frames = 0
        fps = cap.get(cv2.CAP_PROP_FPS)
        if fps <= 0:
            # Some containers/codecs report fps as 0; fall back to a
            # default so timestamps and duration stay well-defined.
            fps = 30.0

        index = 0
        while True:
            ok, bgr = cap.read()
            if not ok:
                break
            timestamp_ms = (index + 1) * FRAME_INTERVAL_MS
            mask = None
            if segmenter is not None:
                person = segmenter.process(bgr, timestamp_ms)
                if person is not None:
                    mask = person.mask
                    segmented_frames += 1
            # Feed the pose landmarker only person pixels; with no person
            # mask there is nothing to suppress and the raw frame is used.
            pose_input = (
                suppress_background(bgr, mask) if mask is not None else bgr
            )
            detected = estimator.process(pose_input)
            if detected is not None and mask is not None:
                inside = landmark_inside_fraction(mask, detected)
                if inside < MIN_LANDMARK_INSIDE_FRACTION:
                    detected = None
                    rejected_frames += 1
            # Empty frames are counted at the detection level: the smoother
            # deliberately carries the last landmarks forward for the
            # analysis stream, so its return value must not be used here.
            if detected is None:
                empty_frames += 1
            smoothed = smoother.update(detected)
            if smoothed is not None:
                # The smoother returns its internal mutable state; copy so
                # each retained frame keeps its own snapshot.
                smoothed = smoothed.copy()
            frames.append(bgr)
            landmarks_per_frame.append(smoothed)
            timestamps.append(index / fps)
            index += 1
    finally:
        cap.release()
        if own_estimator:
            estimator.close()
        if own_segmenter and segmenter is not None:
            segmenter.close()

    analysis_frames = [
        Frame(landmarks=landmarks, timestamp=ts)
        for landmarks, ts in zip(landmarks_per_frame, timestamps)
    ]
    report = ANALYZERS[exercise]().analyze(analysis_frames)

    frame_count = len(frames)
    report.video_meta = {
        "fps": fps,
        "frame_count": frame_count,
        "duration": frame_count / fps,
    }
    if segment_person:
        report.video_meta["segmented_frames"] = segmented_frames
        report.video_meta["pose_rejected_outside_person"] = rejected_frames
    if frame_count > 0 and empty_frames / frame_count > _EMPTY_FRAME_RATIO_THRESHOLD:
        report.warnings.append(EMPTY_FRAME_WARNING)

    ReportBuilder().build(report, output_dir)

    if write_video and frame_count > 0:
        out_path = Path(output_dir) / f"{Path(input_path).stem}_annotated.mp4"
        height, width = frames[0].shape[:2]
        writer = VideoWriter(str(out_path), fps, (width, height))
        try:
            for bgr, landmarks, ann in zip(
                frames, landmarks_per_frame, report.frames
            ):
                writer.write(annotate_frame(bgr, landmarks, ann))
        finally:
            writer.close()

    return report
