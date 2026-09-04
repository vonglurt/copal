#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Paul Richeson -- part of Copal Linux.
#
# cast-trim.py -- cut a window out of an asciicast.
#
# Exists so the page's stills can come from the SAME recording as the main
# GIF rather than from a second boot. Two recordings of one install disagree
# with each other -- different hostname, different timings, different package
# order -- and a page whose images contradict each other reads as mocked up
# even when every frame is real.
#
# TWO CAST FORMATS, AND THE DIFFERENCE IS NOT COSMETIC:
#
#   v2  [absolute_time, "o", "text"]   time since the recording started
#   v3  [interval,      "o", "text"]   time since the PREVIOUS event
#
# asciinema 3.x writes v3. A trimmer that assumes v2 and is handed a v3 cast
# does not fail -- it compares a small delta against a large cutoff, keeps
# every event, and silently produces a copy of the whole recording. That is
# exactly what happened here the first time: the "still" was the entire
# install, and it looked correct because the first frame of an animated GIF
# is what a viewer shows. So the version is read from the header and the
# timeline is reconstructed either way.
#
# Usage:
#   cast-trim.py in.cast out.cast --end 90
#   cast-trim.py in.cast out.cast --marker "Level [s/m" --before 12 --after 4
#
# --marker is the useful one: seek the frame where some text has finished
# printing and keep a window around it. Guessing a timestamp gets you the
# boot messages, because how long a boot takes is not a constant.

import argparse
import json
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")


def load(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()
    if not lines:
        raise SystemExit(f"cast-trim: {path} is empty")
    header = json.loads(lines[0])
    version = int(header.get("version", 2))

    events, clock = [], 0.0
    for line in lines[1:]:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            # A recording interrupted mid-write ends in half a line. Stop:
            # everything before it is still a valid cast.
            break
        if not isinstance(event, list) or len(event) < 3:
            continue
        # v3 stores the gap since the previous event; v2 stores the absolute
        # time. Normalise to absolute so the rest of this reasons in one unit.
        clock = clock + float(event[0]) if version >= 3 else float(event[0])
        events.append((clock, event[1], event[2]))
    return lines[0], version, events


def find_marker(events, marker):
    """Absolute time at which `marker` has finished printing."""
    acc = ""
    for when, _kind, data in events:
        acc += data
        if marker in ANSI.sub("", acc):
            return when
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description="Cut a window out of an asciicast.")
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--start", type=float, default=0.0)
    ap.add_argument("--end", type=float, default=None)
    ap.add_argument("--marker", default=None,
                    help="seek the moment this text finishes printing")
    ap.add_argument("--before", type=float, default=12.0,
                    help="seconds of run-up to keep before the marker")
    ap.add_argument("--after", type=float, default=4.0,
                    help="seconds to keep after the marker")
    args = ap.parse_args()

    header, version, events = load(args.src)
    if not events:
        print(f"cast-trim: no events in {args.src}", file=sys.stderr)
        return 1

    start, end = args.start, args.end
    if args.marker:
        hit = find_marker(events, args.marker)
        if hit is None:
            print(f"cast-trim: {args.marker!r} never appears in {args.src}",
                  file=sys.stderr)
            return 1
        start, end = max(0.0, hit - args.before), hit + args.after
        print(f"cast-trim: {args.marker!r} at {hit:.1f}s -> window "
              f"{start:.1f}..{end:.1f}s", file=sys.stderr)
    if end is None:
        end = events[-1][0]

    # Everything before the window is REPLAYED WITH ZERO DELAY rather than
    # dropped. A terminal recording is stateful: cut the first N seconds away
    # and the window opens onto a screen whose scrollback, cursor position and
    # colours were all established by output that is no longer there. Feeding
    # it back instantly costs one frame and makes the still correct.
    preamble = "".join(d for w, _k, d in events if w < start)
    kept = [(w, k, d) for w, _k2, d in events for k in (_k2,) if start <= w <= end]
    if not kept:
        print(f"cast-trim: nothing between {start:.1f}s and {end:.1f}s",
              file=sys.stderr)
        return 1

    out = [header]
    # Written as v2 (absolute times) whatever went in: it is the format agg
    # has always understood, and the header is rewritten to match so the file
    # cannot claim v3 while carrying v2 timings.
    hdr = json.loads(header)
    hdr["version"] = 2
    if "term" in hdr and isinstance(hdr["term"], dict):
        # v2 carries geometry at the top level; agg reads it there. Wrong
        # geometry renders as reflowed garbage rather than a screenshot.
        hdr.setdefault("width", hdr["term"].get("cols", 80))
        hdr.setdefault("height", hdr["term"].get("rows", 24))
    out[0] = json.dumps(hdr) + "\n"

    if preamble:
        out.append(json.dumps([0.0, "o", preamble]) + "\n")
    base = kept[0][0]
    for when, kind, data in kept:
        out.append(json.dumps([round(when - base, 6), kind, data]) + "\n")

    with open(args.dst, "w", encoding="utf-8") as fh:
        fh.writelines(out)

    print(f"cast-trim: {len(kept)} events -> {args.dst}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
