# Installing Extra Packages and Libraries During Integration Testing: What a Full Copal Guest Was Missing, and How Each Gap Was Closed

*Lab Report — IEEE Format*

<!-- SPDX-License-Identifier: MIT -->
Copyright (c) 2026 paulr@sdf.org. MIT licensed — see `LICENSE`. Copal Linux is
an aggregation of Alpine Linux, not a derivative work of it; Alpine and its
packages remain under their own licences.

---

## Abstract

A Copal guest with the whole application catalogue installed (304 entries, on
an aarch64 VM under UTM) was used as the integration bench for the question
"the package is installed — is the program usable?". Five gaps were found by
launching things rather than by reading package lists, and each was closed in
the installer so that a clean install reproduces the fix: KiCad's templates,
demos and plugins (a separate report, `kicad-lab-report.md`); the host's
shared folder, which an earlier fstab line had silently prevented copal from
mounting at all; wxMaxima, which Alpine does not package on any port and
which builds from source in under five minutes; a sound card the guest kernel
cannot drive, which is a host setting and not a package; and a yt-dlp queue
built on the cookie handling copal already had. A launch probe was written so
the remaining programs can be tested one at a time, and a plan for doing so
is in `app-integration-plan.md`. The recurring lesson is stated in section V:
the package manager's answer and the program's answer differ, and only the
second one counts.

## I. Objective

1. Treat a fully installed guest as an integration bench: for each program,
   does it start, does it start *into itself* rather than into a wizard or an
   error, and what does it need that the package did not bring?
2. Close every gap found in the installer, not on the bench, so a later clean
   install carries the fix.
3. Leave behind a repeatable way to do this for the rest of the catalogue.

## II. Materials

| Item | Value |
|---|---|
| Guest | Copal aarch64 under UTM on Apple Silicon; Alpine 3.24.1, kernel 6.18.48-0-virt, Hyprland |
| Catalogue | 304 entries present; 240 desktop files; one Flatpak (Brave) |
| Agent access | an unprivileged shell inside the guest with the live Wayland display; no root |
| Instruments | `hyprctl` and `grim` for windows and screenshots, `strace`, `apk`, the Alpine package index at pkgs.alpinelinux.org, Flathub's API, GitHub and GitLab release APIs |
| Helper written | `tools/copal-app-probe.sh` — launch, wait for a window, screenshot, read stderr, close, one summary line |

## III. Method

Each candidate was launched on the live desktop and watched through the
compositor rather than through a human: `hyprctl clients` says which windows
belong to the process tree that was started, `grim` records what was on
screen, and the program's own stderr is kept. Where a program needed a
resource the guest did not have, the resource was traced to its source (a
package, a release tarball, a host setting) before anything was installed.
Where a fix needed root, it was written into `copal-prep.sh` and, when
possible, applied by hand on the bench by the owner and re-checked.

The probe in `tools/copal-app-probe.sh` mechanises the launch step. It marks a
run `ok`, `WIZARD` (a window whose title contains the words wizards use), or
`NO WINDOW`, counts error-like lines on stderr, and appends one line per run
to `~/copal-apps/log.txt`.

## IV. Results

### A. The shared folder was never where copal said it was

`configure_9p_share` checked for any `share` line in fstab before adding its
own, and this guest already had one — `share /share 9p …`, written by the
Alpine image, not by copal — so copal's step reported "already has the share"
and did nothing. `/mnt/share` did not exist and `~/Shared` pointed at it.

The step was rewritten around autofs: a direct map at `/mnt/share` with
9p2000.L options and a 300 s idle timeout, the foreign line commented out,
and the old mount point kept as a symlink. The owner applied it by hand on
the bench with root, and it works: the autofs mount holds `/mnt/share`, the
9p session appears on first access, `/share` resolves to the same place. The
package split matters on Alpine — `autofs` carries the daemon and `autofs-openrc`
the service script — and the kernel module is `autofs4` in the virt kernel.

### B. wxMaxima: not packaged, buildable

Alpine carries Maxima (edge/testing) and gnuplot but no wxMaxima on any
branch or port, checked against the package index and the guest's apk.
Flathub has it for the two 64-bit ports behind a GNOME runtime. The release
tarball is a plain CMake project on wxWidgets, and Alpine's `wxwidgets-dev`
is in community for every port.

Without root, the dev package was fetched with `apk fetch`, unpacked under
the home directory, its `wx-config` re-pointed at that prefix, and its library
symlinks aimed at the real `/usr/lib`. CMake found wxWidgets, noticed by
itself that the webview and qa components were unusable, and built 26.08.0
in 4 min 27 s of wall clock (11 min CPU) on four cores: a 9.4 MB binary, 16 MB
installed with fifty locales. The installer's `build_wxmaxima` does the same
with the real dev package, verifies the release's published SHA-256, and
installs to `/usr/local`.

### C. VICE could not open a sound device — and no package would help

VICE started with `ALSA lib … cannot find card '0'`. The guest had no
`/dev/snd` and no entry in `/proc/asound`. The host *was* offering a card:
PCI 00:03.0, class 0403, vendor 8086 device 2668, the Intel HD Audio
controller that copal's UTM template requests as `intel-hda` — with no driver
bound. Alpine's virt kernel ships one sound driver, `virtio_snd`, whose alias
matches virtio device id 25 and nothing else.

So the fix is host-side: UTM's sound hardware must be `virtio-sound-pci`, a
name confirmed in UTM's own source. The template in `utm/utm-vm.sh` now asks
for it, and stage 10's audio step recognises the situation — a class-0403
device with no driver on a kernel that has only virtio sound — and prints the
UTM instruction. Until the VM is restarted with the new card, `x64sc
-sounddev dummy` starts VICE without one; that was verified.

### D. A queue in front of yt-dlp

`ytq` was written against what copal already knew about Brave's Flatpak
profile path and the keyring problem (`yt-brave`). It watches the clipboard
while its window is focused, checks each URL with a simulated run for an
MP4 at the best available height, downloads one at a time with merged audio,
and on a login, age-gate or bot-check failure opens Brave on the URL and
retries once with Brave's cookies. Verified with a 1 MB public clip: checked
in 1.5 s, downloaded and merged in 1.7 s, and the curses window drew and
quit cleanly under a pseudo-terminal.

### E. The launch sweep

`tools/copal-app-probe.sh` was run over the 109 graphical catalogue entries
outside the Games section, one at a time, plus the programs other stages
install (KiCad, KMail, Brave, VICE). The per-program verdicts and notes are
in `app-integration-plan.md`; the tally on this bench:

| Verdict | Count | What it turned out to mean |
|---|---|---|
| ok | 90 | a window of its own, no first-run dialog |
| WIZARD | 5 | Claws Mail, Firefox, Kate, Audacity, and one false match (feh's window title contained a file name) |
| NO WINDOW | 10 | four re-launch detached or need a file argument (Lapce, Mousepad, VLC, mpv, feh, nsxiv — the probe now catches the detached ones); three GPU terminals that cannot get an EGL screen on this software-GL guest (kitty, WezTerm, Zutty); two Qt Quick programs that crash in the renderer (MuseScore, welle.io); one upstream breakage (Cura imports `imp`, removed in Python 3.12) |
| not probed | 37 | the 32 games, left for a hand pass, and applets or root tools with no window by design |

**Resolved in the installer:** mail accounts for Thunderbird and Claws Mail
seeded from four optional questions in `make answers` (Claws verified here
with a dummy address: opens on the account, no wizard); Firefox's welcome tab
and default-browser nag off through a policies file; qBittorrent's legal
notice accepted and its tray behaviour off; Zim given a default notebook;
Kate's welcome view off; `QT_QUICK_BACKEND=software` exported on virtio-gpu
guests, which makes MuseScore and welle.io start; the i3 bar given a tray for
the applets and for qBittorrent; the mGBA row corrected to the Qt front end;
scrot reclassified as a command-line tool. Each seed is written only where
the file is absent.

**Left alone, on purpose:** Audacity's welcome dialog (its preference could
not be found; its "New Plugins" dialog is a one-time scan), KMail (Akonadi
has no declarative seed), KOReader's quickstart page, Cura's printer wizard,
device dialogs in the SDR programs, and every audio complaint, which waits on
the sound card.

**Claude Code.** `claude doctor` on this guest reported one warning: the
copy copal installed as root into `/usr/local` could not update itself. The
install now goes into a per-user npm prefix (`~/.npm-global`, on PATH from
`/etc/profile.d`), runs `claude doctor` at the end of the step, and the
verify entry reports its result; applied here, the doctor is clean.

**A caveat about the probe.** Two probes must never run at once: the
detached-window fallback attributes any new window to the program under test,
and three verdicts (Krusader, welle.io, FS-UAE) were polluted that way before
the rule was learned.

## V. Discussion

**"Installed" is the package manager's word.** Every finding here came from a
program that apk considered complete. The library package was a release
behind, the templates were in a repository the distribution had never
packaged, the share was present under a different name, the sound card was
present without a driver. A package list would have reported all of these as
fine.

**Look at the source before installing the fix.** wxMaxima could have been
"installed" as a 600 MB Flatpak runtime; five minutes of compilation was the
better answer, and only reading the package index for every branch and port
made that a decision rather than a guess. The sound card could have prompted
a search for an HDA driver package that does not exist for this kernel;
reading `/sys/bus/pci` and the kernel's module tree said in one look that the
answer was on the host.

**Fixes go in the installer, with the reason beside them.** Each function
added carries a comment saying what was observed and why the fix takes the
form it does, because the next person to read "why autofs and not fstab" will
be reading it a year from now with no bench in front of them.

**Limits.** Root was not available to the agent on the bench, so the
system-side halves (`/usr/share/kicad/template`, autofs, wxMaxima into
`/usr/local`) were exercised either in a sandbox under the home directory or
by the owner's hand, and are what the clean-install test must confirm. The
`v` entry in the copal menu prints an "extras" checklist for that test.

## VI. Procedures

**Run the launch probe on one program:**

```sh
tools/copal-app-probe.sh NAME [COMMAND ARGS...]     # closes it afterwards
tools/copal-app-probe.sh --keep NAME                 # leaves it open for you
tail -3 ~/copal-apps/log.txt
```

**Check the extras after a clean install:** copal's menu, entry `v`.

**Ask the guest whether a sound card is drivable:**

```sh
cat /proc/asound/cards
grep -l '^0x0403' /sys/bus/pci/devices/*/class
ls /lib/modules/$(uname -r)/kernel/sound
```

## VII. Files touched

| File | Change |
|---|---|
| `copal-prep.sh` | `configure_9p_share` (autofs), `build_wxmaxima`, `install_ytq`, the audio-card check in stage 10, KMail row, the verify checklist; KiCad work per the other report |
| `utm/utm-vm.sh` | sound card `virtio-sound-pci`; share text |
| `tools/copal-app-probe.sh`, `tools/copal-app-plan.py` | new |
| `docs/app-integration-plan.md` | new, generated from the probe log |
| `docs/copal-handbook.md` | electronics, maths, mail, workshop rows |
