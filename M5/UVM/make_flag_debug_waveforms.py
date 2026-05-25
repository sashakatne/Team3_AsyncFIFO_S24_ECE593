#!/usr/bin/env python3
"""Render focused flag debug waveforms from the farm flag_threshold.vcd."""

from __future__ import annotations

import csv
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VCD = ROOT / "flag_threshold.vcd"
CSV_OUT = ROOT / "flag_debug_samples.csv"
SVG_OUT = ROOT / "flag_debug_waveforms.svg"
PNG_OUT = ROOT / "flag_debug_waveforms.png"
WRITE_ZOOM_SVG = ROOT / "flag_debug_write_thresholds.svg"
WRITE_ZOOM_PNG = ROOT / "flag_debug_write_thresholds.png"
READ_ZOOM_SVG = ROOT / "flag_debug_read_thresholds.svg"
READ_ZOOM_PNG = ROOT / "flag_debug_read_thresholds.png"

TRACKS = [
    ("wclk", "digital", ["flag_threshold_tb"], "wclk", "wclk"),
    ("rclk", "digital", ["flag_threshold_tb"], "rclk", "rclk"),
    ("wptr_dec", "bus", ["flag_threshold_tb", "DUT"], "wptr", "wptr dec"),
    ("rptr_dec", "bus", ["flag_threshold_tb", "DUT"], "rptr", "rptr dec"),
    ("wen", "digital", ["flag_threshold_tb"], "winc", "wen"),
    ("ren", "digital", ["flag_threshold_tb"], "rinc", "ren"),
    ("wFull", "digital", ["flag_threshold_tb"], "wFull", "wFull"),
    ("wHalfFull", "digital", ["flag_threshold_tb"], "wHalfFull", "wHalfFull"),
    ("rEmpty", "digital", ["flag_threshold_tb"], "rEmpty", "rEmpty"),
    ("rHalfEmpty", "digital", ["flag_threshold_tb"], "rHalfEmpty", "rHalfEmpty"),
]

TRACK_BY_SIGNAL = {(tuple(scope), signal): key for key, _kind, scope, signal, _label in TRACKS}
KIND_BY_KEY = {key: kind for key, kind, _scope, _signal, _label in TRACKS}
LABEL_BY_KEY = {key: label for key, _kind, _scope, _signal, label in TRACKS}
VAR_RE = re.compile(r"\$var\s+\S+\s+\d+\s+(\S+)\s+(\S+)(?:\s+\S+)?\s+\$end")
TIME_UNITS_TO_NS = {
    "1ps": 0.001,
    "10ps": 0.01,
    "100ps": 0.1,
    "1ns": 1.0,
    "10ns": 10.0,
    "100ns": 100.0,
}


def parse_vcd() -> tuple[list[dict[str, str]], float, dict[str, list[float]]]:
    if not VCD.exists():
        raise SystemExit(f"missing VCD: {VCD}")

    code_to_key: dict[str, str] = {}
    current = {key: "0" for key, *_rest in TRACKS}
    rows: list[dict[str, str]] = []
    rising_edges: dict[str, list[float]] = {"wclk": [], "rclk": []}
    scope_stack: list[str] = []
    in_header = True
    scale_to_ns = 1.0
    t_raw = 0
    pending = False
    last_emit = -1

    for raw in VCD.read_text(errors="replace").splitlines():
        line = raw.strip()
        if not line:
            continue
        if in_header:
            if line in TIME_UNITS_TO_NS:
                scale_to_ns = TIME_UNITS_TO_NS[line]
                continue
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
                code, signal = match.groups()
                key = TRACK_BY_SIGNAL.get((tuple(scope_stack), signal))
                if key is not None:
                    code_to_key[code] = key
                continue
            if line == "$enddefinitions $end":
                in_header = False
            continue

        if line.startswith("#"):
            if pending and t_raw != last_emit:
                rows.append({"time_ns": f"{t_raw * scale_to_ns:g}", **current})
                last_emit = t_raw
                pending = False
            t_raw = int(line[1:])
            continue

        if line[0] in "01xz":
            key = code_to_key.get(line[1:])
            if key is None:
                continue
            value = line[0]
            old = current[key]
            if old != value:
                current[key] = value
                pending = True
                if key in rising_edges and old == "0" and value == "1":
                    rising_edges[key].append(t_raw * scale_to_ns)
            continue

        if line[0] in "bB":
            parts = line[1:].split()
            if len(parts) != 2:
                continue
            bits, code = parts
            key = code_to_key.get(code)
            if key is None:
                continue
            value = "x" if any(ch in bits.lower() for ch in "xz") else str(int(bits, 2))
            if current[key] != value:
                current[key] = value
                pending = True

    if pending:
        rows.append({"time_ns": f"{t_raw * scale_to_ns:g}", **current})
    return rows, t_raw * scale_to_ns, rising_edges


def write_csv(rows: list[dict[str, str]]) -> None:
    fields = ["time_ns"] + [key for key, *_rest in TRACKS]
    with CSV_OUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def window_rows(rows: list[dict[str, str]], start_ns: float, end_ns: float) -> list[dict[str, str]]:
    seed = rows[0].copy()
    for row in rows:
        if float(row["time_ns"]) <= start_ns:
            seed = row.copy()
        else:
            break
    seed["time_ns"] = f"{start_ns:g}"
    out = [seed]
    for row in rows:
        t = float(row["time_ns"])
        if start_ns < t < end_ns:
            out.append(row)
    tail = out[-1].copy()
    tail["time_ns"] = f"{end_ns:g}"
    out.append(tail)
    return out


def render_svg(rows: list[dict[str, str]], start_ns: float, end_ns: float, rising_edges: dict[str, list[float]], svg_out: Path, png_out: Path, title: str) -> None:
    width = 1900
    left = 145
    right = width - 40
    plot_w = right - left
    top = 82
    bottom = 72
    track_h = 38
    gap = 10
    keys = [key for key, *_rest in TRACKS]
    height = top + len(keys) * (track_h + gap) + bottom
    span = end_ns - start_ns

    def x_of(t: float) -> float:
        return left + ((t - start_ns) / span) * plot_w if span else left

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" font-family="Menlo, Consolas, monospace">',
        f'<rect width="{width}" height="{height}" fill="#fbfbfb"/>',
        f'<text x="{width / 2}" y="30" font-size="18" text-anchor="middle" fill="#222">{title}</text>',
        f'<text x="{width / 2}" y="52" font-size="12" text-anchor="middle" fill="#555">'
        "Red ticks mark rising clock edges. Pointer tracks show full binary pointer values in decimal.</text>",
    ]

    for i in range(11):
        tick = start_ns + ((end_ns - start_ns) * i / 10)
        x = x_of(tick)
        parts.append(f'<line x1="{x:.1f}" y1="{height - bottom}" x2="{x:.1f}" y2="{height - bottom + 6}" stroke="#888"/>')
        parts.append(f'<text x="{x:.1f}" y="{height - bottom + 22}" font-size="11" text-anchor="middle" fill="#333">{tick:.0f} ns</text>')

    for idx, key in enumerate(keys):
        kind = KIND_BY_KEY[key]
        label = LABEL_BY_KEY[key]
        y0 = top + idx * (track_h + gap)
        y1 = y0 + track_h
        mid = (y0 + y1) / 2
        parts.append(f'<text x="{left - 12}" y="{mid + 5:.1f}" font-size="13" text-anchor="end" fill="#222">{label}</text>')
        parts.append(f'<line x1="{left}" y1="{y1}" x2="{right}" y2="{y1}" stroke="#bbb"/>')
        if key in rising_edges:
            for edge_t in rising_edges[key]:
                if start_ns <= edge_t <= end_ns:
                    x = x_of(edge_t)
                    parts.append(f'<line x1="{x:.1f}" y1="{y0 + 2}" x2="{x:.1f}" y2="{y1 - 2}" stroke="#d72638" stroke-width="1.2" opacity="0.65"/>')

        seg_start = start_ns
        seg_value = rows[0][key]
        segments: list[tuple[float, float, str]] = []
        for row in rows[1:]:
            row_time = float(row["time_ns"])
            row_value = row[key]
            if row_value != seg_value:
                segments.append((seg_start, row_time, seg_value))
                seg_start = row_time
                seg_value = row_value
        segments.append((seg_start, end_ns, seg_value))

        for t0, t1, value in segments:
            if t1 <= t0:
                continue
            x0, x1 = x_of(t0), x_of(t1)
            if kind == "digital":
                y = y0 + 9 if value == "1" else y1 - 9
                color = "#006600" if value == "1" else "#333"
                parts.append(f'<line x1="{x0:.1f}" y1="{y:.1f}" x2="{x1:.1f}" y2="{y:.1f}" stroke="{color}" stroke-width="2"/>')
            else:
                parts.append(f'<rect x="{x0:.1f}" y="{y0 + 8:.1f}" width="{max(x1 - x0, 1):.1f}" height="{track_h - 16:.1f}" fill="#eef3ff" stroke="#2d7ff9" stroke-width="0.8"/>')
                if x1 - x0 > 34:
                    parts.append(f'<text x="{(x0 + x1) / 2:.1f}" y="{mid + 4:.1f}" font-size="10" text-anchor="middle" fill="#114">{value}</text>')

    parts.append("</svg>")
    svg_out.write_text("\n".join(parts) + "\n")
    if shutil.which("sips") is not None:
        subprocess.run(["sips", "-s", "format", "png", str(svg_out), "--out", str(png_out)], check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    rows, t_max, rising_edges = parse_vcd()
    write_csv(rows)
    render_svg(window_rows(rows, 0, t_max), 0, t_max, rising_edges, SVG_OUT, PNG_OUT, f"M5 directed flag debug waveform from farm VCD, 0 - {t_max:.0f} ns")
    render_svg(window_rows(rows, 560, 1085), 560, 1085, rising_edges, WRITE_ZOOM_SVG, WRITE_ZOOM_PNG, "M5 write-side threshold zoom: half-full and full")
    render_svg(window_rows(rows, 1720, 2470), 1720, 2470, rising_edges, READ_ZOOM_SVG, READ_ZOOM_PNG, "M5 read-side threshold zoom: half-empty and empty")
    print(
        "wrote flag_debug_samples.csv, flag_debug_waveforms.svg, flag_debug_waveforms.png, "
        "flag_debug_write_thresholds.svg, flag_debug_write_thresholds.png, "
        "flag_debug_read_thresholds.svg, flag_debug_read_thresholds.png"
    )
    print(f"parsed {len(rows)} rows through {t_max:.0f} ns")
    print(f"rising edges: wclk={len(rising_edges['wclk'])}, rclk={len(rising_edges['rclk'])}")


if __name__ == "__main__":
    main()
