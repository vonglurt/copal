#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Paul Richeson -- part of Copal Linux.
#
#  copal-gfx-probe.sh -- what is the guest's graphics stack doing, right now?
#
# Runs INSIDE the guest, as the desktop user, on a running Hyprland session.
# It answers the questions docs/visual-debugging-lab-report.md asks after every
# restart, and writes them down so the restart-and-test loop has a memory:
#
#   - which renderer the compositor got (virgl, or llvmpipe software)
#   - which features the host's virtio-gpu is offering
#   - the Hyprland settings the lab found matter (cm_enabled, blur, damage)
#   - what the compositor and the bar cost, in CPU, over three seconds
#   - a screenshot, plus a pixel check of the bar: is it a black block?
#
# Output: a report on stdout, the same report saved under ~/copal-gfx/, the
# screenshots beside it, and ONE summary line appended to ~/copal-gfx/log.txt
# (or $COPAL_GFX_LOG). The summary line is the thing to paste into the lab
# report's restart log.
#
# Exit status is the number of FAILED checks, so `&& echo ok` works.
#
# Nothing here changes any setting. Every command is read-only.
set -u

OUT="${COPAL_GFX_DIR:-$HOME/copal-gfx}"
LOG="${COPAL_GFX_LOG:-$OUT/log.txt}"
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
REPORT="$OUT/probe-$STAMP.txt"
LABEL="${1:-}"

fails=0
say()  { printf '%s\n' "$*" | tee -a "$REPORT"; }
pass() { say "  PASS  $*"; }
fail() { say "  FAIL  $*"; fails=$((fails+1)); }
warn() { say "  WARN  $*"; }

# CPU% of a pid over three seconds, from /proc, no top needed. Empty pid -> "-".
cpu3() {
    [ -n "${1:-}" ] || { echo '-'; return; }
    a=$(awk '{print $14+$15}' "/proc/$1/stat" 2>/dev/null) || { echo '-'; return; }
    sleep 3
    b=$(awk '{print $14+$15}' "/proc/$1/stat" 2>/dev/null) || { echo '-'; return; }
    echo $(( (b - a) / 3 ))
}

say "copal-gfx-probe  $STAMP  ${LABEL:+[$LABEL]}"
say "  host: $(uname -n)  kernel: $(uname -r)  uptime: $(cut -d. -f1 /proc/uptime)s"
say "  hyprland: $(hyprctl version 2>/dev/null | head -1 | sed 's/ built.*//')"
say "  mesa: $(apk info mesa 2>/dev/null | head -1 | sed 's/ .*//')"

# ---- 1. the device -------------------------------------------------------
say ""
say "== virtio-gpu"
# card0/device is the PCI function (driver virtio-pci); the DRM driver hangs
# off the virtio child underneath it.
drv=""
for l in /sys/class/drm/card0/device/virtio*/driver /sys/class/drm/card0/device/driver; do
    [ -e "$l" ] && drv=$(basename "$(readlink "$l")") && break
done
say "  kernel driver: ${drv:-unknown}"
vdev=""
for d in /sys/bus/virtio/devices/virtio*; do
    [ "$(cat "$d/device" 2>/dev/null)" = "0x0010" ] && vdev=$d && break
done
if [ -n "$vdev" ]; then
    f=$(cat "$vdev/features")
    # bit 0 VIRGL (3D via OpenGL), 1 EDID, 2 RESOURCE_UUID, 3 RESOURCE_BLOB,
    # 4 CONTEXT_INIT. Blob + context_init together are what Venus (Vulkan
    # over virtio) needs; VIRGL alone is what UTM's "GPU supported" cards give.
    virgl=${f%"${f#?}"}; blob=$(printf '%s' "$f" | cut -c4); ctx=$(printf '%s' "$f" | cut -c5)
    say "  features: virgl=$virgl blob=$blob context_init=$ctx   ($vdev)"
    if [ "$virgl" = 1 ]; then say "  host offers VIRGL 3D"; else say "  host offers 2D only (no virgl)"; fi
else
    warn "no virtio GPU device found under /sys/bus/virtio"
fi

# ---- 2. the renderer -----------------------------------------------------
say ""
say "== renderer (EGL on GBM, the path Hyprland takes)"
egl=$(eglinfo -B 2>/dev/null | sed -n '/GBM platform/,/^$/p')
renderer=$(printf '%s\n' "$egl" | grep -m1 'core profile renderer' | sed 's/.*renderer: //')
missing=$(eglinfo -B 2>&1 | grep -c 'driver missing')
say "  renderer: ${renderer:-unknown}"
[ "$missing" -gt 0 ] && say "  mesa loader: 'virtio_gpu: driver missing' x$missing (virgl not compiled into this Mesa)"
case "$renderer" in
    *virgl*) pass "hardware path: virgl in use" ;;
    *llvmpipe*|*softpipe*) warn "software rendering (llvmpipe): every frame is drawn on the CPU" ;;
    *) fail "renderer unknown -- eglinfo could not create a screen" ;;
esac

# ---- 3. the settings the lab found matter --------------------------------
say ""
say "== hyprland settings"
opt() { hyprctl getoption "$1" 2>/dev/null | awk '/^\t*(int|float|str):/ {print $2; exit}'; }
cm=$(opt render:cm_enabled); blur=$(opt decoration:blur:enabled)
dmg=$(opt debug:damage_tracking); hwc=$(opt cursor:no_hardware_cursors)
say "  render:cm_enabled=$cm  decoration:blur:enabled=$blur  debug:damage_tracking=$dmg  cursor:no_hardware_cursors=$hwc"
if [ "$cm" = 0 ]; then pass "colour management off (the llvmpipe black-layer bug is dodged)"
else warn "colour management ON: expect black bars/widgets/notifications on llvmpipe"; fi
if [ "$hwc" = 1 ]; then pass "software cursor"; else warn "hardware cursor plane in use on virtio-gpu"; fi
say "  monitor: $(hyprctl monitors 2>/dev/null | awk '/^\t[0-9]+x[0-9]+@/ {print $1; exit}')  format: $(hyprctl monitors 2>/dev/null | awk '/currentFormat/ {print $2; exit}')"

# ---- 4. what it costs ----------------------------------------------------
say ""
say "== cpu over 3 s (a busy terminal drives the compositor; idle is the honest number)"
hp=$(pgrep -x Hyprland | head -1); wp=$(pgrep -f '^waybar$' | head -1)
hc=$(cpu3 "$hp"); wc=$(cpu3 "$wp")
say "  Hyprland: ${hc}%   waybar (main bar): ${wc}%"
if [ "$wc" = '-' ]; then fail "no main waybar running"
elif [ "$wc" -ge 50 ]; then fail "waybar is spinning at ${wc}% (the custom/menu exec+once bug?)"
else pass "waybar idle"; fi

# ---- 5. what is on screen ------------------------------------------------
say ""
say "== layers"
hyprctl layers 2>/dev/null | grep namespace | sed 's/^[[:space:]]*/  /' | tee -a "$REPORT"

say ""
say "== screenshot"
shot="$OUT/shot-$STAMP.png"
if grim "$shot" 2>/dev/null; then
    say "  full screen: $shot"
else
    fail "grim could not capture the screen"; shot=""
fi
# The bar strip: find the waybar layer's geometry and count its colours. A
# correctly drawn bar has hundreds; the bug renders exactly one (black).
geom=$(hyprctl layers 2>/dev/null | awk '/namespace: waybar,/ {sub(/.*xywh: /,""); gsub(/,/,""); print $1","$2" "$3"x"$4; exit}')
if [ -n "$geom" ] && grim -g "$geom" "$OUT/bar-$STAMP.png" 2>/dev/null; then
    ncol=$(magick "$OUT/bar-$STAMP.png" -format '%k' info:- 2>/dev/null || echo '?')
    top=$(magick "$OUT/bar-$STAMP.png" -format '%c' histogram:info:- 2>/dev/null | sort -rn | head -1 | sed 's/^ *[0-9]*: //; s/ .*//')
    say "  bar strip $geom -> $OUT/bar-$STAMP.png : $ncol colours, dominant $top"
    if [ "$ncol" = '?' ]; then warn "imagemagick missing, cannot judge the bar"
    elif [ "$ncol" -le 2 ]; then fail "bar is a flat block ($top) -- the black-layer bug"
    else pass "bar has content"; fi
else
    warn "no waybar layer to sample"
fi

# ---- 6. verdict ----------------------------------------------------------
say ""
say "== verdict: $fails failed check(s)"
summary="$STAMP ${LABEL:+[$LABEL] }renderer=$(printf '%s' "${renderer:-?}" | cut -d' ' -f1) virgl=${virgl:-?} cm=$cm blur=$blur dmg=$dmg hypr=${hc}% waybar=${wc}% bar=${ncol:-?}col fails=$fails"
printf '%s\n' "$summary" >> "$LOG"
say "  logged: $summary"
say "  -> $LOG"
exit "$fails"
