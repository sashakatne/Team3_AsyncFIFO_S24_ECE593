#!/usr/bin/env python3
"""Generate M1/ConventionalTB waveform artifacts from the farm VCD.

The ConventionalTB testbench dumps a VCD via $dumpfile/$dumpvars. This script:
  1. Parses dump.vcd, tracking the top-level handshake signals (winc, rinc,
     wData, rData, wFull, rEmpty, wHalfFull, rHalfEmpty, error_flag,
     w_count, r_count).
  2. Emits waveform_samples.csv: one row whenever any tracked signal changes
     (clocks excluded -- their edges would dominate the file).
  3. Renders waveforms.svg covering an informative window of the run
     (default 0 – 2500 ns, capturing reset deassert + first fill + first
     wFull) with bus values labelled where stable, then converts to
     waveforms.png via sips (macOS built-in). The full trace is preserved
     in waveform_samples.csv; the windowed PNG is only for at-a-glance
     review since the full 17930 ns of two-burst random traffic is too
     dense for a single static plot.
"""

from __future__ import annotations

import csv
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VCD = ROOT / "dump.vcd"
CSV_OUT = ROOT / "waveform_samples.csv"
SVG_OUT = ROOT / "waveforms.svg"
PNG_OUT = ROOT / "waveforms.png"

WINDOW_END_NS = 2500

TRACKED = {
    "winc":        "digital",
    "rinc":        "digital",
    "wFull":       "digital",
    "rEmpty":      "digital",
    "wHalfFull":   "digital",
    "rHalfEmpty":  "digital",
    "error_flag":  "digital",
    "wData":       "bus",
    "rData":       "bus",
    "w_count":     "bus",
    "r_count":     "bus",
}

VAR_RE = re.compile(r"\$var\s+\S+\s+(\d+)\s+(\S+)\s+(\S+)(?:\s+\S+)?\s+\$end")


def parse_vcd(path: Path) -> tuple[list[dict[str, str]], int]:
    """Return (rows, t_max). Each row has 'time_ns' plus current TRACKED values."""
    if not path.exists():
        raise SystemExit(f"missing VCD: {path}")

    code_to_name: dict[str, str] = {}
    scope_stack: list[str] = []
    in_header = True
    current: dict[str, str] = {n: "0" for n in TRACKED}
    rows: list[dict[str, str]] = []
    t = 0
    last_t = -1
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
            m = VAR_RE.match(line)
            if m:
                _width, code, name = m.groups()
                if scope_stack == ["top"] and name in TRACKED:
                    code_to_name[code] = name
            if line == "$enddefinitions $end":
                in_header = False
                # snapshot at t=0 (after $dumpvars block emits initial values)
            continue

        if line.startswith("#"):
            # time change -- flush a snapshot if any tracked signal changed since last emit
            if pending and t != last_t:
                rows.append({"time_ns": str(t), **current})
                last_t = t
                pending = False
            t = int(line[1:])
            continue

        if line[0] in "01xz":
            code = line[1:]
            val = line[0]
            name = code_to_name.get(code)
            if name is None:
                continue
            if current[name] != val:
                current[name] = val
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
            # decimal value for bus, but keep 'x'/'z' literal if present
            if any(c in bits for c in "xz"):
                val = "x"
            else:
                val = str(int(bits, 2))
            if current[name] != val:
                current[name] = val
                pending = True
            continue

    if pending:
        rows.append({"time_ns": str(t), **current})

    return rows, t


def write_csv(rows: list[dict[str, str]]) -> None:
    fields = ["time_ns"] + list(TRACKED.keys())
    with CSV_OUT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def render_svg(rows: list[dict[str, str]], t_max: int) -> None:
    if not rows:
        raise SystemExit("no VCD samples parsed -- check tracked signal names")

    # Window the trace for the PNG so individual edges stay readable.
    # The CSV still contains all events; only the plot is cropped.
    win_end = min(WINDOW_END_NS, t_max)
    # Keep rows up to (and one row past) win_end so the last visible edge
    # has somewhere to draw to.
    windowed: list[dict[str, str]] = []
    for r in rows:
        if int(r["time_ns"]) <= win_end:
            windowed.append(r)
        else:
            # one row past the window so trailing values render correctly
            windowed.append({**r, "time_ns": str(win_end)})
            break
    rows = windowed
    t_max = win_end

    width = 1800
    track_order = [
        "winc", "wFull", "wHalfFull", "wData", "w_count",
        "rinc", "rEmpty", "rHalfEmpty", "rData", "r_count",
        "error_flag",
    ]
    track_h = 42
    track_gap = 10
    top_pad = 70
    bot_pad = 70
    height = top_pad + len(track_order) * (track_h + track_gap) + bot_pad

    left = 130
    right = width - 30
    plot_w = right - left

    def x_of(t: int) -> float:
        return left + (t / t_max) * plot_w if t_max else left

    parts: list[str] = []
    parts.append(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" font-family="Menlo, Consolas, monospace">'
    )
    parts.append(f'<rect width="{width}" height="{height}" fill="#fafafa"/>')
    parts.append(
        f'<text x="{width/2}" y="34" font-size="18" text-anchor="middle" '
        f'fill="#222">M1/ConventionalTB: scoreboard run, '
        f'windowed 0 – {t_max} ns (full trace in CSV)</text>'
    )

    # X axis ticks
    n_ticks = 10
    for i in range(n_ticks + 1):
        t = int(t_max * i / n_ticks)
        x = x_of(t)
        parts.append(
            f'<line x1="{x:.1f}" y1="{height-bot_pad}" x2="{x:.1f}" '
            f'y2="{height-bot_pad+6}" stroke="#888"/>'
        )
        parts.append(
            f'<text x="{x:.1f}" y="{height-bot_pad+22}" font-size="11" '
            f'text-anchor="middle" fill="#333">{t} ns</text>'
        )

    # Per-track rendering
    for ti, name in enumerate(track_order):
        kind = TRACKED[name]
        y_top = top_pad + ti * (track_h + track_gap)
        y_bot = y_top + track_h
        # Label
        parts.append(
            f'<text x="{left-12}" y="{(y_top+y_bot)/2+5}" font-size="13" '
            f'text-anchor="end" fill="#222">{name}</text>'
        )
        parts.append(
            f'<line x1="{left}" y1="{y_bot}" x2="{right}" y2="{y_bot}" '
            f'stroke="#bbb"/>'
        )

        # extract signal trace as (time, value) sorted list
        prev_val = "0"
        prev_x = left
        if kind == "digital":
            color = "#cc3300" if name == "error_flag" else "#0066cc"
            for r in rows:
                v = r[name]
                t = int(r["time_ns"])
                cur_x = x_of(t)
                y = y_top if prev_val in ("1", "x") and prev_val != "0" else y_bot
                parts.append(
                    f'<line x1="{prev_x:.1f}" y1="{y}" x2="{cur_x:.1f}" '
                    f'y2="{y}" stroke="{color}" stroke-width="1.5"/>'
                )
                if v != prev_val:
                    parts.append(
                        f'<line x1="{cur_x:.1f}" y1="{y_top}" '
                        f'x2="{cur_x:.1f}" y2="{y_bot}" '
                        f'stroke="{color}" stroke-width="1.5"/>'
                    )
                prev_val = v
                prev_x = cur_x
            # tail
            y = y_top if prev_val == "1" else y_bot
            parts.append(
                f'<line x1="{prev_x:.1f}" y1="{y}" x2="{right}" y2="{y}" '
                f'stroke="{color}" stroke-width="1.5"/>'
            )
        else:  # bus
            box_top = y_top + 6
            box_bot = y_bot - 6
            mid_y = (box_top + box_bot) / 2
            for r in rows:
                v = r[name]
                t = int(r["time_ns"])
                cur_x = x_of(t)
                if cur_x - prev_x < 1:
                    prev_val = v
                    prev_x = cur_x
                    continue
                # value-box polygon
                parts.append(
                    f'<polygon points="{prev_x:.1f},{mid_y} '
                    f'{prev_x+3:.1f},{box_top} {cur_x-3:.1f},{box_top} '
                    f'{cur_x:.1f},{mid_y} {cur_x-3:.1f},{box_bot} '
                    f'{prev_x+3:.1f},{box_bot}" fill="#eef3ff" '
                    f'stroke="#0066cc" stroke-width="0.8"/>'
                )
                if cur_x - prev_x > 28:
                    parts.append(
                        f'<text x="{(prev_x+cur_x)/2:.1f}" y="{mid_y+4:.1f}" '
                        f'font-size="10" text-anchor="middle" fill="#114">'
                        f'{prev_val}</text>'
                    )
                prev_val = v
                prev_x = cur_x
            # tail
            parts.append(
                f'<polygon points="{prev_x:.1f},{mid_y} '
                f'{prev_x+3:.1f},{box_top} {right-3:.1f},{box_top} '
                f'{right:.1f},{mid_y} {right-3:.1f},{box_bot} '
                f'{prev_x+3:.1f},{box_bot}" fill="#eef3ff" '
                f'stroke="#0066cc" stroke-width="0.8"/>'
            )

    # Mark first wFull assert + first rEmpty deassert events
    first_full_t = next(
        (int(r["time_ns"]) for r in rows if r["wFull"] == "1"), None
    )
    first_unfilled_t = next(
        (int(r["time_ns"]) for r in rows if r["rEmpty"] == "0"), None
    )
    events: list[tuple[int, str]] = []
    if first_full_t is not None:
        events.append((first_full_t, "wFull first assert"))
    if first_unfilled_t is not None:
        events.append((first_unfilled_t, "rEmpty first deassert"))
    for et, label in events:
        x = x_of(et)
        parts.append(
            f'<line x1="{x:.1f}" y1="{top_pad-10}" x2="{x:.1f}" '
            f'y2="{height-bot_pad}" stroke="#cc0033" stroke-dasharray="4 4" '
            f'stroke-width="1"/>'
        )
        parts.append(
            f'<text x="{x:.1f}" y="{top_pad-16}" font-size="11" '
            f'text-anchor="middle" fill="#cc0033">{label} @ {et} ns</text>'
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
    rows, t_max = parse_vcd(VCD)
    write_csv(rows)
    render_svg(rows, t_max)
    convert_with_sips(SVG_OUT, PNG_OUT)
    print(f"wrote {CSV_OUT.name} ({len(rows)} change events, t_max={t_max} ns)")
    print(f"wrote {SVG_OUT.name}")
    print(f"wrote {PNG_OUT.name}")


if __name__ == "__main__":
    main()
