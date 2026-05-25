#!/usr/bin/env python3
"""Generate M3/CLASS waveform artifacts from dump.vcd.

Run this after a successful Questa batch run from M3/CLASS:

    vsim -c -do 'do run.do; quit -f' 2>&1 | tee transcript_farm.txt
    python3 make_artifacts.py

The script parses DUT-port signals from async_fifo_top.DUT, writes
waveform_samples.csv, renders a compact SVG waveform window, and converts
the SVG to PNG with macOS sips when available.
"""

from __future__ import annotations

import csv
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VCD = ROOT / "dump.vcd"
CSV_OUT = ROOT / "waveform_samples.csv"
SVG_OUT = ROOT / "waveforms.svg"
PNG_OUT = ROOT / "waveforms.png"

WINDOW_END_NS = 2500

TRACKED: dict[str, str] = {
    "winc": "digital",
    "rinc": "digital",
    "wFull": "digital",
    "rEmpty": "digital",
    "wHalfFull": "digital",
    "rHalfEmpty": "digital",
    "wData": "bus",
    "rData": "bus",
}

DUT_SCOPE = ["async_fifo_top", "DUT"]
VAR_RE = re.compile(r"\$var\s+\S+\s+(\d+)\s+(\S+)\s+(\S+)(?:\s+\S+)?\s+\$end")


def parse_vcd(path: Path) -> tuple[list[dict[str, str]], int]:
    if not path.exists():
        raise SystemExit(f"missing VCD: {path}")

    code_to_name: dict[str, str] = {}
    scope_stack: list[str] = []
    current: dict[str, str] = {name: "0" for name in TRACKED}
    rows: list[dict[str, str]] = []

    in_header = True
    time_ns = 0
    last_emit_time = -1
    pending = False

    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line:
            continue

        if in_header:
            if line.startswith("$scope "):
                fields = line.split()
                if len(fields) >= 3:
                    scope_stack.append(fields[2])
                continue
            if line.startswith("$upscope"):
                if scope_stack:
                    scope_stack.pop()
                continue
            match = VAR_RE.match(line)
            if match:
                _width, code, name = match.groups()
                if scope_stack == DUT_SCOPE and name in TRACKED:
                    code_to_name[code] = name
                continue
            if line == "$enddefinitions $end":
                in_header = False
            continue

        if line.startswith("#"):
            if pending and time_ns != last_emit_time:
                rows.append({"time_ns": str(time_ns), **current})
                last_emit_time = time_ns
                pending = False
            time_ns = int(line[1:])
            continue

        if line[0] in "01xz":
            code = line[1:]
            name = code_to_name.get(code)
            if name is None:
                continue
            value = line[0]
            if current[name] != value:
                current[name] = value
                pending = True
            continue

        if line[0] in "bB":
            parts = line[1:].split()
            if len(parts) != 2:
                continue
            bits, code = parts
            name = code_to_name.get(code)
            if name is None:
                continue
            value = "x" if any(ch in bits.lower() for ch in "xz") else str(int(bits, 2))
            if current[name] != value:
                current[name] = value
                pending = True

    if pending:
        rows.append({"time_ns": str(time_ns), **current})

    return rows, time_ns


def write_csv(rows: list[dict[str, str]]) -> None:
    fields = ["time_ns"] + list(TRACKED.keys())
    with CSV_OUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def render_svg(rows: list[dict[str, str]], t_max: int) -> None:
    if not rows:
        raise SystemExit("no tracked VCD samples parsed")

    win_end = min(WINDOW_END_NS, t_max)
    windowed: list[dict[str, str]] = []
    for row in rows:
        if int(row["time_ns"]) <= win_end:
            windowed.append(row)
        else:
            windowed.append({**row, "time_ns": str(win_end)})
            break

    rows = windowed
    t_max = win_end

    width = 1800
    left = 130
    right = width - 30
    plot_w = right - left
    top_pad = 70
    bot_pad = 70
    track_h = 42
    track_gap = 10
    track_order = [
        "winc",
        "wFull",
        "wHalfFull",
        "wData",
        "rinc",
        "rEmpty",
        "rHalfEmpty",
        "rData",
    ]
    height = top_pad + len(track_order) * (track_h + track_gap) + bot_pad

    def x_of(t: int) -> float:
        return left + (t / t_max) * plot_w if t_max else left

    parts: list[str] = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" font-family="Menlo, Consolas, monospace">'
    )
    parts.append(f'<rect width="{width}" height="{height}" fill="#fafafa"/>')
    parts.append(
        f'<text x="{width / 2}" y="34" font-size="18" text-anchor="middle" '
        f'fill="#222">M3/CLASS post-fix run, windowed 0 - {t_max} ns</text>'
    )

    for i in range(11):
        tick = int(t_max * i / 10)
        x = x_of(tick)
        parts.append(
            f'<line x1="{x:.1f}" y1="{height - bot_pad}" x2="{x:.1f}" '
            f'y2="{height - bot_pad + 6}" stroke="#888"/>'
        )
        parts.append(
            f'<text x="{x:.1f}" y="{height - bot_pad + 22}" font-size="11" '
            f'text-anchor="middle" fill="#333">{tick} ns</text>'
        )

    for track_index, name in enumerate(track_order):
        kind = TRACKED[name]
        y_top = top_pad + track_index * (track_h + track_gap)
        y_mid = y_top + track_h / 2
        y_bot = y_top + track_h
        parts.append(
            f'<text x="{left - 12}" y="{y_mid + 5:.1f}" font-size="13" '
            f'text-anchor="end" fill="#222">{name}</text>'
        )
        parts.append(f'<line x1="{left}" y1="{y_bot}" x2="{right}" y2="{y_bot}" stroke="#bbb"/>')

        for idx, row in enumerate(rows):
            t0 = int(row["time_ns"])
            t1 = int(rows[idx + 1]["time_ns"]) if idx + 1 < len(rows) else t_max
            if t1 <= t0:
                continue
            x0 = x_of(t0)
            x1 = x_of(t1)
            value = row[name]

            if kind == "digital":
                y = y_top + 10 if value == "1" else y_bot - 10
                color = "#006600" if value == "1" else "#333"
                parts.append(
                    f'<line x1="{x0:.1f}" y1="{y:.1f}" x2="{x1:.1f}" y2="{y:.1f}" '
                    f'stroke="{color}" stroke-width="2"/>'
                )
                if idx + 1 < len(rows):
                    next_value = rows[idx + 1][name]
                    next_y = y_top + 10 if next_value == "1" else y_bot - 10
                    parts.append(
                        f'<line x1="{x1:.1f}" y1="{y:.1f}" x2="{x1:.1f}" y2="{next_y:.1f}" '
                        f'stroke="#777" stroke-width="1"/>'
                    )
            else:
                parts.append(
                    f'<rect x="{x0:.1f}" y="{y_top + 8:.1f}" width="{max(x1 - x0, 1):.1f}" '
                    f'height="{track_h - 16:.1f}" fill="#eef3ff" stroke="#0066cc" stroke-width="0.8"/>'
                )
                if x1 - x0 > 36:
                    parts.append(
                        f'<text x="{(x0 + x1) / 2:.1f}" y="{y_mid + 4:.1f}" font-size="10" '
                        f'text-anchor="middle" fill="#114">{value}</text>'
                    )

    parts.append("</svg>")
    SVG_OUT.write_text("\n".join(parts) + "\n")


def convert_png() -> None:
    if shutil.which("sips") is None:
        print("sips not found; SVG generated but PNG conversion skipped")
        return
    subprocess.run(
        ["sips", "-s", "format", "png", str(SVG_OUT), "--out", str(PNG_OUT)],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def main() -> None:
    rows, t_max = parse_vcd(VCD)
    write_csv(rows)
    render_svg(rows, t_max)
    convert_png()
    print(f"wrote {CSV_OUT.name}, {SVG_OUT.name}, {PNG_OUT.name}")
    print(f"parsed {len(rows)} tracked changes through {t_max} ns")


if __name__ == "__main__":
    main()
