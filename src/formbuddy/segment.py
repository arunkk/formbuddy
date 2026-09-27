"""Person segmentation gate for pose estimation.

MediaPipe Pose can lock onto gym equipment (rack uprights, loaded plates,
benches) when the lifter shares the frame with it.  This module isolates the
*best* person in each frame with MediaPipe's selfie segmentation model so the
pose landmarker only ever sees person pixels, and gives the pipeline a way to
reject pose results that fall outside the person silhouette.

The segmenter runs in video mode so its person mask is tracked temporally,
mirroring ``formbuddy.pose.PoseEstimator``.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

# MediaPipe selfie segmentation model asset (binary person mask, float16).
_MODEL_PATH = Path(__file__).parent / "assets" / "selfie_segmenter.tflite"

# Person-pixel probability cut-off of the binary selfie mask.
PERSON_CONFIDENCE = 0.5

# A connected component smaller than this fraction of the frame is noise,
# not a person.
MIN_PERSON_COVERAGE = 0.002

# Components at least this large relative to the biggest one are merged into
# the best person when their bounding box touches the main body — those are
# detached limbs (a hand or foot the mask split off), not a second person.
_ATTACHED_AREA_RATIO = 0.05
_ATTACHED_MARGIN = 0.15

# Neutral mid-grey used to suppress background pixels.
BACKGROUND_FILL = 114

# Pose results with fewer than this fraction of visible landmarks inside the
# (dilated) person mask are treated as environment lock-on and dropped.
MIN_LANDMARK_INSIDE_FRACTION = 0.5

# Dilation of the person mask, as a fraction of the short frame side, used
# when validating pose landmarks against the silhouette.
_MASK_DILATE_FRACTION = 0.008


@dataclass
class PersonMask:
    """Binary silhouette of the best person in one frame.

    Parameters
    ----------
    mask : np.ndarray of shape (H, W), dtype uint8
        1 on person pixels, 0 elsewhere.
    coverage : float
        Fraction of frame pixels belonging to the person.
    """

    mask: np.ndarray
    coverage: float

    @property
    def bbox(self) -> tuple[int, int, int, int] | None:
        """Bounding box ``(x0, y0, x1, y1)`` in pixels, or None if empty."""
        ys, xs = np.nonzero(self.mask)
        if xs.size == 0:
            return None
        return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


class PersonSegmenter:
    """Segment the best person out of BGR frames.

    Wraps ``mediapipe.tasks.vision.ImageSegmenter`` (selfie segmentation) in
    video mode.  The segmenter instance is created once and kept alive for
    the segmenter's lifetime so masks are tracked temporally.  The model
    asset ships with the package (``assets/selfie_segmenter.tflite``).

    Parameters
    ----------
    person_confidence : float
        Per-pixel probability cut-off for person vs. background.
    min_coverage : float
        Minimum frame fraction a connected component must cover to count as
        a person; smaller components are discarded as noise.
    """

    def __init__(
        self,
        person_confidence: float = PERSON_CONFIDENCE,
        min_coverage: float = MIN_PERSON_COVERAGE,
    ) -> None:
        options = mp.tasks.vision.ImageSegmenterOptions(
            base_options=mp.tasks.BaseOptions(model_asset_path=str(_MODEL_PATH)),
            running_mode=mp.tasks.vision.RunningMode.VIDEO,
            output_confidence_masks=True,
            output_category_mask=False,
        )
        self._segmenter = mp.tasks.vision.ImageSegmenter.create_from_options(options)
        self.person_confidence = person_confidence
        self.min_coverage = min_coverage

    def process(self, bgr_frame: np.ndarray, timestamp_ms: int) -> PersonMask | None:
        """Segment the best person in *bgr_frame* at *timestamp_ms*.

        Returns
        -------
        PersonMask or None
            None when no component reaches *min_coverage*, i.e. no person.
        """
        rgb = cv2.cvtColor(bgr_frame, cv2.COLOR_BGR2RGB)
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = self._segmenter.segment_for_video(image, timestamp_ms)
        if not result.confidence_masks:
            return None
        # The binary selfie model returns a single (H, W, 1) confidence mask.
        probability = np.asarray(result.confidence_masks[0].numpy_view())
        probability = probability[:, :, 0].astype(np.float32)
        mask = best_person_mask(probability, self.person_confidence, self.min_coverage)
        if mask is None:
            return None
        return PersonMask(mask=mask, coverage=float(mask.mean()))

    def close(self) -> None:
        """Release the native segmenter resources."""
        self._segmenter.close()

    def __enter__(self) -> "PersonSegmenter":
        return self

    def __exit__(self, *exc_info) -> None:
        self.close()


def best_person_mask(
    probability: np.ndarray,
    threshold: float = PERSON_CONFIDENCE,
    min_coverage: float = MIN_PERSON_COVERAGE,
) -> np.ndarray | None:
    """Reduce a person-probability map to the best person's binary mask.

    Thresholds *probability*, closes small holes, then keeps the largest
    connected component plus any sizeable component whose bounding box
    touches it (a detached limb of the same person).  Distant components —
    other people — are dropped.

    Returns
    -------
    np.ndarray of shape (H, W), dtype uint8, or None
        1 on best-person pixels; None when nothing reaches *min_coverage*.
    """
    height, width = probability.shape
    binary = (probability >= threshold).astype(np.uint8)
    kernel = _kernel_size(height, width)
    if kernel > 1:
        binary = cv2.morphologyEx(
            binary,
            cv2.MORPH_CLOSE,
            cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel, kernel)),
        )
    count, labels, stats, _ = cv2.connectedComponentsWithStats(binary, connectivity=8)
    if count <= 1:
        return None

    areas = stats[1:, cv2.CC_STAT_AREA]
    min_area = max(1.0, min_coverage * height * width)
    candidates = [i + 1 for i in range(count - 1) if areas[i] >= min_area]
    if not candidates:
        return None

    seed = max(candidates, key=lambda label: areas[label - 1])
    mask = np.zeros_like(binary)
    mask[labels == seed] = 1

    sx, sy, sw, sh = (int(v) for v in stats[seed, :4])
    margin_x = _ATTACHED_MARGIN * sw
    margin_y = _ATTACHED_MARGIN * sh
    for label in candidates:
        if label == seed or areas[label - 1] < _ATTACHED_AREA_RATIO * areas[seed - 1]:
            continue
        x, y, w, h = (int(v) for v in stats[label, :4])
        touches = (
            x <= sx + sw + margin_x
            and x + w >= sx - margin_x
            and y <= sy + sh + margin_y
            and y + h >= sy - margin_y
        )
        if touches:
            mask[labels == label] = 1
    return mask


def suppress_background(
    bgr_frame: np.ndarray, mask: np.ndarray, fill: int = BACKGROUND_FILL
) -> np.ndarray:
    """Return *bgr_frame* with every non-person pixel set to *fill*.

    Masked OpenCV bitwise ops keep this a single SIMD pass over the frame;
    boolean fancy-indexing the person pixels is an order of magnitude
    slower at 1080p.
    """
    person = cv2.bitwise_and(bgr_frame, bgr_frame, mask=mask)
    fill_frame = np.full_like(bgr_frame, fill)
    # OpenCV masks are "nonzero = apply" and unmasked pixels of a fresh dst
    # come out zero, so the 0/1 person mask inverts arithmetically here.
    background = cv2.bitwise_and(fill_frame, fill_frame, mask=1 - mask)
    return cv2.add(person, background)


def landmark_inside_fraction(mask: np.ndarray, landmarks: np.ndarray) -> float:
    """Fraction of visible landmarks that fall on the person, with tolerance.

    *landmarks* are normalized ``(x, y, visibility)`` rows; only rows with
    visibility >= 0.5 are checked.  A landmark just outside the silhouette
    still counts when any mask pixel lies within a tolerance band (~0.8% of
    the short frame side) around it.  Returns 1.0 when no landmark is
    visible (nothing to validate).
    """
    height, width = mask.shape
    radius = max(3, int(_MASK_DILATE_FRACTION * min(height, width)))
    visible = landmarks[:, 2] >= 0.5
    if not visible.any():
        return 1.0
    xs = np.clip((landmarks[visible, 0] * width).astype(int), 0, width - 1)
    ys = np.clip((landmarks[visible, 1] * height).astype(int), 0, height - 1)
    on_person = mask[ys, xs] == 1
    # Only the few off-silhouette landmarks pay for a window lookup.
    for i in np.nonzero(~on_person)[0]:
        y0, y1 = max(0, ys[i] - radius), min(height, ys[i] + radius + 1)
        x0, x1 = max(0, xs[i] - radius), min(width, xs[i] + radius + 1)
        if mask[y0:y1, x0:x1].any():
            on_person[i] = True
    return float(on_person.mean())


def _kernel_size(height: int, width: int) -> int:
    """Odd morphological kernel side, ~0.5% of the short frame side."""
    size = int(0.005 * min(height, width))
    return size | 1
