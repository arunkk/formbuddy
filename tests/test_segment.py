"""Tests for person segmentation (best-person mask, suppression, validation)."""

import numpy as np
import pytest

from formbuddy.segment import (
    PersonMask,
    PersonSegmenter,
    best_person_mask,
    landmark_inside_fraction,
    suppress_background,
)


def _prob_map(height: int, width: int) -> np.ndarray:
    return np.zeros((height, width), dtype=np.float32)


def _blob(prob: np.ndarray, y0: int, y1: int, x0: int, x1: int, value: float = 0.9):
    prob[y0:y1, x0:x1] = value


class TestBestPersonMask:
    """best_person_mask keeps the largest person and drops the rest."""

    def test_keeps_only_the_largest_component(self):
        prob = _prob_map(200, 200)
        _blob(prob, 20, 180, 80, 120)  # main person, 10% of the frame
        _blob(prob, 20, 60, 10, 30)  # second person far away, 2%
        mask = best_person_mask(prob)
        assert mask is not None
        assert mask.dtype == np.uint8
        assert mask[100, 100] == 1
        assert mask[30, 20] == 0
        assert int(mask.sum()) == 160 * 40

    def test_merges_detached_limb_touching_the_body(self):
        prob = _prob_map(200, 200)
        _blob(prob, 20, 180, 80, 120)
        _blob(prob, 182, 198, 80, 104)  # foot the mask split off, just below
        mask = best_person_mask(prob)
        assert mask is not None
        assert mask[190, 90] == 1

    def test_drops_detached_component_far_from_the_body(self):
        prob = _prob_map(200, 200)
        _blob(prob, 20, 180, 80, 120)
        _blob(prob, 182, 198, 10, 34)  # same size, but in another corner
        mask = best_person_mask(prob)
        assert mask is not None
        assert mask[190, 20] == 0

    def test_noise_below_min_coverage_is_ignored(self):
        prob = _prob_map(200, 200)
        _blob(prob, 10, 12, 10, 12)  # 4 px, far below 0.2% of the frame
        assert best_person_mask(prob) is None

    def test_all_background_returns_none(self):
        assert best_person_mask(_prob_map(200, 200)) is None

    def test_closes_small_holes(self):
        prob = _prob_map(480, 640)
        _blob(prob, 40, 440, 250, 390)
        prob[200, 300:310] = 0.0  # one-pixel-tall gap inside the body
        mask = best_person_mask(prob)
        assert mask is not None
        assert mask[200, 305] == 1


class TestSuppressBackground:
    def test_background_replaced_person_kept(self):
        rng = np.random.default_rng(0)
        frame = rng.integers(0, 255, size=(60, 80, 3), dtype=np.uint8)
        mask = np.zeros((60, 80), dtype=np.uint8)
        mask[10:50, 20:60] = 1
        out = suppress_background(frame, mask, fill=7)
        assert (out[mask == 0] == 7).all()
        assert (out[mask == 1] == frame[mask == 1]).all()


class TestLandmarkInsideFraction:
    def _mask(self) -> np.ndarray:
        mask = np.zeros((100, 100), dtype=np.uint8)
        mask[20:80, 20:80] = 1
        return mask

    def test_inside_landmarks_score_one(self):
        landmarks = np.array([[0.5, 0.5, 1.0]])
        assert landmark_inside_fraction(self._mask(), landmarks) == 1.0

    def test_outside_landmarks_score_zero(self):
        landmarks = np.array([[0.05, 0.05, 1.0]])
        assert landmark_inside_fraction(self._mask(), landmarks) == 0.0

    def test_invisible_landmarks_are_not_counted(self):
        landmarks = np.array([[0.05, 0.05, 0.1], [0.5, 0.5, 1.0]])
        assert landmark_inside_fraction(self._mask(), landmarks) == 1.0

    def test_no_visible_landmarks_scores_one(self):
        landmarks = np.array([[0.05, 0.05, 0.1]])
        assert landmark_inside_fraction(self._mask(), landmarks) == 1.0

    def test_mixed_landmarks_score_the_inside_share(self):
        landmarks = np.array([[0.5, 0.5, 1.0], [0.05, 0.05, 1.0]])
        assert landmark_inside_fraction(self._mask(), landmarks) == 0.5


class TestPersonMaskBBox:
    def test_bbox_bounds_the_person_pixels(self):
        mask = np.zeros((100, 100), dtype=np.uint8)
        mask[20:80, 30:60] = 1
        assert PersonMask(mask=mask, coverage=0.1).bbox == (30, 20, 60, 80)

    def test_empty_mask_has_no_bbox(self):
        mask = np.zeros((10, 10), dtype=np.uint8)
        assert PersonMask(mask=mask, coverage=0.0).bbox is None


class TestPersonSegmenter:
    """Model-backed smoke tests (the asset ships with the package)."""

    @pytest.fixture(scope="module")
    def segmenter(self):
        segmenter = PersonSegmenter()
        yield segmenter
        segmenter.close()

    def test_blank_frame_returns_none(self, segmenter):
        frame = np.zeros((240, 320, 3), dtype=np.uint8)
        assert segmenter.process(frame, 33) is None

    def test_constructor_accepts_threshold_kwargs(self):
        segmenter = PersonSegmenter(person_confidence=0.7, min_coverage=0.01)
        segmenter.close()

    def test_context_manager_closes(self):
        with PersonSegmenter() as segmenter:
            frame = np.zeros((240, 320, 3), dtype=np.uint8)
            assert segmenter.process(frame, 33) is None
