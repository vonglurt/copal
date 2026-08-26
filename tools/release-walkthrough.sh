#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 paulr@sdf.org -- part of Copal Linux.
#
# release-walkthrough.sh -- run a release, and stop at the parts a person has
# to do.
#
# WHY THIS EXISTS. `make release` is automatic right up to the two things a
# script cannot do on this Mac:
#
#   1. Approve an Accessibility grant. macOS records that against whoever is
#      asking, and a terminal is a poor asker -- so the AppleScript is handed
#      to Script Editor for a human to read and run with Cmd+R.
#   2. Photograph a desktop. `make screens` can do it through QEMU's monitor,
#      but only once an install has FINISHED -- which is hours -- and the
#      framing (which workspace, which windows open, menu up or not) is a
#      judgement nobody has automated.
#
# Left implicit, those two turn a "just run make release" into a job that
# quietly produces a page with two empty slots and no explanation. This walks
# through the whole thing instead: it runs the automatic parts, and where a
# person is needed it says exactly what to do, waits, and checks that it was
# done before carrying on.
#
# Every pause is skippable. Nothing here is destructive on its own -- the one
# destructive step (purge) is announced and confirmed before it runs.
#
# Usage:
#   tools/release-walkthrough.sh                # the full guided release
#   tools/release-walkthrough.sh --no-purge     # keep the payload cache
#   tools/release-walkthrough.sh --shots-only   # skip to the screenshot steps
set -uo pipefail

cd "$(dirname "$0")/.."

PURGE=1
SHOTS_ONLY=0
MINUTES="${MINUTES:-12}"
LEVEL="${LEVEL:-f}"

while [ $# -gt 0 ]; do
    case "$1" in
        --no-purge)  PURGE=0; shift ;;
        --shots-only) SHOTS_ONLY=1; shift ;;
        --minutes)   MINUTES="$2"; shift 2 ;;
        --level)     LEVEL="$2"; shift 2 ;;
        -h|--help)   sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "release-walkthrough.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

if [ -t 1 ]; then
    B=$'\033[1m'; G=$'\033[32m'; C=$'\033[36m'; Y=$'\033[33m'; D=$'\033[2m'; N=$'\033[0m'
else
    B=""; G=""; C=""; Y=""; D=""; N=""
fi

STEP=0
step() {
    STEP=$((STEP + 1))
    printf '\n%s┌─ STEP %d ─ %s%s\n' "$C" "$STEP" "$1" "$N"
}
say()   { printf '%s│%s  %s\n' "$C" "$N" "$*"; }
blank() { printf '%s│%s\n' "$C" "$N"; }
done_() { printf '%s└─%s %s%s%s\n' "$C" "$N" "$G" "$*" "$N"; }

# A pause that a person answers. Returns 1 if they skipped, so the caller can
# say so rather than pretending the step happened.
pause_for() {  # <what they should have done>
    blank
    printf '%s│%s  %sPress Enter when done, or s to skip: %s' "$C" "$N" "$B" "$N"
    read -r _r </dev/tty || _r=s
    case "$_r" in
        s|S|skip) printf '%s│%s  %sskipped%s\n' "$C" "$N" "$Y" "$N"; return 1 ;;
    esac
    return 0
}

# Did a file appear? The only honest way to know a screenshot step happened.
expect_file() {  # <path> <what it is>
    if [ -s "$1" ]; then
        done_ "$2 -> $1 ($(du -h "$1" | cut -f1))"
        return 0
    fi
    printf '%s└─%s %snot found: %s%s\n' "$C" "$N" "$Y" "$1" "$N"
    printf '   %sthe page will show an empty slot for it, which is honest but ugly%s\n' "$D" "$N"
    return 1
}

cat <<BANNER

${B}Copal -- guided release${N}

  This runs ${B}make release${N} and stops at the parts a script cannot do here.
  There are ${B}three${N} of those, and none takes long:

    ${B}A${N}  approve an Accessibility prompt (once, ever)
    ${B}B${N}  photograph the Hyprland desktop
    ${B}C${N}  photograph the i3 desktop

  Everything else runs by itself. Steps can be skipped with 's'; a skipped
  screenshot leaves that slot empty on the page rather than faking it.

BANNER

if [ "$SHOTS_ONLY" = 0 ]; then

# ---------------------------------------------------------------- 1. purge
if [ "$PURGE" = 1 ]; then
    step "Purge — build/, the payload cache, and both UTM machines"
    say "This is the only destructive step, and it is the reason a release"
    say "is reproducible: everything after it is built from nothing."
    blank
    say "${Y}It deletes:${N}"
    say "  build/            every image, transcript and harvested log"
    say "  build/cache/      the verified Alpine payloads (they re-download)"
    say "  UTM machines      Copal-aarch64 and Copal-x86_64, and their disks"
    say "${D}Any other UTM machine is left alone.${N}"
    if pause_for "ready to purge"; then
        make purge YES=1 2>&1 | sed 's/^/   /'
        done_ "purged"
    else
        say "Keeping what is there. The build below may reuse it."
    fi
fi

# ------------------------------------------------------------- 2. the build
step "Build — a clean image, unattended"
say "${D}make auto: ./copal build $(sed -n 's/^MODEL *?= *//p' Makefile | head -1) --auto${N}"
say "No questions. script(1) supplies the tty the step gates want."
say "About 90 seconds once the payload is cached; longer if it re-downloads."
# The status is taken from make, not from the tail of the pipe. Without
# PIPESTATUS the exit code here would be sed's, which is always 0 -- and the
# walkthrough would announce success over a release that failed at verify.
set -o pipefail
make release PURGE=0 LEVEL="$LEVEL" MINUTES="$MINUTES" 2>&1 \
    | grep -vE '^\s*[0-9]+ / [0-9]+' | sed 's/^/   /'
_rc=${PIPESTATUS[0]}
set +o pipefail
if [ "$_rc" != 0 ]; then
    printf '%s└─%s %sthe release failed (exit %s)%s\n' "$C" "$N" "$Y" "$_rc" "$N"
    say ""
    say "The usual cause is ${B}verify${N}: a release will not be built from a"
    say "tree with uncommitted changes, because the revision stamped into the"
    say "image would not describe what was actually built. Commit, then re-run."
    say ""
    say "Carrying on to the screenshot steps anyway -- they work on whatever"
    say "image is there, and skipping them would lose the pictures too."
else
    done_ "image built, install recorded, GIF and video rendered"
fi

fi  # SHOTS_ONLY

# ------------------------------------------------- 3. the desktop screenshots
#
# The two images the serial capture cannot produce. A compositor draws to a
# framebuffer; asciinema records a tty; the two never meet.
step "The desktops — the two pictures a recording cannot take"
say "The install you just recorded was ${B}bounded${N} -- it stopped after"
say "$MINUTES minutes, long before a desktop existed. To photograph one you"
say "need an install that actually finished, which is hours, not minutes."
blank
say "${B}Two ways, and the second is the one to use:${N}"
blank
say "  ${B}1. Let it finish in UTM${N}, then photograph it:"
say "     ${D}make utm${N}                             register and start"
say "     ${D}make utm-type TEXT=root${N}              log in    ${Y}(needs step A)${N}"
say "     ${D}make utm-type TEXT='sh /media/vda1/copal-init.sh'${N}"
say "     ${D}make utm-type TEXT=$LEVEL${N}                    pick the level"
say "     ${D}... hours ...${N}"
say "     then screenshot the UTM window with ${B}Cmd+Shift+4${N}, space, click"
blank
say "  ${B}2. Or let QEMU take it${N}, once an install has finished:"
say "     ${D}make screens${N}                         QEMU screendump, headless"
say "     ${D}${N}                                    real pixels, no window, no camera"
blank
say "${Y}Step A -- the Accessibility grant -- happens the first time you run${N}"
say "${Y}make utm-type. macOS denies this terminal, the script opens in Script${N}"
say "${Y}Editor, you read it and press Cmd+R. Once, ever.${N}"

step "B — the Hyprland desktop"
say "Wanted: ${B}docs/media/antiquity-desktop.png${N}"
blank
say "Frame it with something on screen worth looking at:"
say "  ${D}Super+Return${N}   a kitty terminal or two, tiled"
say "  ${D}Super+D${N}        the launcher open, if quickshell is installed"
say "  ${D}${N}               otherwise the wallpaper and a terminal is plenty"
blank
say "From inside the guest:    ${D}grim ~/Pictures/shot.png${N}"
say "From the Mac, on the VM:  ${D}Cmd+Shift+4${N}, space, click the window"
say "Then save or copy it to:  ${B}docs/media/antiquity-desktop.png${N}"
pause_for "saved the Hyprland screenshot" \
    && expect_file docs/media/antiquity-desktop.png "Hyprland desktop"

step "C — the i3 desktop"
say "Wanted: ${B}docs/media/i3-desktop.png${N}"
blank
say "This is the medium level -- X on the framebuffer. If the same machine"
say "has both, switch to it without reinstalling anything:"
say "  ${D}doas copal-desktop x11${N}     then log out and back in"
blank
say "The key bindings are painted onto the root window at first login, which"
say "is the frame worth catching -- it is what the desktop looks like to"
say "somebody seeing it for the first time."
pause_for "saved the i3 screenshot" \
    && expect_file docs/media/i3-desktop.png "i3 desktop"

# ------------------------------------------------------------- 4. the gallery
step "Gallery and pages"
say "Regenerating docs/gallery.html from whatever is actually in docs/media."
python3 tools/build-gallery.py 2>&1 | sed 's/^/   /'
done_ "gallery rebuilt"

printf '\n%s%s  Release walkthrough complete.%s\n\n' "$B" "$G" "$N"
printf '  In docs/media:\n'
ls -1 docs/media 2>/dev/null | grep -vE '\.md$' | sed 's/^/    /' || true
printf '\n  %sReview, then commit:%s  git add docs && git commit\n\n' "$D" "$N"
