#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 paulr@sdf.org -- part of Copal Linux.
#
# verify-build.sh -- is this image the one this checkout would build, and is
# this checkout the newest there is?
#
# WHY. An image and a source tree drift apart silently. Nothing fails when
# they do: the image still boots, the script still runs, and the only symptom
# is a bug you already fixed reappearing in a demonstration, or a release
# built from a tree with uncommitted edits nobody can reconstruct. Every
# question below is one somebody eventually asks in a form like "which
# version is that, exactly", and the answer has to come from a file rather
# than from memory.
#
# Six checks, in the order they matter. Each prints its own verdict and the
# script exits non-zero if any FAILED -- a warning is a thing to know, a
# failure is a thing to fix before publishing or tagging.
#
#   1  the image exists and carries a build stamp
#   2  the stamp names a source revision
#   3  that revision is this working tree's HEAD
#   4  the tree was clean when it was built, and is clean now
#   5  HEAD is not behind its remote  (the "most recent checkout" question)
#   6  the payload's Alpine version is the one this script pins today
#
# Usage:
#   tools/verify-build.sh                      # build/copal-vm.img
#   tools/verify-build.sh --image path.img
#   tools/verify-build.sh --boot               # also boot it and check it comes up
#   tools/verify-build.sh --quiet              # verdict only, for scripts
set -uo pipefail

cd "$(dirname "$0")/.."

IMAGE="build/copal-vm.img"
DO_BOOT=0
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE="$2"; shift 2 ;;
        --boot)  DO_BOOT=1; shift ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "verify-build.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

FAILED=0
WARNED=0

# Colour only when someone is watching. A verdict piped into a log should be
# greppable, not full of escape sequences.
if [ -t 1 ] && [ "$QUIET" = 0 ]; then
    G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[2m'; N=$'\033[0m'
else
    G=""; R=""; Y=""; D=""; N=""
fi

ok()   { [ "$QUIET" = 1 ] || printf '  %s[ ok ]%s   %s\n' "$G" "$N" "$*"; }
bad()  { printf '  %s[fail]%s   %s\n' "$R" "$N" "$*" >&2; FAILED=$((FAILED + 1)); }
warn() { printf '  %s[warn]%s   %s\n' "$Y" "$N" "$*" >&2; WARNED=$((WARNED + 1)); }
note() { [ "$QUIET" = 1 ] || printf '           %s%s%s\n' "$D" "$*" "$N"; }

[ "$QUIET" = 1 ] || printf '\nCopal -- verifying %s\n\n' "$IMAGE"

# --- 1. the image, and its stamp ----------------------------------------
#
# Read WITHOUT mounting. The stamp lives on the FAT boot partition, and
# attaching an image to look at one file means a mount that can be left
# behind, a /Volumes name that can clash with a card already in a reader
# (see the note on assert_mount_is in copal-prep.sh), and a write-capable
# handle on something being verified. `strings` over the first megabytes
# finds the same lines and cannot alter anything.
if [ ! -f "$IMAGE" ]; then
    bad "no image at $IMAGE"
    note "build one:  make image"
    printf '\n'
    exit 1
fi
ok "image present ($(du -h "$IMAGE" | cut -f1) on disk)"

stamp_field() {  # <field name>
    # The stamp is a handful of KEY="value" lines; -a because a disk image is
    # binary and grep would otherwise refuse to look.
    grep -a -m1 "^COPAL_$1=" "$IMAGE" 2>/dev/null \
        | sed "s/^COPAL_$1=[\"']\{0,1\}//; s/[\"']\{0,1\}[[:space:]]*$//"
}

BID=$(stamp_field BUILD_ID)
BDATE=$(stamp_field BUILD_DATE)
BTARGET=$(stamp_field BUILD_TARGET)
BALPINE=$(stamp_field ALPINE_VER)
GREV=$(stamp_field GIT_REV)
GDESC=$(stamp_field GIT_DESCRIBE)
GDIRTY=$(stamp_field GIT_DIRTY)

if [ -z "$BID" ]; then
    bad "no build stamp in the image -- it predates copal-build, or is truncated"
else
    ok "build $BID -- $BDATE"
    note "target $BTARGET, Alpine $BALPINE"
fi

# --- 2 & 3. which source built it ---------------------------------------
HEAD_REV=$(git rev-parse HEAD 2>/dev/null || echo "")
if [ -z "$GREV" ] || [ "$GREV" = "(not a git checkout)" ]; then
    warn "the image records no source revision"
    note "built from a tarball, or by a copal-prep.sh older than the git stamp"
elif [ -z "$HEAD_REV" ]; then
    warn "this is not a git checkout -- cannot compare"
    note "image was built from ${GDESC:-$GREV}"
elif [ "$GREV" = "$HEAD_REV" ]; then
    ok "built from this exact checkout (${GDESC:-${GREV:0:12}})"
else
    bad "image and checkout disagree"
    note "image  ${GDESC:-} ${GREV:0:12}"
    note "HEAD   $(git describe --tags --always --dirty 2>/dev/null) ${HEAD_REV:0:12}"
    # Which direction, because "the image is old" and "the image is from a
    # branch you have since left" want different responses.
    if git merge-base --is-ancestor "$GREV" HEAD 2>/dev/null; then
        note "the image is BEHIND HEAD by $(git rev-list --count "$GREV..HEAD" 2>/dev/null) commit(s) -- rebuild it"
    else
        note "the image is not an ancestor of HEAD -- built from another branch"
    fi
fi

# --- 4. clean at build time, and clean now ------------------------------
if [ "$GDIRTY" = yes ]; then
    bad "built from a tree with uncommitted changes"
    note "the recorded revision does not describe what was actually built"
elif [ "$GDIRTY" = no ]; then
    ok "built from a clean tree"
fi

if [ -n "$HEAD_REV" ]; then
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        warn "the working tree has uncommitted changes now"
        git status --short 2>/dev/null | head -5 | sed 's/^/           /' >&2
    else
        ok "working tree is clean"
    fi
fi

# --- 5. is this the most recent checkout? -------------------------------
#
# Asked WITHOUT fetching. A verification script that mutates the repository
# it is verifying -- and that fails on an aeroplane -- is the wrong shape;
# it reports what the last fetch knew and says so.
if [ -n "$HEAD_REV" ]; then
    UP=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo "")
    if [ -z "$UP" ]; then
        warn "this branch tracks no remote -- cannot say whether it is current"
    else
        BEHIND=$(git rev-list --count "HEAD..$UP" 2>/dev/null || echo 0)
        AHEAD=$(git rev-list --count "$UP..HEAD" 2>/dev/null || echo 0)
        if [ "$BEHIND" = 0 ] && [ "$AHEAD" = 0 ]; then
            ok "up to date with $UP"
        elif [ "$BEHIND" != 0 ]; then
            warn "$BEHIND commit(s) behind $UP -- 'git pull' first"
        else
            ok "$AHEAD commit(s) ahead of $UP (unpushed)"
        fi
        note "as of the last fetch; this does not touch the network"
    fi
fi

# --- 6. the Alpine the script pins today --------------------------------
WANT_ALPINE=$(sed -n 's/^ALPINE_VER="\${ALPINE_VER:-\([^}]*\)}"/\1/p' copal-prep.sh | head -1)
if [ -n "$WANT_ALPINE" ] && [ -n "$BALPINE" ]; then
    if [ "$WANT_ALPINE" = "$BALPINE" ]; then
        ok "Alpine $BALPINE matches what copal-prep.sh pins"
    else
        bad "image has Alpine $BALPINE; copal-prep.sh now pins $WANT_ALPINE"
    fi
fi

# --- optional: does it actually come up? --------------------------------
#
# The only check here that runs the thing rather than reading about it, and
# the slow one -- so it is opt-in. --check boots headless and greps the
# serial log for a login prompt, which is the difference between "an image
# exists" and "a system was built".
if [ "$DO_BOOT" = 1 ]; then
    [ "$QUIET" = 1 ] || printf '\n  booting it headless (about a minute)...\n'
    if ./copal-vm.sh --check --log build/copal-verify.log "$IMAGE" >/dev/null 2>&1; then
        ok "boots to a login prompt"
    else
        bad "did not reach a login prompt -- see build/copal-verify.log"
    fi
fi

# --- the verdict ---------------------------------------------------------
printf '\n'
if [ "$FAILED" -gt 0 ]; then
    printf '  %sFAILED%s -- %d problem(s), %d warning(s)\n\n' "$R" "$N" "$FAILED" "$WARNED"
    exit 1
fi
if [ "$WARNED" -gt 0 ]; then
    printf '  %sOK, with %d warning(s)%s\n\n' "$Y" "$WARNED" "$N"
    exit 0
fi
printf '  %sVERIFIED%s -- image, source and checkout all agree\n\n' "$G" "$N"
exit 0
