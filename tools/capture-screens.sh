#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 paulr@sdf.org -- part of Copal Linux.
#
# capture-screens.sh -- real screenshots of the graphical console, taken by
# the hypervisor rather than by a person with a camera or a screen recorder.
#
# THE PROBLEM THIS SOLVES. capture-media.sh records the serial console, which
# is text, and a compositor does not draw to a serial console. So the two
# desktop images the page wants -- Hyprland with the theme, and i3 on the
# framebuffer -- could not be captured that way and were left as a manual job.
#
# THE TRICK IS QEMU'S OWN MONITOR. `screendump` tells QEMU to write the
# guest's framebuffer to a file, exactly as the guest is drawing it. That is a
# real screenshot: the actual pixels, at the guest's real resolution, with no
# window manager, compositor or camera in between, and no display attached at
# all. It works headless, so nothing appears on your screen and nothing can
# steal focus while it runs.
#
# It is also the only route that does not require the guest's cooperation:
# grim needs a running Wayland session and a way to copy the file back out,
# and if the desktop is broken -- which is exactly when you want a picture --
# neither is available. The hypervisor can always see the screen.
#
# Usage:
#   tools/capture-screens.sh --image build/copal-vm.img --out docs/media
#   tools/capture-screens.sh --wait 240 --shots 6 --interval 20
#
# The image must already have a desktop installed; this boots it and
# photographs what comes up. Run it after an install, not instead of one.
set -uo pipefail

cd "$(dirname "$0")/.."

IMAGE="build/copal-vm.img"
OUT="docs/media"
WAIT=150          # seconds to let the guest boot before the first shot
SHOTS=6           # how many to take
INTERVAL=20       # seconds between them
PREFIX="screen"

while [ $# -gt 0 ]; do
    case "$1" in
        --image)    IMAGE="$2"; shift 2 ;;
        --out)      OUT="$2"; shift 2 ;;
        --wait)     WAIT="$2"; shift 2 ;;
        --shots)    SHOTS="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --prefix)   PREFIX="$2"; shift 2 ;;
        -h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "capture-screens.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

info() { printf '\033[36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$IMAGE" ] || die "no image at $IMAGE"
command -v qemu-system-aarch64 >/dev/null 2>&1 || die "qemu-system-aarch64 not installed"
mkdir -p "$OUT" build

# The firmware, found the same way copal-vm.sh finds it rather than by a
# second hard-coded guess that can disagree with the first.
FW=""
for _c in /opt/homebrew/opt/qemu/share/qemu/edk2-aarch64-code.fd \
          /usr/local/opt/qemu/share/qemu/edk2-aarch64-code.fd \
          /opt/homebrew/share/qemu/edk2-aarch64-code.fd; do
    [ -f "$_c" ] && { FW="$_c"; break; }
done
[ -n "$FW" ] || die "no edk2-aarch64-code.fd -- is qemu installed?"

VARS="build/copal-screens-efivars.fd"
[ -f "$VARS" ] || { dd if=/dev/zero of="$VARS" bs=1m count=64 2>/dev/null; }

MON="build/copal-screens.monitor"
rm -f "$MON"

# -display none, and a virtio GPU that still exists. The device is what has a
# framebuffer to dump; the display is only how a human would look at it, and
# there is no human here. HVF because a desktop under software emulation
# takes long enough to boot that the screenshots would be of a machine still
# starting up.
info "Booting $IMAGE headless with a monitor socket"
qemu-system-aarch64 \
    -machine virt,accel=hvf -cpu host -smp 2 -m 2048 \
    -drive "if=pflash,format=raw,readonly=on,file=$FW" \
    -drive "if=pflash,format=raw,file=$VARS" \
    -drive "if=virtio,format=raw,file=$IMAGE" \
    -device virtio-gpu-pci -device qemu-xhci \
    -device usb-kbd -device usb-tablet \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -display none \
    -monitor "unix:$MON,server,nowait" \
    -serial "file:build/copal-screens-serial.log" &
QEMU_PID=$!

# However this exits -- a die, a Ctrl-C, the end of the script -- the machine
# is stopped. A QEMU left running headless is invisible and holds the image
# open, which the next build then cannot replace.
cleanup() {
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
    rm -f "$MON"
}
trap cleanup EXIT INT TERM

# The monitor socket appears a moment after QEMU starts.
for _i in $(seq 1 50); do
    [ -S "$MON" ] && break
    sleep 0.2
done
[ -S "$MON" ] || die "QEMU never created its monitor socket"

monitor() {  # <command>
    # A socket that is written to and immediately closed; the monitor accepts
    # one command per connection quite happily, and this avoids holding a
    # session open across the whole boot.
    printf '%s\n' "$1" | nc -U "$MON" >/dev/null 2>&1 \
        || printf '%s\n' "$1" | socat - "UNIX-CONNECT:$MON" >/dev/null 2>&1
}

info "Letting the guest boot for ${WAIT}s before the first shot"
sleep "$WAIT"

TAKEN=0
for _n in $(seq 1 "$SHOTS"); do
    PPM="$(pwd)/build/${PREFIX}-${_n}.ppm"
    rm -f "$PPM"
    # An absolute path: screendump is executed by QEMU, whose working
    # directory is not necessarily this one.
    monitor "screendump $PPM"

    # QEMU writes asynchronously; wait for the file to appear AND stop
    # growing, or a converted half-written frame comes out as a torn image.
    for _w in $(seq 1 25); do
        [ -s "$PPM" ] && break
        sleep 0.2
    done
    if [ ! -s "$PPM" ]; then
        warn "shot $_n: nothing was written -- no framebuffer yet?"
        sleep "$INTERVAL"
        continue
    fi
    _a=$(wc -c < "$PPM"); sleep 0.4; _b=$(wc -c < "$PPM")
    [ "$_a" = "$_b" ] || sleep 0.6

    PNG="$OUT/${PREFIX}-${_n}.png"
    # sips ships with macOS and needs nothing installed; ffmpeg is the
    # fallback for anywhere it does not.
    if command -v sips >/dev/null 2>&1 && sips -s format png "$PPM" --out "$PNG" >/dev/null 2>&1; then
        :
    elif command -v ffmpeg >/dev/null 2>&1 && ffmpeg -y -loglevel error -i "$PPM" "$PNG" 2>/dev/null; then
        :
    else
        warn "cannot convert PPM to PNG (no sips, no ffmpeg) -- keeping $PPM"
        PNG="$PPM"
    fi
    rm -f "$PPM"

    if [ -s "$PNG" ]; then
        TAKEN=$((TAKEN + 1))
        info "shot $_n -> $PNG ($(du -h "$PNG" | cut -f1))"
    fi
    [ "$_n" = "$SHOTS" ] || sleep "$INTERVAL"
done

info "Sending the machine a power button press"
monitor "system_powerdown"
sleep 3

if [ "$TAKEN" = 0 ]; then
    warn "no screenshots were captured."
    printf '    %s\n' \
      "The usual cause is that the guest had not drawn anything yet: raise" \
      "--wait, or check build/copal-screens-serial.log to see how far it got." >&2
    exit 1
fi

info "$TAKEN screenshot(s) in $OUT"
