#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 paulr@sdf.org -- part of Copal Linux.
#
# copal-app-sweeplist.py -- write the gallery sweep list: one row per catalogue
# program whose binary is installed (plus the bench extras), tab separated:
#   NAME <tab> COMMAND <tab> FIRST-ACTION (copal-act words, may be empty)
# Terminal programs run inside foot; a few graphical ones get an X11 backend
# so a stroke can be drawn with xdotool. Output: ~/.cache/copal-gallery/gallery-list.txt
import re, shutil, os
H = os.path.expanduser("~")
HELLO = "type 'hello copal'"
SH = "type 'echo hello copal' ret"
CALC = "type '6*7' ret"
# terminal programs: what to type once the prompt is up
T_ACT = {
 "vim": "type i wait 0.3 " + HELLO + " esc", "vis": "type i wait 0.3 " + HELLO + " esc",
 "hx": "type i wait 0.3 " + HELLO + " esc", "micro": HELLO, "nano": HELLO,
 "sc-im": "type '<hello copal' ret", "irssi": "type '/echo hello copal' ret",
 "weechat": "type '/print hello copal' ret", "lftp": "type '!echo hello copal' ret",
 "nethack": "type y", "adventure": "type no ret",
 "octave": """type 'disp("hello copal")' ret""", "maxima": """type 'print("hello copal");' ret""",
 "gp": """type 'print("hello copal")' ret""", "Singular": """type '"hello copal";' ret""",
 "R": """type 'cat("hello copal\\n")' ret""",
 "tmux": SH, "screen": SH, "byobu": SH, "zellij": SH, "dvtm": SH,
 "retro": "type \"'hello_copal s:put nl\" ret",
 "ocaml": """type 'print_endline "hello copal";;' ret""", "lua5.4": """type 'print("hello copal")' ret""",
 "guile": """type '(display "hello copal")' ret""", "csi": """type '(print "hello copal")' ret""",
 "sbcl": """type '(format t "hello copal~%")' ret""", "racket": """type '(displayln "hello copal")' ret""",
 "elixir": """type 'IO.puts "hello copal"' ret""", "ruby": """type 'puts "hello copal"' ret""",
 "gdb": "type 'echo hello copal\\n' ret", "cgdb": "type 'echo hello copal\\n' ret",
 "lldb": """type 'script print("hello copal")' ret""",
}
T_CMD = {"elixir": "iex", "ruby": "irb"}  # the REPL, not the script runner
# graphical programs: command override (env for an X11 backend, so xdotool can drag) and action
X_CMD = {
 "inkscape": "env GDK_BACKEND=x11 inkscape", "drawing": "env GDK_BACKEND=x11 drawing",
 "mypaint": "env GDK_BACKEND=x11 mypaint", "pinta": "env GDK_BACKEND=x11 pinta",
 "tuxpaint": "env SDL_VIDEODRIVER=x11 tuxpaint", "libresprite": "env SDL_VIDEODRIVER=x11 libresprite",
 "mscore": "env QT_QUICK_BACKEND=software mscore", "welle-io": "env QT_QUICK_BACKEND=software welle-io",
 "gzdoom": f"env DOOMWADDIR={H}/.cache/freedoom/usr/share/games/doom gzdoom",
}
X_ACT = {
 "mousepad": HELLO, "gedit": HELLO, "ghostwriter": HELLO, "abiword": HELLO, "lyx": HELLO, "xpad": HELLO, "zim": HELLO,
 "geany": "keys ctrl+n wait 1 " + HELLO, "kate": "keys ctrl+n wait 1 " + HELLO,
 "emacs": "keys ctrl+x type b wait 0.5 ret wait 0.5 " + HELLO,
 "gnumeric": HELLO + " ret",
 "inkscape": "wait 2 type p wait 0.5 xline", "drawing": "xline", "mypaint": "xline", "pinta": "xline",
 "tuxpaint": "wait 2 xline", "libresprite": "keys ctrl+n wait 1 ret wait 1 xline",
 "qalculate-gtk": CALC, "galculator": CALC, "speedcrunch": CALC,
 "gnome-mines": "click", "wxmaxima": """type 'print("hello copal");' ret""",
 "firefox-esr": "keys ctrl+l wait 0.5 " + HELLO, "brave": "keys ctrl+l wait 0.5 " + HELLO,
 "winebox-notepad++": HELLO,
}
TERMS = "alacritty kitty wezterm st urxvt xterm sakura lxterminal xfce4-terminal terminator tilda guake yakuake qterminal cool-retro-term zutty".split()
for t in TERMS: X_ACT[t] = SH

rows = []
for line in open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "copal-prep.sh")):
    p = line.rstrip("\n").split("|")
    if len(p) == 6 and re.match(r"^[A-Z][a-z]+$", p[0]) and p[4] in ("x", "t"):
        rows.append(p)
out = []; seen = set()
for sec, label, pkg, b, mode, _ in rows:
    if not shutil.which(b) or b in seen: continue
    seen.add(b)
    if mode == "t":
        out.append((b, f"foot -e sh -c '{T_CMD.get(b, b)}; sleep 25'", T_ACT.get(b, "")))
    else:
        out.append((b, X_CMD.get(b, b), X_ACT.get(b, "")))
WB = f"env WINEBOX_ROOT={H}/.cache/winebox-test WINE={H}/.cache/wine/root/usr/bin/wine WINE_TREE={H}/.cache/wine/root {H}/.cache/winebox"
extras = [("kicad", "kicad"), ("kmail", "kmail"), ("brave", "brave"), ("x64sc", "x64sc"),
 ("endless-sky", f"{H}/.cache/copal-build/es/build/endless-sky"),
 ("wxmaxima", f"{H}/.cache/copal-build/stage/bin/wxmaxima"),
 ("ytq", f"{H}/.cache/copal-bin/ytq"),
 ("streamripper", f"foot -e sh -c '{H}/.cache/copal-build/sr/streamripper-1.64.6/streamripper http://ice1.somafm.com/groovesalad-128-mp3 -d {H}/.cache/copal-build/sr/out -l 20; sleep 5'"),
 ("winebox-notepad++", f"{WB} run notepad++"), ("winecfg", f"{WB} cfg notepad++")]
for n, c in extras:
    if n not in seen: out.append((n, c, X_ACT.get(n, ""))); seen.add(n)
os.makedirs(f"{H}/.cache/copal-gallery", exist_ok=True)
with open(f"{H}/.cache/copal-gallery/gallery-list.txt", "w") as f:
    for n, c, a in out: f.write(f"{n}\t{c}\t{a}\n")
print(len(out), "entries,", sum(1 for _, _, a in out if a), "with a first action")
