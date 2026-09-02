#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 paulr@sdf.org -- part of Copal Linux.
#
#  copal-app-probe.sh -- launch one program, watch what it does, write it down.
#
#   copal-app-probe.sh NAME [COMMAND [ARGS...]]     COMMAND defaults to NAME
#   copal-app-probe.sh --keep NAME ...              leave it running for you
#   copal-app-probe.sh --wait 40 NAME ...           seconds to allow for a window
#
# The integration test for a desktop program is dull and has to be done a
# hundred times: start it, see whether a window appears, see whether that
# window is the program or a first-run wizard, read what it printed, close it.
# This does exactly that, on the running Hyprland (or X11) session, and leaves
# behind the three things worth keeping:
#
#   ~/copal-apps/NAME.png       what was on screen when the window had settled
#   ~/copal-apps/NAME.log       everything it wrote to stdout and stderr
#   ~/copal-apps/log.txt        one summary line per run, appended -- the
#                               inventory table in docs/app-integration-plan.md
#                               is filled in from this
#
# A window is recognised by the compositor: hyprctl lists clients with their
# pid, and a client whose pid is the program or one of its descendants is ours.
# Titles are matched against the words wizards use ("Welcome", "Setup",
# "Account", "First", "Wizard", "Assistant"), because a wizard on first launch
# is precisely the thing this exercise exists to find and then design away.
set -u
KEEP=0; WAIT=30
while [ $# -gt 0 ]; do
    case "$1" in
        --keep) KEEP=1; shift ;;
        --wait) WAIT="${2:?--wait needs seconds}"; shift 2 ;;
        --) shift; break ;;
        -*) echo "copal-app-probe: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
NAME="${1:?usage: copal-app-probe.sh [--keep] [--wait N] NAME [COMMAND ARGS...]}"; shift
[ $# -gt 0 ] || set -- "$NAME"
OUT="$HOME/copal-apps"; mkdir -p "$OUT"
LOG="$OUT/$NAME.log"; PNG="$OUT/$NAME.png"

command -v "$1" >/dev/null 2>&1 || {
    printf '%s  %-18s NOT INSTALLED (%s)\n' "$(date +%H:%M)" "$NAME" "$1" | tee -a "$OUT/log.txt"; exit 3; }

# Every pid under ours, for matching windows to the program. Programs fork
# (electron, flatpak, java) and the window's pid is rarely the one we started.
descendants() {  # <pid>
    _p="$1"; echo "$_p"
    for _c in $(pgrep -P "$_p" 2>/dev/null); do descendants "$_c"; done
}
my_windows() {  # prints "pid|class|title" for our windows
    _pids=" $(descendants "$PID" | tr '\n' ' ') "
    if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        hyprctl clients -j 2>/dev/null | python3 -c '
import json, sys
pids = sys.argv[1].split()
for c in json.load(sys.stdin):
    if str(c.get("pid")) in pids:
        print("%s|%s|%s" % (c.get("pid"), c.get("class",""), c.get("title","")))' "$_pids"
    elif command -v xdotool >/dev/null 2>&1; then
        for _w in $(xdotool search --onlyvisible --name '' 2>/dev/null); do
            _wp=$(xdotool getwindowpid "$_w" 2>/dev/null) || continue
            case "$_pids" in *" $_wp "*) echo "$_wp|$(xdotool getwindowclassname "$_w" 2>/dev/null)|$(xdotool getwindowname "$_w" 2>/dev/null)" ;; esac
        done
    fi
}

# Some programs re-launch themselves detached (Lapce execs "lapce --wait"
# and exits 0), so their window has no ancestor of ours. Fallback: any
# window the compositor did not have before the launch is taken as theirs.
all_windows() {
    if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        hyprctl clients -j 2>/dev/null | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    print("%s|%s|%s|%s" % (c.get("pid"), c.get("class",""), c.get("title",""), c.get("address","")))'
    fi
}
BEFORE=$(all_windows | cut -d'|' -f4)
T0=$(date +%s)
setsid "$@" >"$LOG" 2>&1 &
PID=$!
n=0; WIN=""; DETACHED=0
new_windows() {
    all_windows | while IFS='|' read -r _p _c _t _a; do
        case "$BEFORE" in *"$_a"*) ;; *) echo "$_p|$_c|$_t" ;; esac
    done
}
while [ "$n" -lt "$WAIT" ]; do
    WIN=$(my_windows)
    [ -n "$WIN" ] && break
    if ! kill -0 "$PID" 2>/dev/null; then
        # It exited. Keep watching for the rest of the wait: a re-launched
        # copy opens its window well after the launcher has gone.
        while [ "$n" -lt "$WAIT" ]; do
            WIN=$(new_windows); [ -n "$WIN" ] && { DETACHED=1; break; }
            n=$((n + 1)); sleep 1
        done
        break
    fi
    n=$((n + 1)); sleep 1
done
TWIN=$(( $(date +%s) - T0 ))
# Let it draw, and let a wizard that follows the main window arrive.
if [ -n "$WIN" ]; then
    sleep 5
    if [ "$DETACHED" -eq 1 ]; then WIN=$(new_windows); else WIN=$(my_windows); fi
fi

if command -v grim >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then grim "$PNG" 2>/dev/null
elif command -v scrot >/dev/null 2>&1; then scrot -o "$PNG" 2>/dev/null
elif command -v import >/dev/null 2>&1; then import -window root "$PNG" 2>/dev/null; fi

NWIN=$(printf '%s' "$WIN" | grep -c '|')
TITLES=$(printf '%s' "$WIN" | cut -d'|' -f3 | tr '\n' ';' | cut -c1-90)
WIZ=$(printf '%s' "$WIN" | cut -d'|' -f3 | grep -i -c 'welcome\|setup\|wizard\|assistant\|getting started\|first run\|legal notice' || true)
# wait must run in this shell, not a subshell: only the parent can collect
# the exit status, and a subshell answers 127 for every finished child.
if kill -0 "$PID" 2>/dev/null; then ALIVE=yes; else wait "$PID" 2>/dev/null; ALIVE="no (exit $?)"; fi
ERRS=$(grep -i -c 'error\|fail\|cannot\|no such\|not found\|warning' "$LOG" 2>/dev/null)
FIRST=$(grep -i -m1 'error\|fail\|cannot\|not found' "$LOG" 2>/dev/null | cut -c1-100)

if [ "$KEEP" -eq 0 ]; then
    if command -v hyprctl >/dev/null 2>&1; then
        for _p in $(printf '%s' "$WIN" | cut -d'|' -f1 | sort -u); do
            hyprctl dispatch closewindow "pid:$_p" >/dev/null 2>&1
        done
    fi
    sleep 2
    for _p in $(descendants "$PID" | sort -rn); do kill "$_p" 2>/dev/null; done
    sleep 1
    for _p in $(descendants "$PID" | sort -rn); do kill -9 "$_p" 2>/dev/null; done
fi

if [ -z "$WIN" ]; then
    VERDICT="NO WINDOW in ${WAIT}s, process $ALIVE"
elif [ "$WIZ" -gt 0 ]; then
    VERDICT="WIZARD ${TWIN}s ($NWIN window$( [ "$NWIN" -ne 1 ] && echo s))"
else
    VERDICT="ok ${TWIN}s ($NWIN window$( [ "$NWIN" -ne 1 ] && echo s))$( [ "$DETACHED" -eq 1 ] && echo ', detached')"
fi
LINE=$(printf '%s  %-18s %-28s stderr:%-3s %s%s' "$(date +%H:%M)" "$NAME" "$VERDICT" "$ERRS" \
        "$( [ -n "$TITLES" ] && printf '[%s] ' "$TITLES")" "$( [ -n "$FIRST" ] && printf -- '-- %s' "$FIRST")")
echo "$LINE" | tee -a "$OUT/log.txt"
[ "$KEEP" -eq 1 ] && echo "left running as pid $PID; log: $LOG"
exit 0
