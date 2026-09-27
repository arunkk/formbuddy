"""Tests for the command-line interface."""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from formbuddy.cli import main


class TestHelp:
    """--help prints usage and exits 0 via SystemExit."""

    def test_help_raises_system_exit_0(self, capsys):
        with pytest.raises(SystemExit) as exc_info:
            main(["--help"])
        assert exc_info.value.code == 0
        assert "usage" in capsys.readouterr().out.lower()


class TestMissingInput:
    """A path OpenCV cannot open → stderr message + exit 1."""

    def test_missing_input_returns_1(self, capsys):
        rc = main(["--input", "/nonexistent.mp4"])
        assert rc == 1
        assert "nonexistent.mp4" in capsys.readouterr().err


class TestUnsupportedExercise:
    """An exercise outside pipeline.ANALYZERS → stderr message + exit 2."""

    def test_unsupported_exercise_returns_2(self, capsys):
        rc = main(["--input", "x.mp4", "--exercise", "deadlift"])
        assert rc == 2
        assert "deadlift" in capsys.readouterr().err


class TestOSError:
    """Non-FileNotFoundError OS errors from run() → clean message + exit 1."""

    def test_permission_error_returns_1(self, tmp_path, monkeypatch, capsys):
        """e.g. PermissionError creating the output dir → 'error:' on
        stderr, exit code 1, no traceback."""

        def fake_run(
            input_path,
            exercise="squat",
            output_dir="./out",
            write_video=True,
            estimator=None,
        ):
            raise PermissionError("cannot create output dir")

        monkeypatch.setattr("formbuddy.cli.run", fake_run)

        rc = main(["--input", str(tmp_path / "x.mp4")])

        assert rc == 1
        assert "error:" in capsys.readouterr().err


class TestSuccess:
    """main() wires argv to pipeline.run and prints the one-line summary."""

    @staticmethod
    def _stub_run(monkeypatch, calls) -> None:
        def fake_run(
            input_path,
            exercise="squat",
            output_dir="./out",
            write_video=True,
            estimator=None,
        ):
            calls.update(
                input_path=input_path,
                exercise=exercise,
                output_dir=output_dir,
                write_video=write_video,
            )
            return SimpleNamespace(
                summary=SimpleNamespace(total_reps=3, reps_below_parallel=1)
            )

        monkeypatch.setattr("formbuddy.cli.run", fake_run)

    def test_success_prints_summary_and_returns_0(
        self, tmp_path, monkeypatch, capsys
    ):
        calls = {}
        self._stub_run(monkeypatch, calls)
        video = tmp_path / "squat.mp4"
        video.write_bytes(b"not a real video; run() is stubbed")

        rc = main(["--input", str(video), "--output-dir", str(tmp_path / "out")])

        assert rc == 0
        assert calls["input_path"] == str(video)
        assert calls["exercise"] == "squat"
        assert calls["output_dir"] == str(tmp_path / "out")
        assert calls["write_video"] is True
        assert capsys.readouterr().out.strip() == "reps=3 below_parallel=1"

    def test_no_video_flag_sets_write_video_false(self, tmp_path, monkeypatch):
        calls = {}
        self._stub_run(monkeypatch, calls)
        video = tmp_path / "squat.mp4"
        video.write_bytes(b"")

        rc = main(["--input", str(video), "--no-video"])

        assert rc == 0
        assert calls["write_video"] is False

    def test_exercise_passed_through(self, tmp_path, monkeypatch):
        calls = {}
        self._stub_run(monkeypatch, calls)
        video = tmp_path / "squat.mp4"
        video.write_bytes(b"")

        rc = main(["--input", str(video), "--exercise", "squat"])

        assert rc == 0
        assert calls["exercise"] == "squat"
