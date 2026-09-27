"""Tests for the report builder."""

from __future__ import annotations

import json

import pytest

from formbuddy.analyzers.squat import (
    FAULT_INSUFFICIENT_DEPTH,
    RepResult,
    SquatReport,
    SquatSummary,
)
from formbuddy.report import ReportBuilder


def make_report() -> SquatReport:
    """A SquatReport with two reps: one full below-parallel rep and one
    partial above-parallel rep carrying a depth fault."""
    return SquatReport(
        exercise="squat",
        reps=[
            RepResult(
                rep_number=1,
                depth="below_parallel",
                bottom_knee_angle=80.0,
                torso_angle_at_bottom=10.0,
                eccentric_seconds=2.0,
                concentric_seconds=1.5,
                bottom_pause_seconds=0.5,
                faults=[],
                partial=False,
            ),
            RepResult(
                rep_number=2,
                depth="above_parallel",
                bottom_knee_angle=110.0,
                torso_angle_at_bottom=12.0,
                eccentric_seconds=2.2,
                concentric_seconds=0.0,
                bottom_pause_seconds=0.0,
                faults=[FAULT_INSUFFICIENT_DEPTH],
                partial=True,
            ),
        ],
        summary=SquatSummary(
            total_reps=2,
            partial_reps=1,
            reps_below_parallel=1,
            reps_at_parallel=0,
            reps_above_parallel=1,
            avg_eccentric_seconds=2.1,
            avg_concentric_seconds=0.75,
            avg_bottom_pause_seconds=0.25,
            avg_torso_angle_at_bottom=11.0,
            max_torso_angle=25.0,
        ),
    )


def test_build_writes_both_files(tmp_path):
    """build() writes report.json and report.txt into out_dir."""
    ReportBuilder().build(make_report(), str(tmp_path))
    assert (tmp_path / "report.json").exists()
    assert (tmp_path / "report.txt").exists()


def test_build_creates_out_dir(tmp_path):
    """build() creates out_dir (including parents) if missing."""
    out_dir = tmp_path / "nested" / "reports"
    ReportBuilder().build(make_report(), str(out_dir))
    assert (out_dir / "report.json").exists()
    assert (out_dir / "report.txt").exists()


def test_build_returns_json_dict(tmp_path):
    """build() returns the JSON dict with exercise, summary, and reps."""
    result = ReportBuilder().build(make_report(), str(tmp_path))
    assert result["exercise"] == "squat"
    assert result["summary"]["total_reps"] == 2
    assert result["summary"]["partial_reps"] == 1
    assert len(result["reps"]) == 2


def test_json_file_matches_returned_dict(tmp_path):
    """The report.json contents equal the dict returned by build()."""
    result = ReportBuilder().build(make_report(), str(tmp_path))
    on_disk = json.loads((tmp_path / "report.json").read_text())
    assert on_disk == result


def test_text_contains_rep_lines_and_fault(tmp_path):
    """report.txt has one line per rep and names the fault."""
    ReportBuilder().build(make_report(), str(tmp_path))
    text = (tmp_path / "report.txt").read_text()
    assert "#1" in text
    assert "#2" in text
    assert FAULT_INSUFFICIENT_DEPTH in text


def test_build_returns_video_meta_and_warnings_keys(tmp_path):
    """The returned JSON dict carries the video_meta and warnings keys."""
    result = ReportBuilder().build(make_report(), str(tmp_path))
    assert "video_meta" in result
    assert "warnings" in result


def test_summary_torso_fields_in_json(tmp_path):
    """The torso summary fields appear in the returned JSON dict."""
    result = ReportBuilder().build(make_report(), str(tmp_path))
    assert result["summary"]["avg_torso_angle_at_bottom"] == pytest.approx(11.0)
    assert result["summary"]["max_torso_angle"] == pytest.approx(25.0)


def test_text_contains_torso_summary_lines(tmp_path):
    """report.txt includes the torso summary lines."""
    ReportBuilder().build(make_report(), str(tmp_path))
    text = (tmp_path / "report.txt").read_text()
    assert "Avg torso angle at bottom" in text
    assert "Max torso angle" in text
