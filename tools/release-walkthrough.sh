#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Paul Richeson -- part of Copal Linux.
#
# release-walkthrough.sh -- run a release, and stop at the parts a person has
# to do.
#
# WHY THIS EXISTS. `make release` is automatic right up to the one thing a
# script cannot do: photograph a desktop. `make screens` can take the picture
# through QEMU's monitor, but only once an install has FINISHED -- which is
# hours, not the minutes a bounded capture runs -- and the framing (which
# workspace, which windows open, menu up or not) is a judgement nobody has
# automated.
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

cat <<BANNER

${B}Copal -- guided release${N}

  This runs ${B}make release${N} end to end and photographs the result.

  ${B}One${N} thing asks you anything: whether to purge, because that is the only
  step that destroys something. Everything else -- building, verifying,
  recording the install, rendering, and taking the screenshots through QEMU's
  monitor -- happens without you.

  The screenshots are real frames of whatever the image actually contains. If
  the install never reached a desktop, they show a console, honestly.

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
        # NOT piped. Indenting through sed buffers the output, so a step that
        # takes a minute shows nothing at all and reads as a hang -- which is
        # the opposite of what a walkthrough is for. Alignment is not worth
        # hiding progress for.
        make purge YES=1
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
# STRAIGHT TO THE TERMINAL, deliberately. This used to run through
# `grep -v | sed` to drop agg's progress bars and indent the rest -- and both
# of those buffer, so the build showed nothing for ninety seconds and the
# recording showed nothing for the length of the capture. A walkthrough whose
# whole job is to say what is happening cannot be the thing that hides it.
#
# Not piping also means $? is make's own status, so the PIPESTATUS dance that
# used to be needed here is gone with it.
make release PURGE=0 LEVEL="$LEVEL" MINUTES="$MINUTES"
_rc=$?
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
step "The desktops — taken automatically, where that is possible"
say "A compositor draws to a framebuffer, not to a serial console, so the"
say "recording above cannot contain a desktop. QEMU's own monitor can"
say "photograph one though -- ${D}screendump${N} writes the guest's framebuffer"
say "exactly as the guest is drawing it, headless, needing no permission"
say "from macOS and nothing on your screen."
blank
say "So this step does not ask you to take a picture. It takes them."

# WHAT THIS CANNOT DO, and why it is worth saying rather than silently
# skipping: photographing the UTM window would need macOS Screen Recording
# permission, which this process does not have and cannot ask for usefully
# (the request is denied without a dialog and the denial is remembered).
# QEMU's monitor sidesteps the whole question -- it is the hypervisor writing
# a file, not an application reading somebody's screen.
if screencapture -x -R 0,0,8,8 /tmp/copal-cap-probe.$$.png 2>/dev/null \
   && [ -s /tmp/copal-cap-probe.$$.png ]; then
    say "${D}(this terminal also has Screen Recording, so a UTM window could be${N}"
    say "${D} captured with screencapture if you would rather frame it by hand)${N}"
fi
rm -f /tmp/copal-cap-probe.$$.png

# Only worth attempting on an image with a desktop on it. The level recorded
# on the boot partition is the best signal available from here -- the root is
# ext4 and macOS cannot read it, so the FAT partition is all there is to ask.
_lvl=""
_att=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage "build/copal-$(sed -n 's/^MODEL *?= *//p' Makefile | head -1).img" 2>/dev/null) || true
_mnt=$(printf '%s\n' "$_att" | awk -F'\t' '/COPALBOOT/{print $NF}' | head -1)
if [ -n "${_mnt:-}" ]; then
    [ -f "$_mnt/copal-profile" ] && _lvl=$(cat "$_mnt/copal-profile" 2>/dev/null)
    _dev=$(printf '%s\n' "$_att" | awk '/^\/dev\/disk[0-9]+ /{print $1; exit}')
    hdiutil detach "$_dev" >/dev/null 2>&1 || true
fi
[ -n "$_lvl" ] && say "install level recorded on the card: ${B}$_lvl${N}"

blank
say "Booting the image and photographing what comes up..."
if tools/capture-screens.sh --shots 4 --wait 150 --interval 25 --prefix screen; then
    _n=$(ls docs/media/screen-*.png 2>/dev/null | wc -l | tr -d ' ')
    done_ "$_n frame(s) captured -- docs/media/screen-*.png"
    blank
    say "${B}These are real frames, whatever they show.${N} If the install that"
    say "produced this image never reached a desktop -- and a bounded capture"
    say "does not -- they will be a console, honestly."
    blank
    say "To promote one to the page's hero slot once a desktop IS in it:"
    say "  ${D}cp docs/media/screen-3.png docs/media/antiquity-desktop.png${N}"
    say "  ${D}cp docs/media/screen-3.png docs/media/i3-desktop.png${N}"
    say "  ${D}make gallery${N}"
else
    printf '%s└─%s %sno frames -- the guest drew nothing in time%s\n' "$C" "$N" "$Y" "$N"
    say "Raise the wait (${D}make screens SHOTWAIT=300${N}) or check"
    say "${D}build/copal-screens-serial.log${N} to see how far it booted."
fi

step "A finished desktop, when you want one"
say "The frames above come from whatever state the image is in. A ${B}complete${N}"
say "install -- the one that reaches stage 16 and a compositor -- takes hours"
say "and is a separate job from this release:"
blank
say "  ${D}make utm${N}         start it in UTM"
say "  ${D}${N}                 log in as root in the window, then run"
say "  ${D}   sh /media/vda1/copal-init.sh${N}   and pick level f"
say "  ${D}utm/utm-vm.sh progress --target aarch64${N}   how far it has got"
blank
say "When it has finished, ${B}make screens${N} photographs the real desktop"
say "with no window, no camera and no permission of any kind."

# ------------------------------------------------------------- 4. the gallery
step "Gallery and pages"
say "Regenerating docs/gallery.html from whatever is actually in docs/media."
python3 tools/build-gallery.py
done_ "gallery rebuilt"

printf '\n%s%s  Release walkthrough complete.%s\n\n' "$B" "$G" "$N"
printf '  In docs/media:\n'
ls -1 docs/media 2>/dev/null | grep -vE '\.md$' | sed 's/^/    /' || true
printf '\n  %sReview, then commit:%s  git add docs && git commit\n\n' "$D" "$N"
