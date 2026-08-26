<!-- SPDX-License-Identifier: MIT -->
# Images for docs/index.html

The page reserves four slots. Each frame holds its aspect ratio whether or not
the file is there, so dropping one in never reflows the page around it, and a
missing image removes itself rather than showing a broken-image icon.

| File | What it shows |
|---|---|
| `install-cast.svg` | the install, accelerated — see below |
| `guided-levels.png` | the guided first screen: server / medium / full |
| `antiquity-desktop.png` | the full level: Hyprland with the Antiquity theme |
| `i3-desktop.png` | the medium level: i3 on the framebuffer |

## The install recording

Record with asciinema, then render to a **self-contained** animated SVG or GIF.
Do not embed asciinema's own player: it is a script from another host, and the
published page's CSP blocks every external host except Google Fonts, so a
player-based embed renders nothing.

    asciinema rec install.cast
    svg-term --in install.cast --out docs/media/install-cast.svg --window
    # or: agg install.cast docs/media/install-cast.gif   (then rename the src)

Keep it wide rather than tall — the frame is 16:9, and an install transcript
is a wide thing.
