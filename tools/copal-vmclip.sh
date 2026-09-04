#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Paul Richeson -- part of Copal Linux.
#
#  copal-vmclip -- share the clipboard with the host, when this is a VM.
#
# Copy on the Mac, Super+V in the guest; Super+C in the guest, Cmd+V on the
# Mac. UTM does that over SPICE, and the guest half of SPICE is two programs:
# spice-vdagentd, the root daemon that owns the virtio port (an OpenRC
# service, started at boot), and spice-vdagent, the per-session client that
# actually reads and writes a clipboard. The client is X11-only, and Copal's
# desktop is Wayland. So this script does two things and then stays out of
# the way:
#
#   1. starts spice-vdagent against Xwayland (:0), which every Hyprland
#      session has, so the host side works exactly as it does on X;
#   2. relays text between the Wayland clipboard (what Super+C and every
#      Wayland program use) and the X clipboard (what spice-vdagent watches),
#      in both directions, without echoing a change back to where it came from.
#
# Xwayland bridges the two selections itself ONLY while an X window has the
# keyboard focus, which on a Wayland desktop is almost never -- measured on
# 2026-09-02, neither direction crossed. Hence the relay.
#
# On a machine that is not a SPICE guest there is no port, and this exits at
# once, silently: it is safe to start everywhere. Text only, on purpose --
# images and files are a different protocol and a different day.
#
# Started by hyprland's exec-once. Run it by hand with -d to watch it work.
set -u

PORT=/dev/virtio-ports/com.redhat.spice.0
SOCK=/run/spice-vdagentd/spice-vdagent-sock
TICK=0.3

have() { command -v "$1" >/dev/null 2>&1; }
log()  { [ -n "${DEBUG:-}" ] && printf 'copal-vmclip: %s\n' "$*" >&2; return 0; }
warn() { printf 'copal-vmclip: %s\n' "$*" >&2; }

[ "${1:-}" = -d ] && DEBUG=1
[ -e "$PORT" ] || { log "no SPICE port at $PORT: not a SPICE guest, nothing to do"; exit 0; }
for t in wl-copy wl-paste xclip spice-vdagent; do
    have "$t" || { warn "$t is missing (apk add wl-clipboard xclip spice-vdagent)"; exit 1; }
done
[ -S "$SOCK" ] || warn "spice-vdagentd is not running -- as root: rc-service spice-vdagentd start; rc-update add spice-vdagentd"

# One relay per session. busybox flock is enough.
LOCK="${XDG_RUNTIME_DIR:-/tmp}/copal-vmclip.lock"
exec 9>"$LOCK"
flock -n 9 || { log "already running"; exit 0; }

: "${DISPLAY:=:0}"; export DISPLAY
# Xwayland is what we relay through; wait for it rather than race the login.
n=0
until [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ] || [ $n -ge 30 ]; do sleep 1; n=$((n+1)); done

# ---- 1. the SPICE session client -----------------------------------------
if ! pgrep -x spice-vdagent >/dev/null 2>&1; then
    # -x keeps it in the foreground as our child, so it goes when we go.
    spice-vdagent -x >/dev/null 2>&1 &
    log "started spice-vdagent (pid $!)"
fi

# ---- 2. the relay ---------------------------------------------------------
D=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/copal-vmclip.XXXXXX")
trap 'kill 0 2>/dev/null; rm -rf "$D"' EXIT INT TERM HUP
: > "$D/w.cur"; : > "$D/x.cur"

get_w() { timeout 2 wl-paste --no-newline --type text 2>/dev/null; }
get_x() { timeout 2 xclip -selection clipboard -o -t UTF8_STRING 2>/dev/null \
       || timeout 2 xclip -selection clipboard -o 2>/dev/null; }
# Both setters fork a holder that owns the selection until someone else takes
# it; the previous holder exits on its own.
set_w() { wl-copy --type text/plain < "$1"; }
set_x() { xclip -selection clipboard -i < "$1"; }

log "relaying wayland <-> x11 clipboard, every ${TICK}s"
while :; do
    get_w > "$D/w.new" || :
    if [ -s "$D/w.new" ] && ! cmp -s "$D/w.new" "$D/w.cur"; then
        # Wayland changed (Super+C, wl-copy, any program): hand it to X, so
        # spice-vdagent announces it to the host.
        cp "$D/w.new" "$D/w.cur"; cp "$D/w.new" "$D/x.cur"
        set_x "$D/w.cur"
        log "wayland -> x11 ($(wc -c < "$D/w.cur") bytes)"
    else
        get_x > "$D/x.new" || :
        if [ -s "$D/x.new" ] && ! cmp -s "$D/x.new" "$D/x.cur"; then
            # X changed, and Wayland did not: that is the host (via
            # spice-vdagent) or an X program. Hand it to Wayland.
            cp "$D/x.new" "$D/x.cur"; cp "$D/x.new" "$D/w.cur"
            set_w "$D/x.cur"
            log "x11 -> wayland ($(wc -c < "$D/x.cur") bytes)"
        fi
    fi
    sleep "$TICK"
done
