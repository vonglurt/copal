#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 paulr@sdf.org -- part of Copal Linux.
#
# copal-app-plan.py -- write docs/app-integration-plan.md from the catalogue
# and the launch-probe log.
#
#   tools/copal-app-plan.py                 reads ~/copal-apps/log.txt
#   tools/copal-app-plan.py --log FILE      a log from another machine
#
# The plan is a table: every graphical entry in the catalogue, the command
# that starts it, the latest probe verdict for it, and a note. The verdicts
# come from copal-app-probe.sh's one-line summaries; the notes are the NOTES
# dictionary below, kept here so the document can be regenerated after every
# pass without losing what was learned. Run it, read the diff, commit both.
import os, re, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.expanduser("~/copal-apps/log.txt")
if "--log" in sys.argv:
    LOG = sys.argv[sys.argv.index("--log") + 1]

# What was learned per program, by the binary the catalogue names. A note is
# the configuration step that spares the wizard or the error, or the reason
# to leave it alone. Add to it as the passes go on.
NOTES = {
    "endless-sky": "not packaged; built from source by stage 12's offer (LTO off, tests off). Title screen rendered here. Run from outside its source tree it aborts with 'Unable to find the resource directories': the launcher must pass --resources SRCDIR or run inside it",
    "winebox": "Wine in bubblewrap boxes, stage 14 bundle w. Verified on this aarch64 bench with Notepad++'s ARM64 portable build; x86 programs need the x86_64 port",
    "streamripper": "not packaged; built from source by stage 12's offer (four musl/GCC 15 fixes). Command-line; prints its usage",
    "gzdoom": "opened a 'Fatal error' box: no game data. RESOLVED: the row installs freedoom with it; verified with DOOMWADDIR pointed at Freedoom's WADs -- GZDoom starts into the game",
    "chocolate-doom": "same: needs an IWAD. RESOLVED: freedoom in the row; verified -- 'Freedoom: Phase 1 - Chocolate Doom'",
    "openmw-launcher": "the row named the engine binary, which exits without game data. RESOLVED: the row now starts openmw-launcher, whose 'First run' wizard asks for the Morrowind data -- expected, nothing to seed",
    "lbreakout2": "exit 133 after 'lbreakout2.conf: file not found', EGL cannot create a screen; SDL_VIDEODRIVER=wayland makes no difference. A software-GL guest casualty; retest on hardware",
    "pingus": "SIGSEGV after SDL_Mixer fails to open ALSA; the EGL failure is there too. Retest after the sound card fix, then on hardware",
    "supertux2": "starts; ALSA 'cannot find card' -- the sound card question",
    "freeciv-sdl2": "starts; ALSA 'cannot find card' -- the sound card question",
    "krusader": "an 'Information' box on the very first start only; the second start went straight to the panes. Its one-time notice about optional helper tools -- leave",
    "xboard": "exit 2, 'Unable to create font set': Xwayland's font path is built-ins only. RESOLVED on the antiquity-desktop branch (stage 16): an exec-once adds the misc/75dpi/100dpi directories; verified by hand with xset +fp",
    "xfig": "starts; its 'Cannot convert string -misc-fixed-*' warning is the same Xwayland font path, gone with the same fix",
    "welle-io": "SIGSEGV on start: the Qt Quick renderer on llvmpipe, same as MuseScore. RESOLVED by the same QT_QUICK_BACKEND=software (verified: opens its window). Needs an RTL-SDR to receive anything",
    "kitty": "exits 1: needs OpenGL 3.3 through EGL and this guest's llvmpipe/virtio-gpu EGL path fails to create a screen. A software-GL guest problem; fine on hardware. foot is the terminal here",
    "wezterm": "no window in 45 s, process alive, EGL cannot create a screen: a GPU terminal on a software-GL guest. Fine on hardware; foot is the terminal here",
    "zutty": "SIGSEGV: wants DRI3 under Xwayland and this guest has none. A software-GL guest problem",
    "guake": "process stays alive with no window: it is a drop-down terminal, hidden until its hotkey. Expected. Logs a GSettings schema warning",
    "scrot": "a command-line screenshot tool that was catalogued as graphical; mode corrected to 'h'",
    "minuet": "SIGSEGV on start. With the virtio sound card present it dies later, in the Qt Quick renderer. RESOLVED by QT_QUICK_BACKEND=software (verified 2 Sep: opens its window; ALSA still grumbles about cards.pcm.front etc., harmless)",
    "yakuake": "SIGSEGV on start (exit 139). A KDE drop-down terminal that expects KWin/X11 window management; under Hyprland it does not survive. Leave, or drop from the Wayland desktop's menu",
    "mgba-qt": "the catalogue installed 'mgba', which is the SDL binary and needs a ROM on its command line -- a GUI entry with no GUI. RESOLVED: the row now installs mgba-qt, the Qt front end",
    "fs-uae": "the sweep's window was closed by a concurrent test; re-probe by hand. Needs a Kickstart ROM to do anything, which is its own first-run dialog",
    "gitk": "probed from a home directory that is not a repository; 'not a git repository' is the expected answer. Run it inside a checkout",
    "gqrx": "opens an 'Audio Error' (PulseAudio connection refused) before its device dialog: the same missing sound server as Hydrogen, same fix (stage 10 PipeWire)",
    "kate": "opened its Welcome view. RESOLVED: 'Show welcome view for new window=false' in the katerc stage 7 writes, and seeded by stage 12 where stage 7 did not run; verified",
    "zim": "first window is 'Add Notebook'. RESOLVED: stage 12 seeds ~/Notebooks/Notes as the default notebook; verified -- opens on 'Home - Notes'",
    "qbittorrent": "first start shows a Legal Notice, then minimises to the tray. RESOLVED: stage 12 seeds the notice as accepted and turns off close/minimise-to-tray; the i3 bar now has a tray (tray_output primary) for the applets that need one",
    "mousepad": "the first probe saw no window because Mousepad is D-Bus single-instance and the window belongs to another pid; the probe now catches that. Fine",
    "vlc": "detaches; starts fine. PulseAudio connection error is the missing audio stack, not VLC",
    "mpv": "needs a file or --force-window=yes --idle=yes; not a first-run problem",
    "feh": "needs an image argument; exit 1 without one is its usage error",
    "nsxiv": "needs an image argument; same",
    "cura": "BROKEN upstream: ModuleNotFoundError 'imp' -- Cura 5 on Alpine's Python 3.14 (imp was removed in 3.12). Report to Alpine's cura@testing; nothing to seed",
    "koreader": "opens its Quickstart Guide on first run; that is its intended first page",
    "xfburn": "'No drives were found' -- the VM has no optical drive; expected",
    "umbrello6": "a warning about a missing help index; harmless",
    "kdevelop": "cannot load the kdevperforce plugin; harmless",
    "kicad": "done — templates, sheets, demos, plugins seeded by stage 14 (kicad-lab-report.md)",
    "claws-mail": "opened its Setup Wizard. RESOLVED: stage 12 seeds accountrc + folderlist.xml from the mail answers; verified here with a dummy address -- opens on the account, no wizard. The /usr/etc/skel warning is the Alpine build's path, harmless",
    "thunderbird": "not on this bench. Stage 12 seeds profiles.ini + user.js from the mail answers (recipe below); verify on the clean install",
    "audacity": "two first-run dialogs. 'New Plugins' is the first scan and does not return. 'Welcome to Audacity!' ignores /GUI/ShowSplashScreen (tested) and its own key is not in the binaries -- left as is",
    "firefox-esr": "first run opens 'Welcome to Firefox'. RESOLVED in stage 12: policies.json in the distribution directory (root; verify on the clean install)",
    "mscore": "SIGSEGV on start in the QML renderer under llvmpipe. RESOLVED: stage 1 exports QT_QUICK_BACKEND=software on virtio-gpu guests; with it MuseScore starts (its 'Getting started' tour is the expected first run)",
    "lapce": "re-launches itself detached ('lapce --wait') and exits 0, so the first probe saw no window; the probe now catches detached windows. Starts fine",
    "milkytracker": "aborts (SIGABRT) when the ALSA sequencer is absent: /dev/snd/seq needs the snd-seq module loaded (root: modprobe snd-seq, and /etc/modules -- stage 10 now does both). Opened fine before the sound card arrived, because RtMidi then had no card to try",
    "mc": "its default skin paints the panels in palette blue with cyan text, which on the light Copal Sand terminal is a dark island. RESOLVED: stage 12 seeds ~/.config/mc/ini with skin=sand256, the skin mc ships for exactly this ground (verified: sand panels, coffee text)",
    "hangman": "prints 'unable to open dictionary file /usr/share/dict/words' and quits: no word list on the guest. RESOLVED in the catalogue: the Hangman row now pulls words-en, and stage 12 links /usr/share/dict/words to american-english (Alpine's words-en does not make that link). Same file feeds look(1) and the other word games",
    "hydrogen": "starts, but cannot open an audio driver. With the virtio-snd card present it tries JACK, then PulseAudio, and both are refused: no sound server runs on the guest -- wireplumber is installed but pipewire, pipewire-pulse and pipewire-alsa are not, and nothing starts one. RESOLVED in the installer: stage 10 now installs PipeWire (pipewire, wireplumber, pipewire-pulse, pipewire-alsa, pipewire-jack) and copal-audio-start brings it up with the session; awaits the install here",
    "tuxpaint": "starts; ALSA 'cannot find card' -- the sound card question",
    "kmail": "already configured here (Akonadi resources present); a fresh account needs the KDE wizard or kmail-account-wizard's ISPDB lookup — hard to seed, leave the wizard",
    "brave": "Flatpak; first run shows the welcome tour; same policies.json mechanism inside the Flatpak's /etc/brave/policies path (to verify)",
    "x64sc": "needs a sound card the kernel can drive: UTM Sound = virtio-sound-pci; until then -sounddev dummy",
    "vsid": "same sound requirement as x64sc",
    "cura": "first run is a printer-setup wizard; copal's slice-ender3 covers the headless path, the GUI wizard is expected",
    "FreeCAD": "heavy; first launch builds its addon cache and may exceed the probe's wait — rerun with --wait 60",
    "gparted": "needs root (pkexec); launch as root or with doas, not from the probe",
    "nm-applet": "a tray applet, no window by design",
    "blueman-applet": "a tray applet, no window by design",
    "xscreensaver": "a daemon; the probe would only see its settings dialog",
    "koreader": "runs fullscreen in its own SDL window",
    "gqrx": "asks for an SDR device on first launch; without hardware it shows a device dialog, which is correct",
    "gnuradio-companion": "slow first start (Python block cache); rerun with --wait 60",
    "wireshark": "capture needs the user in the wireshark group or dumpcap setuid; the window itself is fine",
    "simple-scan": "no scanner on the bench; the empty window is correct",
    "qsstv": "first run asks for a sound device; depends on the sound card fix",
    "pavucontrol": "PulseAudio/PipeWire mixer on a machine with neither; shows a connection error — the audio stack question, not this program",
}


def catalogue():
    rows = []
    with open(os.path.join(ROOT, "copal-prep.sh")) as f:
        for line in f:
            p = line.rstrip("\n").split("|")
            if len(p) == 6 and re.match(r"^[A-Z][a-z]+$", p[0]) and p[4] in ("x", "t", "h"):
                rows.append(dict(section=p[0], label=p[1], pkgs=p[2], bin=p[3], mode=p[4], gate=p[5]))
    return rows


def verdicts():
    v = {}
    try:
        with open(LOG) as f:
            for line in f:
                m = re.match(r"^(\d\d:\d\d)\s+(\S+)\s+(.*)$", line.rstrip("\n"))
                if m and not line.startswith("==="):
                    v[m.group(2)] = m.group(3).strip()
    except OSError:
        pass
    return v


RECIPES = r"""
## Recipes for launching into the program, not the wizard

These are the seeds a `configure_<program>` step in `copal-prep.sh` would
write, only when the file is absent, into each account's home the way
`install_home_file` does. Each is marked with what has and has not been
verified.

### Thunderbird — an IMAP account without the account wizard (seeded by stage 12; verify on the clean install)

Thunderbird reads `~/.thunderbird/profiles.ini` and, inside the profile,
`user.js`, which it copies into `prefs.js` on every start. Accounts are
nothing more than prefs, so a complete account can be declared before the
first launch:

```
# ~/.thunderbird/profiles.ini
[General]
StartWithLastProfile=1
[Profile0]
Name=default
IsRelative=1
Path=copal.default
Default=1
```

```js
// ~/.thunderbird/copal.default/user.js
user_pref("mail.accountmanager.accounts", "account1,account2");
user_pref("mail.accountmanager.defaultaccount", "account1");
user_pref("mail.accountmanager.localfoldersserver", "server2");
user_pref("mail.account.account1.identities", "id1");
user_pref("mail.account.account1.server", "server1");
user_pref("mail.account.account2.server", "server2");
user_pref("mail.server.server1.type", "imap");
user_pref("mail.server.server1.hostname", "imap.example.org");
user_pref("mail.server.server1.port", 993);
user_pref("mail.server.server1.socketType", 3);      // 3 = SSL/TLS, 2 = STARTTLS
user_pref("mail.server.server1.authMethod", 3);      // 3 = password, 10 = OAuth2
user_pref("mail.server.server1.userName", "paul@example.org");
user_pref("mail.server.server1.name", "paul@example.org");
user_pref("mail.server.server2.type", "none");
user_pref("mail.server.server2.hostname", "Local Folders");
user_pref("mail.server.server2.name", "Local Folders");
user_pref("mail.identity.id1.fullName", "Paul");
user_pref("mail.identity.id1.useremail", "paul@example.org");
user_pref("mail.identity.id1.smtpServer", "smtp1");
user_pref("mail.smtpservers", "smtp1");
user_pref("mail.smtp.defaultserver", "smtp1");
user_pref("mail.smtpserver.smtp1.hostname", "smtp.example.org");
user_pref("mail.smtpserver.smtp1.port", 465);
user_pref("mail.smtpserver.smtp1.try_ssl", 3);
user_pref("mail.smtpserver.smtp1.authMethod", 3);
user_pref("mail.smtpserver.smtp1.username", "paul@example.org");
user_pref("mail.shell.checkDefaultClient", false);
user_pref("app.donation.eoy.version.viewed", 99);
```

The password is asked for on first connection and stored in the profile's
logins.json; nothing here holds it. Verify on the clean install: the first
launch should open on the Inbox with no account dialog. If it does not, the
prefs that changed are `socketType`/`try_ssl` (the numeric codes moved once
already, between the 60s and 78) and that is where to look.

### Claws Mail — the same, in INI files (verified on this bench)

`~/.claws-mail/accountrc` with one `[Account: 1]` section (`protocol=3` is
IMAP4, `ssl_imap=1`/`ssl_smtp=1` is TLS on connect, ports 993 and 465) and a
`folderlist.xml` declaring the IMAP tree for that account id. Claws skips its
Setup Wizard when `accountrc` exists: probed here with a dummy address, the
first start opened on "paul@example.org - Claws Mail 4.4.0", no wizard.

### Where the address comes from

`make answers` asks for a mail address and, if one is given, the display
name and the IMAP and SMTP hosts (defaults: the git name, `imap.` and
`smtp.` in front of the address's domain). They travel to the card in
`copal.conf` as `PI_MAIL_*`, and stage 12's `seed_app_configs` writes both
clients' files from them, only where absent. No address, no seed, wizards as
before. The password is never part of it.

### Firefox ESR and Brave — no welcome page, no import prompt

Enterprise policies, read on every start:

```json
// /usr/lib/firefox-esr/distribution/policies.json  (root; stage 4 territory)
{ "policies": {
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "DisableTelemetry": true,
    "DontCheckDefaultBrowser": true,
    "NoDefaultBookmarks": true } }
```

Brave reads Chromium-style policies from `/etc/brave/policies/managed/*.json`
on a native install; inside the Flatpak the path is under
`~/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/policies`
(to verify). Keys: `"BraveRewardsDisabled": true`, `"BraveWalletDisabled": true`,
`"BrowserSignin": 0`, `"DefaultBrowserSettingEnabled": false`.

### Mail in KMail

Akonadi resources are created by the KDE account wizard and stored across
`~/.config/akonadi*`, `emailidentities` and `kmail2rc`; there is no clean
declarative seed. The honest plan is to let the wizard run, or to use
`kmail-account-wizard` with its ISPDB lookup, which is three fields.
"""


def main():
    rows = [r for r in catalogue() if r["mode"] == "x"]
    v = verdicts()
    out = []
    out.append("# The Application Integration Plan: Launch Everything Once, Write Down What Happens, Design Away the Wizards\n")
    out.append("<!-- SPDX-License-Identifier: MIT -->\n<!-- generated by tools/copal-app-plan.py from the catalogue and ~/copal-apps/log.txt; edit NOTES in the script, not this table -->\n")
    out.append("Copyright (c) 2026 paulr@sdf.org. MIT licensed — see `LICENSE`.\n\n---\n")
    out.append("""## The procedure

One program at a time, on the bench (a Copal guest with the catalogue
installed, or the clean install when it exists):

1. `tools/copal-app-probe.sh NAME` — it starts the program, waits for its
   window, screenshots it, reads its stderr, closes it, and appends one line
   to `~/copal-apps/log.txt`. `--keep` leaves it open for a hand test.
2. Read the line. Three verdicts:
   - **ok** — a window of its own, no first-run dialog. Look at the
     screenshot once; move on.
   - **WIZARD** — a first-run or setup dialog. Decide: seed its configuration
     from the installer (a `configure_<program>` step that writes the file the
     wizard would have written, only when absent), or record that the wizard
     is the right first experience and leave it.
   - **NO WINDOW** — read `~/copal-apps/NAME.log`. Missing resource, missing
     device, or a tray applet that never has a window.
3. Fix what the installer can fix, in `copal-prep.sh`, with the observation
   written beside it. Rerun the probe. Regenerate this document:
   `tools/copal-app-plan.py`, and commit the log line with it.

The sweep runs the graphical entries of the catalogue in section order,
games last: fullscreen SDL games can take the compositor with them, so they
are probed one by one with a person watching.

## Inventory and verdicts
""")
    out.append("%d graphical catalogue entries. Verdict is the latest probe line for that command from this bench's own home, i.e. the first-run state; a RESOLVED note means the seed was verified from a throwaway home and the verdict here is what a machine without the seed shows. Blank means not probed yet.\n" % len(rows))
    out.append("| Section | Program | Command | Verdict | Note |\n|---|---|---|---|---|")
    for r in sorted(rows, key=lambda r: (r["section"] != "Games", r["section"], r["label"].lower()) if False else (r["section"] == "Games", r["section"], r["label"].lower())):
        verdict = v.get(r["bin"], "")
        verdict = verdict.replace("|", "/")
        note = NOTES.get(r["bin"], "")
        out.append("| %s | %s | `%s` | %s | %s |" % (r["section"], r["label"].replace("|", "/"), r["bin"], verdict, note))
    extras = [("kicad", "KiCad"), ("kmail", "KMail"), ("brave", "Brave (Flatpak)"), ("x64sc", "VICE x64sc"), ("thunderbird", "Thunderbird"), ("wxmaxima", "wxMaxima (built)"), ("ytq", "ytq")]
    out.append("\nOutside the catalogue table, installed by their own stages:\n")
    out.append("| Program | Command | Verdict | Note |\n|---|---|---|---|")
    for b, label in extras:
        if any(r["bin"] == b for r in rows):
            continue
        out.append("| %s | `%s` | %s | %s |" % (label, b, v.get(b, "").replace("|", "/"), NOTES.get(b, "")))
    counts = {}
    for r in rows:
        k = v.get(r["bin"], "")
        key = "ok" if k.startswith("ok") else "WIZARD" if k.startswith("WIZARD") else "NO WINDOW" if k.startswith("NO WINDOW") else "not probed"
        counts[key] = counts.get(key, 0) + 1
    out.append("\nTally: " + ", ".join("%s %d" % (k, n) for k, n in sorted(counts.items())) + ".\n")
    out.append(RECIPES)
    out.append("\n*Generated %s.*\n" % time.strftime("%Y-%m-%d %H:%M"))
    with open(os.path.join(ROOT, "docs", "app-integration-plan.md"), "w") as f:
        f.write("\n".join(out))
    print("docs/app-integration-plan.md: %d entries, %s" % (len(rows), counts))


if __name__ == "__main__":
    main()
