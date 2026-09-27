"""Turn a SquatReport into JSON and human-readable text files."""

from __future__ import annotations

import dataclasses
import json
from pathlib import Path

from formbuddy.analyzers.squat import SquatReport


class ReportBuilder:
    """Write a SquatReport to ``report.json`` and ``report.txt``."""

    def build(self, report: SquatReport, out_dir: str) -> dict:
        """Write report files into *out_dir* (created if missing).

        Returns the JSON dict that was written to ``report.json``.
        """
        out = Path(out_dir)
        out.mkdir(parents=True, exist_ok=True)

        data = {
            "exercise": report.exercise,
            "video_meta": report.video_meta,
            "summary": dataclasses.asdict(report.summary),
            "reps": [dataclasses.asdict(rep) for rep in report.reps],
            "warnings": report.warnings,
        }

        (out / "report.json").write_text(
            json.dumps(data, indent=2) + "\n", encoding="utf-8"
        )
        (out / "report.txt").write_text(
            self._render_text(report), encoding="utf-8"
        )
        return data

    @staticmethod
    def _render_text(report: SquatReport) -> str:
        """Render the report as a header, summary lines, then one line
        per rep."""
        s = report.summary
        lines = [
            f"Squat form report: {s.total_reps} reps ({s.partial_reps} partial)",
            f"Total reps: {s.total_reps}",
            f"Partial reps: {s.partial_reps}",
            f"Reps below parallel: {s.reps_below_parallel}",
            f"Reps at parallel: {s.reps_at_parallel}",
            f"Reps above parallel: {s.reps_above_parallel}",
            f"Avg eccentric seconds: {s.avg_eccentric_seconds:.2f}",
            f"Avg concentric seconds: {s.avg_concentric_seconds:.2f}",
            f"Avg bottom pause seconds: {s.avg_bottom_pause_seconds:.2f}",
            f"Avg torso angle at bottom: {s.avg_torso_angle_at_bottom:.2f}",
            f"Max torso angle: {s.max_torso_angle:.2f}",
        ]
        for rep in report.reps:
            lines.append(
                f"#{rep.rep_number} depth={rep.depth} "
                f"ecc={rep.eccentric_seconds:.2f} "
                f"conc={rep.concentric_seconds:.2f} "
                f"pause={rep.bottom_pause_seconds:.2f} "
                f"faults={rep.faults} partial={rep.partial}"
            )
        return "\n".join(lines) + "\n"
