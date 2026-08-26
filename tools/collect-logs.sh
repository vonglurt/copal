#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 paulr@sdf.org -- part of Copal Linux.
#
# collect-logs.sh -- gather every log a run produced into one directory.
#
# WHY. The evidence for "did that work" is scattered across three places that
# have nothing to do with each other:
#
#   the Mac        build/copal-prep-auto-*.log   what the BUILD did
#   the image      COPALBOOT/firstrun.log        what the INSTALL did
#   the guest      /var/log/copal/               what the SYSTEM did afterwards
#
# The middle one is the interesting one and the awkward one: it is written by
# copal-init.sh onto the FAT boot partition, which means it survives a guest
# that will not boot and can be read from here with the machine switched off.
# That is exactly the situation you want a log in.
#
# Reading it means attaching the image, so this does that carefully: it
# attaches, copies, and detaches in a trap, and refuses to leave a mount
# behind. See the note on assert_mount_is in copal-prep.sh for why a stray
# /Volumes/COPALBOOT is worse than it sounds.
#
# Usage:
#   tools/collect-logs.sh                     # into build/logs/<timestamp>
#   tools/collect-logs.sh --image other.img
#   tools/collect-logs.sh --out /tmp/logs
set -uo pipefail

cd "$(dirname "$0")/.."

IMAGE="build/copal-vm.img"
OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --image) IMAGE="$2"; shift 2 ;;
        --out)   OUT="$2"; shift 2 ;;
        -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
        *) echo "collect-logs.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

info() { printf '\033[36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }

# No date(1) in the name from inside a recording -- but this is not recorded,
# and a collection needs to be told apart from the one before it.
[ -n "$OUT" ] || OUT="build/logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

# --- 1. the Mac's own transcripts ---------------------------------------
info "Host build transcripts"
for _f in build/copal-prep-auto-*.log build/copal-vm-check.log \
          build/copal-verify.log build/copal-screens-serial.log \
          build/*-build-times.tsv; do
    [ -f "$_f" ] || continue
    cp "$_f" "$OUT/" 2>/dev/null && printf '    %s\n' "$_f" >&2
done

# --- 2. the boot partition, without leaving a mount behind ---------------
if [ ! -f "$IMAGE" ]; then
    warn "no image at $IMAGE -- skipping the install transcript"
else
    info "Attaching $IMAGE to read the install transcript"
    DEV=""
    detach() {
        [ -n "$DEV" ] && hdiutil detach "$DEV" >/dev/null 2>&1 || true
    }
    trap detach EXIT INT TERM

    _att=$(hdiutil attach -imagekey diskimage-class=CRawDiskImage "$IMAGE" 2>/dev/null)
    DEV=$(printf '%s\n' "$_att" | awk '/^\/dev\/disk[0-9]+ /{print $1; exit}')
    MNT=$(printf '%s\n' "$_att" | awk -F'\t' '/COPALBOOT/{print $NF}' | head -1)

    if [ -z "${MNT:-}" ]; then
        warn "no COPALBOOT partition mounted -- is this a Copal image?"
    else
        info "Boot partition at $MNT"
        for _f in firstrun.log copal-build copal.conf copal-profile copal-auto \
                  copal-timings answers.txt usercfg.txt; do
            [ -f "$MNT/$_f" ] || continue
            # answers.txt carries a password hash; it is copied because a log
            # collection that silently omits the file that explains a failed
            # stage 1 is not much of a collection -- but it is named here so
            # nobody is surprised, and build/ is gitignored.
            cp "$MNT/$_f" "$OUT/" 2>/dev/null && printf '    %s\n' "$_f" >&2
        done
        # The install's own per-stage records, where they exist.
        for _d in copal var/log; do
            [ -d "$MNT/$_d" ] || continue
            mkdir -p "$OUT/boot-$(basename "$_d")"
            cp -R "$MNT/$_d/." "$OUT/boot-$(basename "$_d")/" 2>/dev/null || true
        done
    fi
    detach; DEV=""; trap - EXIT INT TERM
fi

# --- 3. the running guest, if one is reachable ---------------------------
if utm/utm-vm.sh status --target aarch64 2>/dev/null | grep -q 'Status *started'; then
    info "A UTM machine is running -- trying its logs over SSH"
    utm/utm-vm.sh log --target aarch64 > "$OUT/utm-guest.log" 2>&1 \
        && printf '    utm-guest.log\n' >&2 \
        || { rm -f "$OUT/utm-guest.log"
             warn "could not reach the guest over SSH (stage 1 may not have run yet)"; }
fi

# --- 4. a summary that answers the questions worth asking ----------------
#
# Grep, not eyes. These are the specific strings that distinguish "it worked"
# from "it printed a lot and failed", and they are the same ones a person
# would look for by hand at two in the morning.
SUM="$OUT/SUMMARY.txt"
{
    printf 'Copal log collection\n'
    printf 'image      %s\n' "$IMAGE"
    printf 'collected  %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if [ -f "$OUT/copal-build" ]; then
        printf -- '--- build stamp ---\n'
        cat "$OUT/copal-build"
        printf '\n'
    fi
    if [ -f "$OUT/copal-profile" ]; then
        printf -- '--- install level chosen --- %s\n\n' "$(cat "$OUT/copal-profile")"
    fi

    printf -- '--- what to worry about ---\n'
    for _pat in \
        'Config error'          \
        'ERROR|error:'          \
        'failed|FAILED'         \
        'not found'             \
        'No space left'         \
        'ENOSPC'                ; do
        _n=$(grep -riEc "$_pat" "$OUT" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
        printf '  %-24s %s\n' "$_pat" "$_n"
    done

    printf '\n--- did the stages run ---\n'
    for _s in 'Stage 1:' 'Stage 2:' 'Stage 3:' 'Stage 4:' 'Stage 5:' \
              'Stage 7:' 'Stage 16:' ; do
        if grep -rqF "$_s" "$OUT" 2>/dev/null; then
            printf '  %-12s reached\n' "$_s"
        else
            printf '  %-12s not seen\n' "$_s"
        fi
    done

    printf '\n--- the Wayland desktop (stage 16) ---\n'
    for _k in 'Installing Hyprland' 'seatd running' 'quickshell is not packaged' \
              'session = wayland' 'setuid server disarmed' \
              'Linux Antiquity configs' 'JetBrains Mono substituted' \
              'GTK 3 and 4' 'fonts installed system-wide' ; do
        if grep -rqF "$_k" "$OUT" 2>/dev/null; then
            printf '  [seen]    %s\n' "$_k"
        else
            printf '  [absent]  %s\n' "$_k"
        fi
    done
} > "$SUM"

info "Collected into $OUT"
printf '\n' >&2
sed 's/^/    /' "$SUM" >&2
printf '\n' >&2
