#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Paul Richeson -- part of Copal Linux.
#
# capture-media.sh -- regenerate the images docs/index.html reserves slots for,
# from a real install rather than from a mock-up.
#
# WHY A SCRIPT AND NOT A SCREEN RECORDING. The install has no GUI: it is a
# text transcript on a serial console, and copal-vm.sh puts that console on
# this terminal. The thing worth capturing is therefore already characters in
# a tty -- and a video of a terminal is the worst container for it: large,
# unsearchable, and blurry at any size that fits a web page. asciinema records
# the characters and their timing; agg renders that to a GIF at whatever speed
# suits. Nobody has to sit and watch, and nobody has to press record.
#
# The one thing this CANNOT capture is the desktop itself. A compositor draws
# to a framebuffer, not to a tty, so the two desktop screenshots stay a manual
# job -- see the note it prints at the end, and docs/media/README.md.
#
# Usage:
#   tools/capture-media.sh                 # full monty, the default
#   tools/capture-media.sh --level m       # medium, if the full one is broken
#   tools/capture-media.sh --minutes 20    # record for longer
#   tools/capture-media.sh --keep          # do not delete the .cast files
#
# Output lands in docs/media/, which is where the page looks for it.
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE="build/copal-vm.img"
LEVEL="f"
MINUTES=12
KEEP=0
SPEED=8
VIDEO=0

while [ $# -gt 0 ]; do
    case "$1" in
        --level)   LEVEL="$2"; shift 2 ;;
        --minutes) MINUTES="$2"; shift 2 ;;
        --image)   IMAGE="$2"; shift 2 ;;
        --speed)   SPEED="$2"; shift 2 ;;
        --keep)    KEEP=1; shift ;;
        --video)   VIDEO=1; shift ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "capture-media.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

info() { printf '\033[36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- what this needs, named before it fails ------------------------------
MISSING=""
for t in asciinema agg expect qemu-system-aarch64; do
    command -v "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"
done
if [ -n "$MISSING" ]; then
    warn "not installed:$MISSING"
    printf '    %s\n' "brew install asciinema agg qemu    # expect ships with macOS" >&2
    exit 1
fi
[ -f "$IMAGE" ] || die "no image at $IMAGE -- run 'make image' first"

OUT=docs/media
mkdir -p "$OUT"

# --- the recording -------------------------------------------------------
#
# ONE INSTALL, RECORDED ONCE, then cut into the pieces the page wants. An
# earlier design booted the machine once per image, which took four times as
# long and -- worse -- produced four transcripts that disagreed with each
# other, because each was a different install with a different hostname and
# different timings. One cast is one truth.
CAST="$OUT/install.cast"
info "Recording a $LEVEL-level install for $MINUTES minutes"
info "  the VM's serial console is the transcript; nothing is being screen-grabbed"

# --overwrite so a re-run replaces rather than refusing; --cols/--rows pin the
# geometry, because the GIF's aspect ratio is the terminal's and the page's
# frame is 16:9.
asciinema rec \
    --overwrite \
    --cols 120 --rows 34 \
    --command "tools/capture-install.exp $IMAGE $LEVEL $MINUTES" \
    "$CAST" || warn "the recorder exited non-zero -- rendering what it captured"

[ -s "$CAST" ] || die "nothing was recorded"
info "Captured: $CAST ($(wc -c < "$CAST" | tr -d ' ') bytes)"

# --- the check that keeps a real name off a public page ------------------
#
# The installer offers THIS Mac's git identity as the default the target
# suggests, and prints it while doing so. Captured and published, that is a
# real name and a real email address in a GIF on a web page -- the same leak
# .gitignore exists to prevent, by a route .gitignore cannot see.
#
# `make release` builds with a neutral identity so it never reaches the image.
# This is the backstop for every other way of running this script: it reads
# what git would have offered and refuses if that string is in the recording.
for _f in name email; do
    _v=$(git config --global --get "user.$_f" 2>/dev/null || true)
    [ -n "$_v" ] || continue
    if grep -qF "$_v" "$CAST"; then
        warn "the recording contains this Mac's git $_f: $_v"
        printf '    %s\n' \
          "That would be published. Build the image with a neutral identity:" \
          "" \
          "    make release            # does this for you" \
          "    CFG_GIT_NAME=Copal CFG_GIT_EMAIL=copal@example.invalid make auto" \
          "" \
          "Then re-run. Nothing has been rendered." >&2
        rm -f "$CAST"
        exit 1
    fi
done

# --- rendering -----------------------------------------------------------
#
# agg wants EIGHTEEN hex triplets: background, foreground, then all sixteen
# ANSI slots. Ten (bg, fg, and the first eight) is the other accepted form --
# a seventeen-value string is rejected outright, which is how the first run of
# this script failed. Values are the helios ones the page is built from
# (docs/THEME.md VI-D), so the GIF sits on the page rather than on top of it.
THEME="181818,d0daed"                    # background, foreground
THEME="$THEME,121212,ff723e,a0675d,fccf8a,666c93,87704f,92bbcc,d0daed"   # 0-7
THEME="$THEME,5e5e5e,ff723e,a0675d,fccf8a,666c93,87704f,92bbcc,fce2ab"   # 8-15

info "Rendering the GIF at ${SPEED}x"
agg --speed "$SPEED" \
    --font-family "JetBrains Mono,Menlo,monospace" \
    --theme "$THEME" \
    "$CAST" "$OUT/install-cast.gif" \
  || die "agg failed to render $CAST"

# The page's <img> names an .svg; a GIF is what agg produces, so point the
# page at what actually exists rather than leaving a dead slot.
if grep -q 'media/install-cast.svg' docs/index.html; then
    sed -i '' 's|media/install-cast\.svg|media/install-cast.gif|' docs/index.html
    info "docs/index.html now points at install-cast.gif"
fi

info "Rendered: $OUT/install-cast.gif ($(du -h "$OUT/install-cast.gif" | cut -f1))"

# --- the video, when asked for -------------------------------------------
#
# A GIF is the right thing for a web page: it plays inline, needs no player
# and no controls, and 364 kB is nothing. A video is the right thing for
# everywhere else -- a release page, a talk, anything that wants scrubbing,
# pausing, or a length a GIF would be absurd at.
#
# Rendered FROM THE GIF rather than from a second agg pass, because agg only
# emits GIF and re-rendering would be a second interpretation of the same
# cast. Going through the GIF means the video is provably the same frames.
# The colour survives: this is a palette-limited source, so the encode uses
# yuv420p for players that insist on it and keeps the palette otherwise.
if [ "$VIDEO" = 1 ]; then
    if ! command -v ffmpeg >/dev/null 2>&1; then
        warn "ffmpeg is not installed -- no video (brew install ffmpeg)"
    else
        info "Encoding the video"
        # -vf pad: H.264 needs even dimensions and a terminal render is
        # whatever the font produced. Padding rather than scaling keeps the
        # text pixel-exact instead of resampling it into mush.
        ffmpeg -y -loglevel error \
            -i "$OUT/install-cast.gif" \
            -movflags +faststart -pix_fmt yuv420p \
            -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" \
            -c:v libx264 -crf 20 -preset slow \
            "$OUT/install.mp4" \
          && info "Rendered: $OUT/install.mp4 ($(du -h "$OUT/install.mp4" | cut -f1))" \
          || warn "ffmpeg could not encode the video"

        # webm alongside, because it is smaller and every browser that
        # matters plays one of the two. A build of ffmpeg without libvpx
        # writes a zero-byte file and exits 0, so success is judged on the
        # file having contents rather than on the exit status -- and an empty
        # one is removed rather than left to be published as a dead <source>.
        ffmpeg -y -loglevel error \
            -i "$OUT/install-cast.gif" \
            -c:v libvpx-vp9 -crf 34 -b:v 0 \
            "$OUT/install.webm" >/dev/null 2>&1 || true
        if [ -s "$OUT/install.webm" ]; then
            info "Rendered: $OUT/install.webm ($(du -h "$OUT/install.webm" | cut -f1))"
        else
            rm -f "$OUT/install.webm"
            warn "no webm -- this ffmpeg cannot encode VP9. The mp4 is fine."
        fi
    fi
fi

# --- the still, cut from the same recording ------------------------------
#
# The guided-levels screenshot is a moment inside the transcript above, so it
# is cut from the same cast rather than from a second boot.
#
# SOUGHT BY ITS TEXT, not by a timestamp. How long a boot takes is not a
# constant -- it moves with the host, the image and whether the modloop has
# to be expanded -- so "the first ninety seconds" reliably produced a still
# of UEFI firmware messages. --marker seeks the frame where the level prompt
# has finished printing and keeps a window around it.
if command -v python3 >/dev/null 2>&1; then
    python3 tools/cast-trim.py "$CAST" "$OUT/guided.cast" \
            --marker "Level [s/m" --before 26 --after 3 \
        && agg --speed 3 --last-frame-duration 6 \
               --font-family "JetBrains Mono,Menlo,monospace" \
               --theme "$THEME" "$OUT/guided.cast" "$OUT/guided-levels.gif" \
        && sed -i '' 's|media/guided-levels\.png|media/guided-levels.gif|' docs/index.html \
        && info "Rendered: $OUT/guided-levels.gif (the level chooser)" \
        || warn "could not cut the guided-levels still -- the main cast is fine"
fi

[ "$KEEP" = 1 ] || rm -f "$OUT"/*.cast

cat >&2 <<'DONE'

  Captured from a real install. Two slots on the page are still empty, and
  they cannot be filled this way:

      docs/media/antiquity-desktop.png    Hyprland with the theme
      docs/media/i3-desktop.png           i3 on the framebuffer

  A compositor draws to a framebuffer, not to a tty, so there is nothing for
  asciinema to record. Take them from inside the running desktop, where the
  tools are already installed and the result is a real screenshot rather than
  a photograph of a screen:

      Super+Shift+S              copal-shot -- writes to ~/Pictures
      grim ~/Pictures/shot.png   the whole screen, on Wayland

  Then copy them out over the shared folder or scp, and drop them in
  docs/media/ under those names. The page picks them up with no edit.

DONE
