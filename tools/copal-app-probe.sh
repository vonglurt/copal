#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Paul Richeson -- part of Copal Linux.
#
#  copal-app-probe.sh -- launch one program, watch what it does, write it down.
#
#   copal-app-probe.sh NAME [COMMAND [ARGS...]]     COMMAND defaults to NAME
#   copal-app-probe.sh --keep NAME ...              leave it running for you
#   copal-app-probe.sh --wait 40 NAME ...           seconds to allow for a window
#   copal-app-probe.sh --workspace 2 NAME ...       run it on that workspace (default 2)
#   copal-app-probe.sh --doc DIR NAME ...           also save a half-size PNG in DIR
#   copal-app-probe.sh --gallery DIR NAME ...       quarter-size, hard-compressed JPEG
#                                                   in DIR, every window moved to the
#                                                   probe workspace first (the gallery)
#   copal-app-probe.sh --act 'CMD' NAME ...         once the window is up and focused,
#                                                   run CMD (a first action: type a line,
#                                                   draw a stroke) before the picture
#
# WORKSPACE 2. The program is launched on its own workspace and the session
# doing the testing stays where it was (the probe switches back at the end),
# so the screenshot holds the program and nothing else, a fullscreen game
# does not land on the terminal driving it, and a typed first action cannot
# reach that terminal. Hyprland only; elsewhere it runs where it runs.
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
KEEP=0; WAIT=30; WS="${COPAL_PROBE_WORKSPACE:-2}"; DOC=""; GAL=""; ACT=""; ACTED=""
while [ $# -gt 0 ]; do
    case "$1" in
        --keep) KEEP=1; shift ;;
        --wait) WAIT="${2:?--wait needs seconds}"; shift 2 ;;
        --workspace) WS="${2:?--workspace needs a number}"; shift 2 ;;
        --doc) DOC="${2:?--doc needs a directory}"; shift 2 ;;
        --gallery) GAL="${2:?--gallery needs a directory}"; shift 2 ;;
        --act) ACT="${2:?--act needs a command}"; shift 2 ;;
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

# The pids above us -- the shell, the terminal it sits in, the compositor.
# A window owned by one of those is never the program's, is never counted
# as "new", and is never closed: on 2 Sep 2026 a clean-up by window class
# ("every foot window") closed the terminal the testing session lived in.
# Close by address or pid from the probe's own list, never by class.
PROTECT=" "; _p=$$
while [ "${_p:-1}" -gt 1 ] 2>/dev/null; do
    PROTECT="$PROTECT$_p "; _p=$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ')
done

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
pids = sys.argv[1].split(); keep_out = sys.argv[2].split()
for c in json.load(sys.stdin):
    if str(c.get("pid")) in pids and str(c.get("pid")) not in keep_out:
        print("%s|%s|%s|%s" % (c.get("pid"), c.get("class",""), c.get("title",""), c.get("address","")))' "$_pids" "$PROTECT"
    elif command -v xdotool >/dev/null 2>&1; then
        for _w in $(xdotool search --onlyvisible --name '' 2>/dev/null); do
            _wp=$(xdotool getwindowpid "$_w" 2>/dev/null) || continue
            case "$PROTECT" in *" $_wp "*) continue ;; esac
            case "$_pids" in *" $_wp "*) echo "$_wp|$(xdotool getwindowclassname "$_w" 2>/dev/null)|$(xdotool getwindowname "$_w" 2>/dev/null)|" ;; esac
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
keep_out = sys.argv[1].split()
for c in json.load(sys.stdin):
    if str(c.get("pid")) not in keep_out:
        print("%s|%s|%s|%s" % (c.get("pid"), c.get("class",""), c.get("title",""), c.get("address","")))' "$PROTECT"
    fi
}
HYPR=0
if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    HYPR=1
    WS_HOME=$(hyprctl activeworkspace -j 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])' 2>/dev/null)
    [ -n "$WS" ] && [ "$WS" != "$WS_HOME" ] && hyprctl dispatch workspace "$WS" >/dev/null 2>&1 && sleep 0.5
fi
BEFORE=$(all_windows | cut -d'|' -f4)
T0=$(date +%s)
setsid "$@" >"$LOG" 2>&1 &
PID=$!
n=0; WIN=""; DETACHED=0
new_windows() {
    all_windows | while IFS='|' read -r _p _c _t _a; do
        case "$BEFORE" in *"$_a"*) ;; *) echo "$_p|$_c|$_t|$_a" ;; esac
    done
}
while [ "$n" -lt "$WAIT" ]; do
    WIN=$(my_windows)
    [ -n "$WIN" ] && break
    # Wine, Flatpak and the like hand the window to a process outside our
    # tree while the launcher lives on. After a grace period, a window the
    # compositor did not have before the launch is taken as the program's.
    if [ "$n" -ge 8 ]; then
        WIN=$(new_windows); [ -n "$WIN" ] && { DETACHED=1; break; }
    fi
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
    # Every window the program opened goes to the probe workspace -- a dialog
    # or a second window that landed elsewhere would otherwise be out of frame.
    if [ "$HYPR" -eq 1 ] && [ -n "$WS" ]; then
        for _a in $(printf '%s' "$WIN" | cut -d'|' -f4); do
            [ -n "$_a" ] && hyprctl dispatch movetoworkspacesilent "$WS,address:$_a" >/dev/null 2>&1
        done
        sleep 1
    fi
    # The first action, if one was asked for: the program's largest window
    # is focused and its place on screen handed to the command, which types
    # or draws into it. Whatever it prints joins the program's log.
    if [ -n "$ACT" ]; then
        if [ "$HYPR" -eq 1 ]; then
            eval "$(hyprctl clients -j 2>/dev/null | python3 -c '
import json, sys
ours = sys.argv[1].split(); best = None
for c in json.load(sys.stdin):
    if c.get("address") in ours:
        a = c["size"][0] * c["size"][1]
        if best is None or a > best[0]: best = (a, c)
if best:
    c = best[1]
    print("COPAL_WIN_ADDR=%s COPAL_WIN_X=%d COPAL_WIN_Y=%d COPAL_WIN_W=%d COPAL_WIN_H=%d"
          % (c["address"], c["at"][0], c["at"][1], c["size"][0], c["size"][1]))' \
                "$(printf '%s' "$WIN" | cut -d'|' -f4 | tr '\n' ' ')")"
            [ -n "${COPAL_WIN_ADDR:-}" ] && hyprctl dispatch focuswindow "address:$COPAL_WIN_ADDR" >/dev/null 2>&1
            export COPAL_WIN_ADDR COPAL_WIN_X COPAL_WIN_Y COPAL_WIN_W COPAL_WIN_H
        fi
        sleep 1
        sh -c "$ACT" >>"$LOG" 2>&1 && ACTED=", acted" || ACTED=", act failed"
        sleep 2
    fi
fi

if command -v grim >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    grim "$PNG" 2>/dev/null
    [ -n "$DOC" ] && mkdir -p "$DOC" && grim -s 0.5 "$DOC/$NAME.png" 2>/dev/null
    # The gallery picture: a quarter of the screen's pixels, JPEG at a
    # quality that keeps the shape of a window and not much else -- about
    # 10-15 KB, so a hundred and fifty of them fit in a document.
    if [ -n "$GAL" ]; then
        mkdir -p "$GAL"
        if command -v magick >/dev/null 2>&1; then
            magick "$PNG" -resize 25% -strip -interlace Plane -sampling-factor 4:2:0 -quality 70 "$GAL/$NAME.jpg" 2>/dev/null
        else
            grim -s 0.25 "$GAL/$NAME.png" 2>/dev/null
        fi
    fi
elif command -v scrot >/dev/null 2>&1; then scrot -o "$PNG" 2>/dev/null
elif command -v import >/dev/null 2>&1; then import -window root "$PNG" 2>/dev/null; fi

NWIN=$(printf '%s' "$WIN" | grep -c '|')
WIN=$(printf '%s' "$WIN" | cut -d'|' -f1-3)   # the address has done its job
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
            case "$PROTECT" in *" $_p "*) continue ;; esac
            hyprctl dispatch closewindow "pid:$_p" >/dev/null 2>&1
        done
    fi
    sleep 2
    for _p in $(descendants "$PID" | sort -rn); do kill "$_p" 2>/dev/null; done
    sleep 1
    for _p in $(descendants "$PID" | sort -rn); do kill -9 "$_p" 2>/dev/null; done
fi

# Back to where the person is.
[ "$HYPR" -eq 1 ] && [ -n "${WS_HOME:-}" ] && [ "$WS" != "$WS_HOME" ] && [ "$KEEP" -eq 0 ] \
    && hyprctl dispatch workspace "$WS_HOME" >/dev/null 2>&1

if [ -z "$WIN" ]; then
    VERDICT="NO WINDOW in ${WAIT}s, process $ALIVE"
elif [ "$WIZ" -gt 0 ]; then
    VERDICT="WIZARD ${TWIN}s ($NWIN window$( [ "$NWIN" -ne 1 ] && echo s))$ACTED"
else
    VERDICT="ok ${TWIN}s ($NWIN window$( [ "$NWIN" -ne 1 ] && echo s))$( [ "$DETACHED" -eq 1 ] && echo ', detached')$ACTED"
fi
LINE=$(printf '%s  %-18s %-28s stderr:%-3s %s%s' "$(date +%H:%M)" "$NAME" "$VERDICT" "$ERRS" \
        "$( [ -n "$TITLES" ] && printf '[%s] ' "$TITLES")" "$( [ -n "$FIRST" ] && printf -- '-- %s' "$FIRST")")
echo "$LINE" | tee -a "$OUT/log.txt"
[ "$KEEP" -eq 1 ] && echo "left running as pid $PID; log: $LOG"
exit 0
