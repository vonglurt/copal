# Porting *Linux Antiquity* to Copal Linux: Vendoring, Transformation, and an Exclusive Wayland Session on Alpine

**Lab report — Copal Linux project**
**Subject:** integration of diinki's *Linux Antiquity* Hyprland theme as Copal's "full monty" install level (stage 16)
**Date:** 2026-08-25
**Upstream:** https://github.com/diinki/linux-antiquity (MIT), snapshot of branch `main` (head at time of vendoring: `c0e3eac`)

---

## Abstract

Copal Linux installs stock Alpine on Raspberry Pi and PC hardware through a
sixteen-stage, re-runnable installer. This report documents the addition of a
second, mutually-exclusive desktop path: Hyprland on Wayland, themed as
diinki's *Linux Antiquity* — an art-nouveau, star-chart aesthetic the author
calls "scientific and celestial antiquity." The upstream theme targets Arch
Linux, bash, systemd, NetworkManager, and a Hyprland new enough to read Lua
configuration; Alpine 3.24 provides none of these. We vendor the upstream
checkout unmodified, stage it onto the boot partition beside the Mini vMac
sources, and perform every Alpine-shaped transformation at install time in
generated files, so the vendored tree remains byte-identical to upstream and
each deviation is legible in one place. Session exclusivity between X11
(stage 4, the "medium" level) and Wayland (stage 16, the "full monty") is
reduced to one word in `/etc/copal/session`, read by a single front door,
`copal-session`. A guided mode presents the install as three levels — server,
medium, full — that are computed subsets of the one automation manifest. We
also survey the packaging gaps (quickshell, hyprpaper, hyprshot are absent
from Alpine entirely), the licence boundary of the vendored material, and the
feature deltas found in nine public forks of the upstream repository.

**Index terms** — Alpine Linux, Hyprland, Wayland, quickshell, theming,
vendoring, git subtree, OpenRC, seatd, POSIX sh.

---

## I. Introduction: derivation of the theme's intent

The theme is not a colour scheme; it is a thesis. From the author's own
narration of the design process [2], distilled:

1. **Reject the obvious aesthetics.** Retro, flat, Aero and liquid-glass are
   all "very obvious" desktop languages — imaginable before they are built.
   The interesting experiment is an aesthetic "so detached from computing
   … that it doesn't become obvious at all how you would even create a user
   interface out of" it.

2. **Choose an inherited, constructed one instead:** old scientific
   illustration and classical depictions of celestial bodies —
   anthropomorphized suns and moons with unsettling faces, armillary
   spheres, star charts, tarot iconography, the four humours. Art nouveau
   with "biblical notes." The author names the mix *scientific and celestial
   antiquity*.

3. **Make the desktop a painting you can interact with.** The structural
   consequences, each visible in the vendored configs:
   - *Radial menus as orbits* — workspaces are planets on a curve; the
     active one grows solar flares; buttons are celestial bodies. Implemented
     as bespoke QML curve primitives (nothing radial exists in Qt Quick by
     default) under `configs/quickshell/taskbar/`.
   - *The power menu as tarot cards* — power-off, reboot, hibernate as
     Helios/Selene, Nyx, Hypnos (`sidebarPopups/PowerMenu.qml`).
   - *Weather in the humoral system* — current conditions mapped to element
     and humour (phlegm for cold-and-wet, yellow bile for hot-and-dry) with
     a drawn celestial face, fed by the OpenWeatherMap API
     (`widgets/`, configured in the settings window).
   - *Layered art passes* — the menus' backgrounds carry a star-chart /
     armillary-sphere vector drawing; sliders, radio buttons and cursors are
     redrawn so no element is "boring in default."
   - *Aliveness* — the bodies rotate subtly; "they have faces, so it would
     be weird if they were static."

4. **Usability is non-negotiable.** Menus close on outside-click, the
   launcher is searchable, favourites and per-monitor widgets are
   customizable in a settings window — all reimplemented from scratch in
   QML because a from-scratch shell inherits nothing.

Copal's interest in this theme is the same as its interest in Alpine: an
opinionated distillation, executed simply. Upstream's installer is ~100
lines of bash that copies four config directories into `~/.config` and backs
up whatever was there [1]. That simplicity is preserved deliberately
(§V-B); everything Alpine-specific is layered around it, not into it.

---

## II. Constraints: what Alpine 3.24 actually provides

Copal pins `ALPINE_VER=3.24.1` (`copal-prep.sh`). The theme's dependency
list (upstream README) was measured against pkgs.alpinelinux.org for
`aarch64`; the result dictates the whole shape of the port.

**Table I — packaging survey (Alpine v3.24, aarch64, measured 2026-08-25)**

| Upstream dependency | Alpine v3.24 | Consequence for the port |
|---|---|---|
| Hyprland > 0.55 (Lua config) | `hyprland` **0.54.3-r0** (community) | present, but **predates Lua configs** → the shipped `hyprland.lua` is never read; a `.conf` translation is generated (§V-C) |
| Quickshell > 0.3.0 | **not packaged** (absent from edge, too) | the radial shell, widgets and launcher cannot be apk-installed; configs installed anyway, launcher falls back to wofi (§V-D) |
| hyprpaper | **not packaged** | `swaybg` (packaged) paints the wallpaper, behind `copal-wallpaper` |
| hyprshot | **not packaged** | `grim` + `slurp` (packaged) behind `copal-shot` |
| kitty | 0.47.0-r0 | used as vendored; font substitution only (§V-E) |
| mako | 1.11.0-r0 | used as vendored, byte-identical |
| nemo | 6.6.4-r0 | used; `pcmanfm` substituted when absent |
| hyprpolkitagent | 0.1.3-r2 | present; upstream starts it via `systemctl --user`, which does not exist here → exec'd directly |
| nm-applet | n/a to Copal | Copal configures wifi with `wpa_supplicant` (stage 10), not NetworkManager → dropped |
| jq, socat | packaged | installed (quickshell IPC helper path) |
| xdg-desktop-portal-hyprland | not in v3.24 (edge/testing only) | omitted for now |
| labwc (fork target, §VII) | 0.20.0-r0 | a packaged wlroots compositor — a viable fallback path surfaced by the labWC fork |

Also absent as assumptions rather than packages: **systemd** (Alpine is
OpenRC; seat management is `seatd`), **bash as /bin/sh** (Copal's target-side
installer runs under busybox ash, so every generated script is POSIX sh),
and **elogind** (so `XDG_RUNTIME_DIR` must be provided by hand — §IV-C).

---

## III. Method of installation of Hyprland on Alpine

For reference, the complete chain stage 16 performs, in order. This is the
"method of installation" in the OpenRC world, and each item exists because
its absence has a specific failure:

1. `apk add hyprland kitty mako` — the spine; hard failure stops the stage.
2. **Seat**: `apk add seatd`; `rc-update add seatd default`;
   `rc-service seatd start`; user added to `seat`, `input`, `video` groups.
   Without seatd the compositor cannot open `/dev/dri/card0` or the input
   devices (logind's job elsewhere).
3. **Bus**: `apk add dbus`, enabled and started. mako, the polkit agent and
   portals rendezvous over the session bus.
4. **GPU userspace**: Mesa *drivers* are dlopen'd, not linked, so apk's
   shared-object resolver never pulls them; `mesa-dri-gallium`, `mesa-egl`,
   `mesa-gles`, `mesa-gbm` are added explicitly (each optional — the set of
   valid names shifts across Alpine releases).
5. **Xwayland**, so every X11 program stage 4/12 installed keeps running
   inside the compositor.
6. **Session start** (no display manager): tty1 autologin (busybox getty
   `-n -l`) → `~/.profile` autostart block → `copal-session` →
   `XDG_RUNTIME_DIR` created as `/tmp/xdg-runtime-$(id -u)` (0700, ownership
   asserted) → `dbus-run-session Hyprland`. Root is refused, mirroring
   `copal-startx`.

---

## IV. Design

### A. Exclusivity as one word

X and a Wayland compositor cannot own the same seat simultaneously — but
their *packages* coexist trivially. So exclusivity is enforced at the
session, not by uninstalling: `/etc/copal/session` contains `x11` or
`wayland`; `copal-session` (installed identically by both desktop stages)
reads it and execs `startx` or `dbus-run-session Hyprland`. Stage 4 writes
`x11`, stage 16 writes `wayland`; the last stage run owns the console —
the only rule a person can predict — and editing the one-word file flips it
back with nothing reinstalled. The `~/.profile` autostart block now execs
`copal-session` (previously `startx` directly) and additionally guards on
`WAYLAND_DISPLAY`.

### B. Install levels (guided mode)

The sixteen-stage menu gained a front door: on a virgin system (no apkovl
yet) with a person at the terminal, `guided_install` describes the flow as
three acts (settle → furnish → harden) and offers three levels:

| Level | Definition (computed, not listed) |
|---|---|
| **server** | manifest minus stages 4, 16, 7, 9, 10, 12, 14 → `1 2 3 8 5 6 13` |
| **medium** | manifest minus 16 — the historical full install; the Pi Zero ceiling; X11/i3 |
| **full monty** | the whole manifest, 16 included — Hyprland + Antiquity takes the session |

Levels are *subsets of the single automation manifest* (`seq_for_profile`
next to `auto_seq_from_manifest`), so a future stage lands in the right
levels without a second list to maintain. The choice is recorded on the FAT
boot partition (`$BOOT/copal-profile`) because that file must survive the
stage 3 reboot that destroys the tmpfs root; `auto_run` re-derives its
sequence from it on every resume. Declining records `custom`, making the
offer one-shot. On armhf/armv7 the full level degrades to medium *by stage
16 declining itself* (with the reason printed), not by a second copy of the
hardware table.

### C. Config-loading chains (how each component finds its values)

Documented here because three of the port's decisions hang on them:

- **Hyprland** reads `~/.config/hypr/hyprland.conf`. Lua configuration
  (`hyprland.lua`) is a ≥ 0.55 feature; 0.54.3 ignores the `.lua` entirely.
  Both files are therefore installed without conflict: the generated
  `.conf` is authoritative today, and the vendored `.lua` (with the
  author's monitor layout) becomes usable the day Alpine's Hyprland can
  read it — at which point deleting our `.conf` restores upstream behaviour.
- **kitty** reads `~/.config/kitty/kitty.conf`; the theme's five palettes
  (`eris|eros|hades|helios|priapus.conf`) are pulled in by an `include`
  line inside a `BEGIN_KITTY_THEME` block — switching palette is editing
  one `include`. Unknown font families fall back to the default monospace,
  which is why the Maple Mono substitution (§V-E) is cosmetic, not
  load-bearing.
- **mako** reads `~/.config/mako/config` (INI with `[urgency=…]` sections);
  colours are hex-with-alpha and match the *helios* palette; needs only a
  session bus to exist.
- **quickshell** loads `~/.config/quickshell/shell.qml` as the root of a
  QML scene; `//@ pragma` lines at its head set the icon theme and
  environment (`QS_ICON_THEME=buuf-nestort` — see §VI on why that icon set
  is not shipped); bundled fonts load via `FontLoader` from the config tree
  itself, so no system font install is required for the shell's own type.
- **hyprpaper** reads `~/.config/hypr/hyprpaper.conf`; an empty
  `monitor =` field means "every monitor," which is the only portable value
  and is what the generated rewrite uses (upstream pinned `DP-2`/`DP-4`).

### D. Where everything lives (trace of code)

All target-side code is generated by `copal-prep.sh` into `copal-init.sh`
(the quoted `COPALINIT` heredoc). Line numbers drift; anchors are names:

| Artifact | Location | Role |
|---|---|---|
| vendored theme | `vendor/linux-antiquity-main/` (later: `vendor/linux-antiquity/` subtree, §VIII) | upstream, unmodified |
| staging | `copal-prep.sh`, "Linux Antiquity, staged" block (beside Mini vMac staging) | tars `configs/` + LICENSE + README to `$MNT/antiquity/linux-antiquity.tar.gz`; excludes `iconTheme/`, `screenshots/` |
| `stage_hyprland` | `copal-init.sh`, between `stage_gui` and `stage_zram` | packages, seat/bus, theme unpack (card first, GitHub fallback), transformations, session claim |
| `copal-session` | written by `configure_desktop_autostart` (both desktop stages) | the one front door; reads `/etc/copal/session` |
| `copal-launcher` | written by stage 16 | Super+D: quickshell IPC → wofi → dmenu |
| `copal-shot` | written by stage 16 | Super+Shift+S: hyprshot → grim+slurp |
| `copal-wallpaper` | written by stage 16 | hyprpaper → swaybg, upstream's image |
| generated `hyprland.conf` | `ANTIQHYPR` heredoc in stage 16 | the Lua translation (§V-C) |
| levels | `seq_for_profile`, `guided_install`, `$BOOT/copal-profile` | guided mode; auto sequence per level |
| manifest row | `auto_manifest`: `16\|Desktop\|Hyprland and the Antiquity theme\|10` | TUI name + inclusion in `a` runs |
| menu | entries `16` and `g` in the main loop | manual entry points |

---

## V. Transformations

The rule: **the vendored tree is never edited.** Every deviation is a
generated file or a `sed` against the *installed copy*, so `diff -r` between
`vendor/` and upstream stays empty and this section is the complete list.

### A. Install-time acquisition
Card first (`$BOOT/antiquity/linux-antiquity.tar.gz`, staged by
`copal-prep.sh`), GitHub tarball as fallback — the Mini vMac rule: an
unattended install must not depend on a web server being up at hour three
for something the card already carries.

### B. The copy itself (upstream semantics, POSIX re-expression)
Upstream `install.sh` is bash; the target shell is busybox ash. The loop is
reimplemented in POSIX sh with identical semantics: each of
`configs/{hypr,kitty,mako,quickshell}` is copied whole to `~/.config/<name>`;
a pre-existing directory is **moved aside** to `~/copal-theme-backups/<name>`
(timestamp-suffixed on collision), never merged, never deleted. Installed
into both `/root` and the admin home, matching `install_home_file`'s
long-standing behaviour. Dependency checking moved from upstream's
`command -v` loop into the stage's package section, where apk is the ground
truth. The MIT licence text is installed beside the configs as
`~/.config/hypr/LICENSE.linux-antiquity`.

### C. `hyprland.lua` → `hyprland.conf` (the translation)

**Table II — mapping.** Everything not listed is carried over
value-for-value (gaps 4/8, border 1 px `rgb(1c1c1c)`, rounding 9 power 4,
blur 3×2 with noise 0.023 / contrast 0.9, shadow range 12 power 6
`rgba(0,0,0,0.19)`, bezier (0.22, 1, 0.36, 1) "smooth", workspace slide,
dwindle + `preserve_split`, `new_status = master`, hyprland logo/default
wallpaper disabled, all ten workspace binds — unrolled, since the `.conf`
dialect has no loops — mouse drag/resize binds, media-key binds verbatim).

| Upstream (`hyprland.lua`) | Generated (`hyprland.conf`) | Reason |
|---|---|---|
| `hl.monitor({DP-2 …}); hl.monitor({DP-4 …})` | `monitor = , preferred, auto, 1` | author's desk vs. everyone's hardware; `hyprctl monitors all` tells you what to pin |
| `kb_layout = "us,se"` + alt-shift toggle | `us` | a surprise layout toggle on a one-keyboard machine is a trap |
| `hl.exec_cmd("nm-applet")` | *(dropped)* | no NetworkManager on Copal (stage 10 / wpa_supplicant) |
| `systemctl --user start hyprpolkitagent` | `exec-once = sh -c '[ -x /usr/libexec/hyprpolkitagent ] && exec …'` | no systemd; exec'd directly, guarded |
| `hl.exec_cmd("hyprpaper")` | `exec-once = copal-wallpaper` | hyprpaper unpackaged; wrapper prefers it if it ever appears |
| `hl.exec_cmd("qs")` | `exec-once = sh -c 'command -v qs … && exec qs'` | quickshell unpackaged; guarded so the line is inert until it exists |
| `hyprctl setcursor Hackneyed-24px 24` | *(dropped)* | cursor theme not part of the repo (upstream leaves it external) |
| launcher = `quickshell ipc call appLauncher_$(hyprctl … jq …)` | `bind = $mainMod, D, exec, copal-launcher` | wrapper: quickshell IPC → wofi → dmenu |
| `hyprshot --mode region` | `bind = … copal-shot` | wrapper: hyprshot → grim+slurp |
| *(none)* | `copal-halt` binds (Super+Shift+P, XF86PowerOff, Super+Shift+Del), Super+Shift+E exit, Ctrl+Alt fallbacks for UTM-stolen keys | Copal conventions carried over from the i3 config so both desktops share one habit set |
| layer rules (Lua) | `layerrule = blur/ignorealpha 0.19` for `diinki_celestialantiquity:{bars,no_blur}` | same values, `.conf` spelling |

### D. Quickshell (the honest gap)
Not packaged anywhere in Alpine (v3.24 or edge). The configs are installed
regardless and every integration point already prefers it (`copal-launcher`,
the guarded `exec-once`), so the theme *completes itself* the moment a `qs`
binary appears — via a future package or a source build (Qt6 ≥ 6.6, CMake,
QtQuick private headers; realistic on a Pi 5/PC with stage 7's toolchain,
not on 512 MB). Until then: Antiquity's windows, terminal, notifications
and wallpaper, wofi launching.

### E. Fonts
`kitty.conf` asks for Maple Mono (unpackaged). If `font-jetbrains-mono`
installed, the installed copy (not the vendored one) is sed'd to it;
otherwise kitty's monospace fallback applies. The quickshell tree bundles
its own display faces (Boska, Charcoal, Monaco, Material Symbols) loaded via
`FontLoader`, so the shell needs no system fonts.

### F. `hyprpaper.conf`
Regenerated with an empty (= all) monitor field and upstream's
`georges_riom_collage.png`; only ever read if hyprpaper appears (§V-A note —
swaybg takes the image path from `copal-wallpaper` directly).

---

## VI. Licence and provenance

- Upstream is **MIT** (© 2026 diinki); vendoring, modification and
  redistribution with the notice are all granted. The notice travels: in the
  repo (`vendor/…/LICENSE`), on the card (in the staged tarball), and on the
  installed system (`~/.config/hypr/LICENSE.linux-antiquity`).
- **`iconTheme/buuf-nestort` is excluded** from the repository, the card and
  the install. It is a derivative of the Buuf icon set (Mattahan / Paul
  Davey), which is licensed **CC BY-NC-SA** — a repository-level MIT grant
  cannot relicense third-party icons. The quickshell configs reference the
  theme by pragma; without it, icon lookups fall back to hicolor/adwaita
  (already installed by stage 4). Anyone wanting the intended icons can
  place them in `~/.local/share/icons` themselves, as upstream's README also
  instructs.
- `screenshots/` (12 MB) is excluded as web-page documentation.
- Credit: theme, artwork, QML shell and the aesthetic thesis are diinki's
  [1][2]. The Alpine port, translations and wrappers are Copal's (MIT, same
  as the rest of the repository).

---

## VII. Survey of public forks (feature deltas vs. upstream `main`)

Measured with the GitHub compare API, 2026-08-25. Most of the twenty forks
are unmodified; the divergent ones:

**Table III — divergent forks**

| Fork | Δ | What it adds | Relevance to Copal |
|---|---|---|---|
| `The-Graze/linux-antiquity-labWC` | +2 | ports the theme to **labwc** (`rc.xml`, `autostart`, `environment`) | **high** — labwc 0.20.0 *is* packaged in Alpine v3.24; a proven fallback compositor path if Hyprland regresses on small boards |
| `maybe-maeb/maeby-antiquity` | +5/−5 | **"Orbit Update"**: `OrbitSystem.qml` (486 lines) + `Planet.qml` — a full orbital taskbar extension; large `Config.qml` growth; drops `install.sh` | the most substantial *feature* fork of the quickshell layer; worth watching for ideas once quickshell is installable |
| `delminator/linux-antiquity-fedora` | +1/−5 | Fedora port: **isolated session** (`sessions/antiquity.desktop` + `antiquity-session` launcher), FR keyboard, Météo-France weather provider, GTK 3/4 settings overlay, `install-fedora.sh` | validates our method — it also keeps upstream intact and layers an overlay + its own installer; its display-manager session file is the pattern to copy if Copal ever adds a DM |
| `Another-Ashl3y/linux-antiquity` | +2/−5 | swaps kitty → **alacritty** (`alacritty.toml`), restructures hypr configs, rewrites install.sh | shows the terminal is swappable; alacritty is packaged in Alpine if kitty's GL needs ever bite |
| `BlupBlurp/linux-antiquity-plasma-widget` | +1 | ports the **humoral weather widget to KDE Plasma** | evidence the widget concept stands alone |
| `davimf721/linux-antiquity` | 0 | its improvements were merged upstream as PR #4 (already in our snapshot) | — |

Conclusion drawn from the survey: every serious fork keeps upstream's
`configs/` layout and varies the *delivery* (compositor, distro, session
wrapper). Stage 16 follows the same grain, which should keep future
`subtree pull`s from upstream low-conflict.

---

## VIII. Forking and vendoring: controlling both sides

The current state is a plain unzipped snapshot (`vendor/linux-antiquity-main`,
no git history). The intended end state is **a GitHub fork we own, vendored
as a git subtree**, giving one place to change the theme and two directions
of flow (pull upstream in, push our changes out — even as PRs back to
diinki). Submodules were rejected: `copal-prep.sh` must tar the vendor tree
onto every card, and a submodule that someone forgot to `--init` would
silently produce theme-less cards; a subtree is always materialized.

Procedure (one-time, run when ready — creating the public fork is the
user's action):

```sh
# 1. Fork on GitHub (creates github.com/<you>/linux-antiquity):
gh repo fork diinki/linux-antiquity --clone=false

# 2. In the fork, create the Copal branch and delete the non-MIT icon set
#    there (licence-clean at the source, not by .gitignore):
git clone git@github.com:<you>/linux-antiquity.git /tmp/la
cd /tmp/la && git switch -c copal-alpine
git rm -r iconTheme screenshots
git commit -m "copal-alpine: drop non-MIT iconTheme and web screenshots"
git push -u origin copal-alpine

# 3. In copal-alpine-linux, replace the snapshot with the subtree:
git rm -r vendor/linux-antiquity-main   # (and the .zip, already ignored)
git subtree add --prefix vendor/linux-antiquity \
    git@github.com:<you>/linux-antiquity.git copal-alpine --squash

# Day-to-day:
#   pull upstream:  in the fork, merge diinki/main into copal-alpine, push;
#                   then here: git subtree pull --prefix vendor/linux-antiquity … copal-alpine --squash
#   push our edits: git subtree push --prefix vendor/linux-antiquity … copal-alpine
```

`copal-prep.sh` already looks for `vendor/linux-antiquity` first and
`vendor/linux-antiquity-main` second, so the migration needs no script edit.
Once the fork exists, transformations that have proven stable (the
`.conf` translation, the hyprpaper rewrite) can *graduate* from
generated-at-install-time into committed files on the `copal-alpine` branch
— the Fedora fork's overlay layout (Table III) is the model — shrinking
stage 16 to acquisition + packages + session.

---

## IX. Limitations and future work

- **Untested on target.** This work is code-and-survey complete but has not
  yet booted: the next `make`/`copal-prep.sh` run with `MODEL=vm` is the
  first real test (Hyprland under UTM runs on llvmpipe; `dmesg | grep drm`
  is the first thing to read on a black screen).
- **Quickshell** remains the visible gap (§V-D). Options in preference
  order: an Alpine package appearing; a pinned source build behind stage 7's
  toolchain; or the labWC fork's path with a simpler bar.
- **Audio keys** bind `wpctl` (WirePlumber), which stage 10's audio work
  does not currently install; the keys are inert until it does.
- **xdg-desktop-portal-hyprland** (screenshare/file dialogs for sandboxed
  apps) exists only in edge/testing; revisit at the next Alpine bump.
- **Wallpaper redundancy**: the theme's three bundled wallpapers ride both
  the repo and every card (~23 MB); if repo weight ever matters, the fork
  branch can thin them the way it thinned iconTheme.

---

## References

[1] diinki, *linux-antiquity* (source repository, install script, README),
    https://github.com/diinki/linux-antiquity — MIT licence, © 2026 diinki.
[2] diinki, *"Linux Antiquity"* (design narration / video transcript),
    https://www.youtube.com/watch?v=qOoWQeIGKiA — the aesthetic derivation
    in §I paraphrases and quotes this source.
[3] Alpine Linux package database, https://pkgs.alpinelinux.org — survey of
    Table I, branch v3.24 and edge, arch aarch64, 2026-08-25.
[4] Hyprland wiki — configuration file discovery, Lua configuration
    (≥ 0.55), monitor syntax, https://wiki.hypr.land.
[5] diinki, *wallpapers* (companion repository),
    https://github.com/diinki/wallpapers.
[6] Fork survey via GitHub compare API (`repos/diinki/linux-antiquity/
    compare/main...<owner>:<repo>:<branch>`), 2026-08-25: The-Graze/
    linux-antiquity-labWC, maybe-maeb/maeby-antiquity, delminator/
    linux-antiquity-fedora, Another-Ashl3y/linux-antiquity,
    BlupBlurp/linux-antiquity-plasma-widget, davimf721/linux-antiquity.
[7] Mattahan (Paul Davey), *Buuf* icon set — CC BY-NC-SA; basis of the
    excluded `iconTheme/buuf-nestort`.
