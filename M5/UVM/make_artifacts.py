#!/usr/bin/env python3
"""Generate M5/UVM waveform artifacts from the farm dump.vcd."""

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

TRACKED = {
    "winc": "digital",
    "rinc": "digital",
    "wFull": "digital",
    "rEmpty": "digital",
    "wHalfFull": "digital",
    "rHalfEmpty": "digital",
    "wData": "bus",
    "rData": "bus",
}
TRACK_ORDER = ["winc", "wFull", "wHalfFull", "wData", "rinc", "rEmpty", "rHalfEmpty", "rData"]
DUT_SCOPE = ["tb_top", "DUT"]
VAR_RE = re.compile(r"\$var\s+\S+\s+(\d+)\s+(\S+)\s+(\S+)(?:\s+\[(\d+)(?::\d+)?\])?\s+\$end")
WINDOW_END_NS = 2500


def bus_value(bits: list[str]) -> str:
    if any(bit.lower() in ("x", "z") for bit in bits):
        return "x"
    return str(int("".join(bits), 2))


def parse_vcd() -> tuple[list[dict[str, str]], int]:
    if not VCD.exists():
        raise SystemExit(f"missing VCD: {VCD}")

    code_to_scalar: dict[str, str] = {}
    code_to_bit: dict[str, tuple[str, int]] = {}
    scope_stack: list[str] = []
    bits = {"wData": ["0"] * 8}
    current = {name: "0" for name in TRACKED}
    rows: list[dict[str, str]] = []

    in_header = True
    time_ns = 0
    last_emit_time = -1
    pending = False

    for raw in VCD.read_text(errors="replace").splitlines():
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
            if match and scope_stack == DUT_SCOPE:
                width_s, code, name, bit_s = match.groups()
                if name in TRACKED:
                    width = int(width_s)
                    if width == 1 and bit_s is not None:
                        code_to_bit[code] = (name, int(bit_s))
                    else:
                        code_to_scalar[code] = name
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
            value, code = line[0], line[1:]
            name = code_to_scalar.get(code)
            if name is not None:
                if current[name] != value:
                    current[name] = value
                    pending = True
                continue
            bit_ref = code_to_bit.get(code)
            if bit_ref is not None:
                name, bit = bit_ref
                bit_index = len(bits[name]) - 1 - bit
                if bits[name][bit_index] != value:
                    bits[name][bit_index] = value
                    next_value = bus_value(bits[name])
                    if current[name] != next_value:
                        current[name] = next_value
                        pending = True
                continue

        if line[0] in "bB":
            parts = line[1:].split()
            if len(parts) != 2:
                continue
            value_bits, code = parts
            name = code_to_scalar.get(code)
            if name is None:
                continue
            value = "x" if any(ch in value_bits.lower() for ch in "xz") else str(int(value_bits, 2))
            if current[name] != value:
                current[name] = value
                pending = True

    if pending:
        rows.append({"time_ns": str(time_ns), **current})

    return rows, time_ns


def write_csv(rows: list[dict[str, str]]) -> None:
    with CSV_OUT.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["time_ns"] + list(TRACKED), lineterminator="\n")
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
    height = top_pad + len(TRACK_ORDER) * (track_h + track_gap) + bot_pad

    def x_of(t: int) -> float:
        return left + (t / t_max) * plot_w if t_max else left

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" font-family="Menlo, Consolas, monospace">',
        f'<rect width="{width}" height="{height}" fill="#fafafa"/>',
        f'<text x="{width / 2}" y="34" font-size="18" text-anchor="middle" fill="#222">'
        f"M5/UVM post-fix farm run, windowed 0 - {t_max} ns</text>",
    ]

    for i in range(11):
        tick = int(t_max * i / 10)
        x = x_of(tick)
        parts.append(f'<line x1="{x:.1f}" y1="{height - bot_pad}" x2="{x:.1f}" y2="{height - bot_pad + 6}" stroke="#888"/>')
        parts.append(f'<text x="{x:.1f}" y="{height - bot_pad + 22}" font-size="11" text-anchor="middle" fill="#333">{tick} ns</text>')

    for track_index, name in enumerate(TRACK_ORDER):
        kind = TRACKED[name]
        y_top = top_pad + track_index * (track_h + track_gap)
        y_mid = y_top + track_h / 2
        y_bot = y_top + track_h
        parts.append(f'<text x="{left - 12}" y="{y_mid + 5:.1f}" font-size="13" text-anchor="end" fill="#222">{name}</text>')
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
                parts.append(f'<line x1="{x0:.1f}" y1="{y:.1f}" x2="{x1:.1f}" y2="{y:.1f}" stroke="{color}" stroke-width="2"/>')
                if idx + 1 < len(rows):
                    next_value = rows[idx + 1][name]
                    next_y = y_top + 10 if next_value == "1" else y_bot - 10
                    parts.append(f'<line x1="{x1:.1f}" y1="{y:.1f}" x2="{x1:.1f}" y2="{next_y:.1f}" stroke="#777" stroke-width="1"/>')
            else:
                parts.append(f'<rect x="{x0:.1f}" y="{y_top + 8:.1f}" width="{max(x1 - x0, 1):.1f}" height="{track_h - 16:.1f}" fill="#eef3ff" stroke="#0066cc" stroke-width="0.8"/>')
                if x1 - x0 > 36:
                    parts.append(f'<text x="{(x0 + x1) / 2:.1f}" y="{y_mid + 4:.1f}" font-size="10" text-anchor="middle" fill="#114">{value}</text>')

    parts.append("</svg>")
    SVG_OUT.write_text("\n".join(parts) + "\n")


def convert_png() -> None:
    if shutil.which("sips") is None:
        print("sips not found; SVG generated but PNG conversion skipped")
        return
    subprocess.run(["sips", "-s", "format", "png", str(SVG_OUT), "--out", str(PNG_OUT)], check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    rows, t_max = parse_vcd()
    write_csv(rows)
    render_svg(rows, t_max)
    convert_png()
    print(f"wrote {CSV_OUT.name}, {SVG_OUT.name}, {PNG_OUT.name}")
    print(f"parsed {len(rows)} tracked changes through {t_max} ns")


if __name__ == "__main__":
    main()
