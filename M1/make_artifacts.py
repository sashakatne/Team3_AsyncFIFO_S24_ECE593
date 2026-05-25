#!/usr/bin/env python3
"""Generate M1 root waveform artifacts from the Questa $monitor transcript.

The M1 root testbench is $monitor-only (no $dumpvars, no scoreboard), so the
authoritative sampled signal trace is the text transcript itself. This script:
  1. Parses transcript.txt for the $monitor lines of the form
         Time=<t>, wdata=<v>, rdata=<v>, wfull=<b>, rempty=<b>
  2. Emits waveform_samples.csv with one row per $monitor change event.
  3. Renders waveforms.svg (digital-waveform style, with bus values labelled)
     and converts to waveforms.png via sips (macOS built-in).
"""

from __future__ import annotations

import csv
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TRANSCRIPT = ROOT / "transcript.txt"
CSV_OUT = ROOT / "waveform_samples.csv"
SVG_OUT = ROOT / "waveforms.svg"
PNG_OUT = ROOT / "waveforms.png"

MONITOR_RE = re.compile(
    r"Time=\s*(\d+),\s*wdata=\s*(\d+),\s*rdata=\s*([0-9xz]+),"
    r"\s*wfull=([01]),\s*rempty=([01])"
)


def parse_monitor(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        raise SystemExit(f"missing transcript: {path}")
    rows: list[dict[str, object]] = []
    for line in path.read_text(errors="replace").splitlines():
        m = MONITOR_RE.search(line)
        if not m:
            continue
        t, wdata, rdata, wfull, rempty = m.groups()
        rows.append({
            "time_ns": int(t),
            "wdata": int(wdata),
            "rdata": rdata,
            "wfull": int(wfull),
            "rempty": int(rempty),
        })
    return rows


def write_csv(rows: list[dict[str, object]]) -> None:
    with CSV_OUT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["time_ns", "wdata", "rdata", "wfull", "rempty"])
        w.writeheader()
        w.writerows(rows)


def render_svg(rows: list[dict[str, object]]) -> None:
    if not rows:
        raise SystemExit("no $monitor samples parsed")

    t_max = rows[-1]["time_ns"]
    width = 1600
    height = 520
    left = 110
    right = width - 30
    plot_w = right - left

    def x_of(t: int) -> float:
        return left + (t / t_max) * plot_w if t_max else left

    # Signal tracks (top->bottom): wfull, rempty, wdata (bus), rdata (bus)
    tracks = [
        ("wfull",  "digital"),
        ("rempty", "digital"),
        ("wdata",  "bus"),
        ("rdata",  "bus"),
    ]
    track_h = 70
    track_gap = 20
    top_pad = 60
    bot_pad = 60

    parts: list[str] = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" font-family="Menlo, Consolas, monospace">'
    )
    # Background
    parts.append(f'<rect width="{width}" height="{height}" fill="#fafafa"/>')
    # Title
    parts.append(
        f'<text x="{width/2}" y="32" font-size="20" text-anchor="middle" '
        f'fill="#222">M1 root: $monitor sampled trace (0 – {t_max} ns)</text>'
    )

    # X axis ticks
    n_ticks = 8
    for i in range(n_ticks + 1):
        t = int(t_max * i / n_ticks)
        x = x_of(t)
        parts.append(
            f'<line x1="{x:.1f}" y1="{height-bot_pad}" x2="{x:.1f}" '
            f'y2="{height-bot_pad+6}" stroke="#888"/>'
        )
        parts.append(
            f'<text x="{x:.1f}" y="{height-bot_pad+22}" font-size="12" '
            f'text-anchor="middle" fill="#333">{t} ns</text>'
        )

    # Tracks
    for i, (name, kind) in enumerate(tracks):
        y_top = top_pad + i * (track_h + track_gap)
        y_bot = y_top + track_h
        # Track label
        parts.append(
            f'<text x="{left-12}" y="{(y_top+y_bot)/2+5}" font-size="14" '
            f'text-anchor="end" fill="#222">{name}</text>'
        )
        # Track baseline
        parts.append(
            f'<line x1="{left}" y1="{y_bot}" x2="{right}" y2="{y_bot}" '
            f'stroke="#bbb"/>'
        )

        if kind == "digital":
            # Square-wave style: y_top = high, y_bot = low
            prev_val = rows[0][name]
            prev_x = x_of(rows[0]["time_ns"])
            for r in rows[1:]:
                cur_x = x_of(r["time_ns"])
                y = y_top if prev_val else y_bot
                parts.append(
                    f'<line x1="{prev_x:.1f}" y1="{y}" x2="{cur_x:.1f}" '
                    f'y2="{y}" stroke="#0066cc" stroke-width="2"/>'
                )
                if r[name] != prev_val:
                    parts.append(
                        f'<line x1="{cur_x:.1f}" y1="{y_top}" '
                        f'x2="{cur_x:.1f}" y2="{y_bot}" '
                        f'stroke="#0066cc" stroke-width="2"/>'
                    )
                prev_val = r[name]
                prev_x = cur_x
            # tail to end
            y = y_top if prev_val else y_bot
            parts.append(
                f'<line x1="{prev_x:.1f}" y1="{y}" x2="{right}" y2="{y}" '
                f'stroke="#0066cc" stroke-width="2"/>'
            )
        else:  # bus
            # Filled "value box" between transitions, with text labels.
            prev_val = rows[0][name]
            prev_x = x_of(rows[0]["time_ns"])
            box_top = y_top + 8
            box_bot = y_bot - 8
            mid_y = (box_top + box_bot) / 2
            for r in rows[1:]:
                cur_x = x_of(r["time_ns"])
                # value-box outline
                parts.append(
                    f'<polygon points="{prev_x:.1f},{mid_y} '
                    f'{prev_x+4:.1f},{box_top} {cur_x-4:.1f},{box_top} '
                    f'{cur_x:.1f},{mid_y} {cur_x-4:.1f},{box_bot} '
                    f'{prev_x+4:.1f},{box_bot}" fill="#eef3ff" '
                    f'stroke="#0066cc" stroke-width="1"/>'
                )
                # value label (only if box wide enough)
                if cur_x - prev_x > 22:
                    parts.append(
                        f'<text x="{(prev_x+cur_x)/2:.1f}" y="{mid_y+4:.1f}" '
                        f'font-size="11" text-anchor="middle" fill="#114">'
                        f'{prev_val}</text>'
                    )
                prev_x = cur_x
                prev_val = r[name]
            # tail box
            parts.append(
                f'<polygon points="{prev_x:.1f},{mid_y} '
                f'{prev_x+4:.1f},{box_top} {right-4:.1f},{box_top} '
                f'{right:.1f},{mid_y} {right-4:.1f},{box_bot} '
                f'{prev_x+4:.1f},{box_bot}" fill="#eef3ff" '
                f'stroke="#0066cc" stroke-width="1"/>'
            )
            if right - prev_x > 22:
                parts.append(
                    f'<text x="{(prev_x+right)/2:.1f}" y="{mid_y+4:.1f}" '
                    f'font-size="11" text-anchor="middle" fill="#114">'
                    f'{prev_val}</text>'
                )

    # Annotate key events
    events: list[tuple[int, str]] = []
    first_full = next((r for r in rows if r["wfull"] == 1), None)
    if first_full:
        events.append((first_full["time_ns"], "wfull asserts"))
    last_empty = next((r for r in reversed(rows) if r["rempty"] == 0), None)
    final_empty = next((r for r in rows if r is not rows[0]
                        and r["rempty"] == 1
                        and r["time_ns"] > (last_empty["time_ns"] if last_empty else 0)), None)
    if final_empty:
        events.append((final_empty["time_ns"], "rempty re-asserts"))
    for t, label in events:
        x = x_of(t)
        parts.append(
            f'<line x1="{x:.1f}" y1="{top_pad-10}" x2="{x:.1f}" '
            f'y2="{height-bot_pad}" stroke="#cc0033" stroke-dasharray="4 4" '
            f'stroke-width="1"/>'
        )
        parts.append(
            f'<text x="{x:.1f}" y="{top_pad-16}" font-size="11" '
            f'text-anchor="middle" fill="#cc0033">{label} @ {t} ns</text>'
        )

    parts.append("</svg>")
    SVG_OUT.write_text("\n".join(parts))


def convert_with_sips(svg: Path, png: Path) -> None:
    subprocess.run(
        ["sips", "-s", "format", "png", str(svg), "--out", str(png)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main() -> None:
    rows = parse_monitor(TRANSCRIPT)
    write_csv(rows)
    render_svg(rows)
    convert_with_sips(SVG_OUT, PNG_OUT)
    print(f"wrote {CSV_OUT.name} ({len(rows)} samples)")
    print(f"wrote {SVG_OUT.name}")
    print(f"wrote {PNG_OUT.name}")


if __name__ == "__main__":
    main()
