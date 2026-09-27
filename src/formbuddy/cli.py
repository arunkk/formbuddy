"""Command-line interface for FormBuddy.

Parses flags, delegates to :func:`formbuddy.pipeline.run`, and prints a
one-line summary.  Exit codes: 0 success, 1 missing/unreadable input,
2 usage error (including an unsupported ``--exercise``).
"""

from __future__ import annotations

import argparse
import sys

from formbuddy.pipeline import ANALYZERS, run


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="formbuddy",
        description="Analyze weight-training form from video.",
    )
    parser.add_argument(
        "--input", required=True, help="path to the input video file"
    )
    parser.add_argument(
        "--exercise",
        default="squat",
        choices=ANALYZERS,
        help="exercise to analyze (default: %(default)s)",
    )
    parser.add_argument(
        "--output-dir",
        default="./out",
        help="directory for report and annotated video (default: %(default)s)",
    )
    parser.add_argument(
        "--no-video",
        action="store_true",
        help="write only the text/JSON reports, skip the annotated video",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        # argparse raises SystemExit(0) for --help (propagate it) and
        # SystemExit(2) for usage errors such as an unsupported
        # --exercise choice (return the code as main's exit status).
        if exc.code == 0:
            raise
        return exc.code if isinstance(exc.code, int) else 2

    try:
        report = run(
            args.input,
            exercise=args.exercise,
            output_dir=args.output_dir,
            write_video=not args.no_video,
        )
    except OSError as exc:
        # FileNotFoundError (unreadable input) and other OS errors such as
        # PermissionError creating the output dir both get a clean
        # one-line message instead of a traceback.
        print(f"error: {exc}", file=sys.stderr)
        return 1

    summary = report.summary
    print(f"reps={summary.total_reps} below_parallel={summary.reps_below_parallel}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
