#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Paul Richeson
#
#  bin/graphical.sh -- make graphical
#
#  Boot the VM in a window, to watch i3 come up.
#
#  The same boot as bin/vm.sh, in a window rather than on this terminal.
#
#      bin/graphical.sh MEM=4096
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)" || exit 1
exec make graphical "$@"
