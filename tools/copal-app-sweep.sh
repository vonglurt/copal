#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 paulr@sdf.org -- part of Copal Linux.
#
# copal-app-sweep.sh -- run the gallery sweep: every row of the list through
# copal-app-probe.sh --gallery, one probe at a time, never two (a second
# probe's window gets attributed to the first and closed).
#
#   tools/copal-app-sweeplist.py                 # writes the list
#   setsid nohup tools/copal-app-sweep.sh > ~/.cache/copal-gallery/sweep.log 2>&1 < /dev/null &
#
# Detached like that it outlives the terminal it was started from. Progress:
# tail -f ~/.cache/copal-gallery/sweep.log; verdicts also land in ~/copal-apps/log.txt.
cd "$(dirname "$0")/.." || exit 1
LIST="${1:-$HOME/.cache/copal-gallery/gallery-list.txt}"
export PATH="$HOME/.cache/copal-bin:$PWD/tools:$PATH"
TAB="$(printf '\t')"
while IFS="$TAB" read -r name cmd act; do
    [ -n "$name" ] || continue
    case "$name" in winebox-*|winecfg) w=60 ;; *) w=30 ;; esac
    if [ -n "$act" ]; then set -- --act "copal-act $act"; else set --; fi
    echo "=== $(date +%H:%M:%S) $name"
    eval "tools/copal-app-probe.sh --wait $w --gallery docs/img/gallery \"\$@\" \"\$name\" $cmd"
done < "$LIST"
echo "=== $(date +%H:%M:%S) SWEEP DONE"
