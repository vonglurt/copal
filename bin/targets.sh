#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Paul Richeson
#
#  bin/targets.sh -- make targets
#
#  List the board names, one per line.
#
#  These are the names bin/sd.sh, bin/img.sh and MODEL= all take. `make
#  boards` is the same target under its other name.
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)" || exit 1
exec make targets "$@"
