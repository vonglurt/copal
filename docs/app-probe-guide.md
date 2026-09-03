# Launching Programs and Taking Their Pictures with the Tools

<!-- SPDX-License-Identifier: MIT -->
Copyright (c) 2026 paulr@sdf.org. MIT licensed — see `LICENSE`.

---

This is the working method behind `docs/app-integration-plan.md` and
`docs/app-gallery.md`: how a program is started on the live desktop from a
shell, how its window is found, pictured and closed, and how a whole
catalogue is run through that in one sitting. It was written after the
method bit its author once (section 6), so the rules are as important as
the commands.

## 1. The bench

Everything runs on the guest's own Hyprland session, driven from a terminal
in that session. Two workspaces matter:

| Workspace | What lives there |
|---|---|
| the caller's (Paul keeps the session on 5) | the terminal running the shell, Claude Code, `tail -f` |
| 2 (`--workspace`, `COPAL_PROBE_WORKSPACE`) | the program under test, and nothing else |

The probe switches to workspace 2 before launching, moves every window the
program opened there, takes the picture, closes the program and switches
back to where it started. The picture therefore holds the program alone, a
fullscreen game never lands on the terminal, and a typed first action can
only reach the program's window: keystrokes go to the focused surface, and
the focused surface is on workspace 2.

The shell needs the session's environment: `WAYLAND_DISPLAY`,
`HYPRLAND_INSTANCE_SIGNATURE` and `XDG_RUNTIME_DIR`. A terminal opened
inside the session has them; a login on a text console (tty1) does not, and
from there `hyprctl` finds no socket and `grim` no display. Check with:

```sh
echo "$WAYLAND_DISPLAY $HYPRLAND_INSTANCE_SIGNATURE"
hyprctl clients -j | python3 -c 'import json,sys; [print(c["pid"],c["class"],c["workspace"]["id"],c["title"][:40]) for c in json.load(sys.stdin)]'
```

The second line is the window list: pid, class, workspace, title. It is the
thing to look at before closing anything (section 6).

## 2. One program, one picture

```sh
tools/copal-app-probe.sh NAME [COMMAND ARGS...]          # COMMAND defaults to NAME
tools/copal-app-probe.sh --keep NAME                      # leave it open afterwards
tools/copal-app-probe.sh --wait 60 NAME                   # slow starters (Wine, Java)
tools/copal-app-probe.sh --doc docs/img/apps NAME         # half-size PNG for a report
tools/copal-app-probe.sh --gallery docs/img/gallery NAME  # 320x200 JPEG for the gallery
```

What happens, in order:

1. `command -v COMMAND` — if it is not installed the log gets `NOT INSTALLED` and nothing is launched.
2. The window list is snapshotted, the program is started with `setsid` and its output goes to `~/copal-apps/NAME.log`.
3. Up to `--wait` seconds: a window whose pid is the program or one of its descendants is "ours". After 8 seconds a window the compositor did not have before the launch is accepted too (Wine, Flatpak and self-re-launching programs hand the window to another process tree); the verdict then says `detached`.
4. Five seconds for it to draw and for a wizard to follow the main window; every window of ours is moved to the probe workspace.
5. The first action, if `--act` was given (section 3).
6. `grim` takes the full screenshot to `~/copal-apps/NAME.png`; `--doc` and `--gallery` derive their smaller copies from it (`magick -resize 25% -quality 70` for the gallery, about 3–10 KB).
7. Unless `--keep`: `hyprctl dispatch closewindow pid:N` for each of our windows, then `kill`, then `kill -9`, over the descendants. Back to the caller's workspace.
8. One line appended to `~/copal-apps/log.txt`:

```
17:17  firefox-esr        ok 1s (1 window), acted      stderr:0   [Mozilla Firefox;]
16:51  audacity           WIZARD 2s (2 windows)        stderr:0   [Audacity;Welcome to Audacity!;]
16:51  mscore             NO WINDOW in 30s, process no (exit 1) stderr:29  -- ... ERROR ...
```

`ok` means a window came up in that many seconds; `WIZARD` means a title
matched the first-run words (Welcome, Setup, Wizard, Assistant, Getting
Started, Legal Notice); `NO WINDOW` says whether the process was still alive
when the wait ran out. `stderr:N` counts lines that look like errors; the
first such line follows after `--`. Titles are in brackets.

**Look at the picture.** The verdict says a window existed; only the picture
says whether it was the program or a black rectangle. Open
`~/copal-apps/NAME.png` (or the gallery JPEG) in an image viewer, or have
the agent read it. The gallery pictures are small on purpose: a window's
shape and its menu bar survive, fine text does not.

Terminal programs are launched inside a terminal so they get a window:

```sh
tools/copal-app-probe.sh --gallery docs/img/gallery lynx foot -e sh -c 'lynx; sleep 25'
```

The trailing `sleep` keeps the window up if the program exits at once (a
missing argument, a refused terminal), so the picture shows what it printed.

## 3. A first action: typing and drawing

`--act 'CMD'` runs CMD after the program's largest window has been focused,
with that window's place on screen in `COPAL_WIN_X/Y/W/H` and its address in
`COPAL_WIN_ADDR`. Whatever CMD prints joins `~/copal-apps/NAME.log`, and the
verdict gains `acted` or `act failed`.

`tools/copal-act` is a word script for that slot:

| Words | Effect |
|---|---|
| `type 'hello copal'` | type it (wtype, 15 ms per key) |
| `ret` `esc` `tab` | press that key |
| `keys ctrl+l` | press a chord |
| `wait 2` | seconds |
| `click` | click the middle of the window (wlrctl) |
| `line` | drag a stroke across the middle of the window (wlrctl) |
| `xline` | the same stroke with xdotool, for a program run with `GDK_BACKEND=x11` or `SDL_VIDEODRIVER=x11` |

```sh
tools/copal-app-probe.sh --gallery docs/img/gallery --act "tools/copal-act keys ctrl+l wait 0.5 type 'hello copal'" firefox-esr
tools/copal-app-probe.sh --gallery docs/img/gallery --act "tools/copal-act xline" mypaint env GDK_BACKEND=x11 mypaint
tools/copal-app-probe.sh --gallery docs/img/gallery --act "tools/copal-act type i wait 0.3 type 'hello copal' esc" vim foot -e sh -c 'vim; sleep 25'
```

`wtype` and `wlrctl` are not in the Copal package set. Without root they can
be unpacked from their apks into a private tree, which is what the bench
does and what `copal-act` looks for:

```sh
mkdir -p ~/.cache/copal-gallery/apks ~/.cache/copal-gallery/root
cd ~/.cache/copal-gallery/apks && apk fetch wtype wlrctl
for a in *.apk; do tar -xzf "$a" -C ../root 2>/dev/null; done
ls ~/.cache/copal-gallery/root/usr/bin      # wlrctl wtype
```

A Wayland-native GTK or SDL program cannot be dragged across by wlrctl in a
way it recognises as a stroke, hence the X11 backend and `xline` for the
drawing programs.

## 4. The whole catalogue: the sweep

```sh
tools/copal-app-sweeplist.py        # ~/.cache/copal-gallery/gallery-list.txt
setsid nohup tools/copal-app-sweep.sh > ~/.cache/copal-gallery/sweep.log 2>&1 < /dev/null &
tail -f ~/.cache/copal-gallery/sweep.log
```

The list has one tab-separated row per installed catalogue program (`x` and
`t` rows of the catalogue in `copal-prep.sh`) plus the bench extras (KiCad,
KMail, Brave, VICE, the programs built from source, the Wine boxes):
name, command, first-action words. The list builder holds the per-program
command overrides (software Qt Quick for MuseScore and welle.io, the X11
backends, `DOOMWADDIR` for GZDoom) and the actions; edit it, not the list.
The runner takes the rows in order, one probe at a time, with `--wait 60`
for the Wine boxes.

**Detach it.** The `setsid nohup ... &` matters: a sweep is an hour or two,
and started as a plain background job of an interactive shell it dies with
that shell's terminal. Detached, it carries on and the log tells the story.

**Never two probes at once.** The detached-window fallback counts any new
window as the program's; a second probe's window is attributed to the first
and closed. While a sweep runs, run nothing else that opens windows.

Afterwards:

```sh
tools/copal-app-gallery.py          # docs/app-gallery.md from the log and the pictures
tools/copal-app-plan.py             # docs/app-integration-plan.md from the log
git add docs/app-gallery.md docs/img/gallery && git commit
```

A program that already has a line in the log is simply re-probed; the
gallery and the plan take the latest line per name.

## 5. Reporting while it runs

The agent, or anyone watching, reads the sweep log and looks at pictures as
they land. Something worth saying after each picture: the verdict line, and
whether the picture matches it. A picture that disagrees with its verdict
(a window that is a black rectangle, a "window" that is the terminal that
launched it, an act that typed into the wrong place) is the finding; the
verdict alone is not.

```sh
tail -n 4 ~/.cache/copal-gallery/sweep.log
ls -t docs/img/gallery | head -3
```

## 6. What must not be done: closing windows by class

On 2 Sep 2026 a sweep was stopped halfway to fix the runner. Its terminal
programs had left foot windows behind, and the clean-up was:

```sh
hyprctl dispatch closewindow "class:^foot$"     # DO NOT
```

Claude Code was itself running in a foot window. Every foot window closed,
including that one, and the session ended in the middle of its own work.

The rules that follow from it:

- **Close by address or pid, from a list you have just read.** `hyprctl clients -j` gives pid, class, workspace, title and address. Pick the windows that are the program's; check the pid is not the terminal you are typing in; then `hyprctl dispatch closewindow address:0x...`. Never a class or title pattern that could match the session's own terminal.
- **The probe protects its ancestors.** It records the pids above it (shell, terminal, compositor) as `PROTECT`, and a window owned by any of them is never counted as the program's, never "new", never moved, never closed. So a probe started from the session's terminal cannot close that terminal, whatever the program does.
- **Leftovers from an interrupted sweep** are the probe's own children; `pkill -f copal-app-probe` and `pkill -f 'foot -e sh -c'` reach them and nothing else, because the session's terminal was not started with `-e sh -c`.
- **Detach long runs** (section 4) so that if the terminal does go, the work does not.

## 7. Files

| Path | What |
|---|---|
| `tools/copal-app-probe.sh` | launch, find window, act, picture, close, one log line |
| `tools/copal-act` | the first-action word script (wtype, wlrctl, xdotool) |
| `tools/copal-app-sweeplist.py` | writes the sweep list from the catalogue and the bench extras |
| `tools/copal-app-sweep.sh` | runs the list, one probe at a time |
| `tools/copal-app-gallery.py` | `docs/app-gallery.md` |
| `tools/copal-app-plan.py` | `docs/app-integration-plan.md` |
| `~/copal-apps/log.txt` | one line per probe run, appended; the source of both documents |
| `~/copal-apps/NAME.png`, `NAME.log` | the full screenshot and the program's output, latest run |
| `docs/img/gallery/NAME.jpg` | the gallery picture, 320x200 |
| `~/.cache/copal-gallery/` | the sweep list, its log, and the unpacked wtype/wlrctl tree |
