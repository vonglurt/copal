#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 paulr@sdf.org -- part of Copal Linux.
#
# copal-terminal-palettes.py -- derive the opaque terminal palettes that
# copal-terminal-theme carries for the Linux Antiquity (diinki) themes.
#
# The theme's kitty files are one neon palette (black #9400ff, white #ff00ee)
# for a window at 20 % opacity over a blurred wallpaper, and one glass tint
# per theme. Opaque, on a CPU renderer, that palette is unreadable. This
# script takes each theme's own design tokens from quickshell/Config.qml --
# tint, text, accent, danger, warning, the humours and the elements -- and
# moves each one along its own hue until it reads at 4.5:1 (WCAG AA) on the
# opaque tint. Hue and saturation are kept; only lightness moves. Bright
# variants go one step further in the same direction, and a little more
# saturated, so "bright" still means "more" on a light ground.
#
# Output: the POSIX-sh case arms pasted into tools/copal-terminal-theme.
# Re-run it when Antiquity's Config.qml changes its tokens.
import colorsys

WCAG = 4.5

def hexrgb(h):
    h = h.lstrip('#'); return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
def rgbhex(c):
    return ''.join('%02x' % round(max(0, min(1, x)) * 255) for x in c)
def lum(c):
    def ch(v): return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = c; return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
def contrast(a, b):
    la, lb = lum(a), lum(b); hi, lo = max(la, lb), min(la, lb); return (hi + 0.05) / (lo + 0.05)

def fit(seed, ground, target=WCAG, sat_boost=0.0, extra_l=0.0):
    """Move seed's HSL lightness away from the ground until contrast >= target."""
    g = hexrgb(ground); s0 = hexrgb(seed)
    h, l, s = colorsys.rgb_to_hls(*s0)
    s = min(1.0, s + sat_boost)
    dark_ground = lum(g) < 0.18
    if dark_ground: s = min(s, 0.75)     # neon reads as glare on a dark ground
    step = 0.005 if dark_ground else -0.005
    c = colorsys.hls_to_rgb(h, l, s)
    # If the seed already sits on the wrong side of the ground, start from mid.
    if (lum(c) > lum(g)) != dark_ground:
        l = 0.5
        c = colorsys.hls_to_rgb(h, l, s)
    while contrast(c, g) < target and 0.0 < l < 1.0:
        l += step; c = colorsys.hls_to_rgb(h, l, s)
    l = max(0.0, min(1.0, l + (extra_l if dark_ground else -extra_l)))
    return rgbhex(colorsys.hls_to_rgb(h, l, s))

# Antiquity's tokens (configs/quickshell/Config.qml) and the kitty grounds.
# helios's ground is its tint #fce2ab faded 60 % toward white: opaque, the
# tint itself was too yellow (Paul, 2 Sep 2026); the glass showed it paler.
# Each entry: ground, text, cursor-candidate (accent), selection, then the
# eight hue seeds: black red green yellow blue magenta cyan white.
PURPLE = '#AC82E9'      # the rice's signature purple, kitty color3/color6
GREEN  = '#00ff5d'      # kitty color2, the only green the design has
THEMES = {
  'helios': dict(ground='fdf2da', text='121212', accent='fccf8a', sel='fccf8a',
    seeds=['181818','fc5870',GREEN,'fcd37b','6f8ebc',PURPLE,'92bbcc','87704f'],
    brights=['87704f','ff723e','a7b777','fcd37b','425682',PURPLE,'92bbcc','473e39']),
  'eris': dict(ground='b9c5c9', text='121212', accent='c7cfe5', sel='d2dddc',
    seeds=['1b1c1e','fc5870',GREEN,'fcd37b','6f8ebc',PURPLE,'92bbcc','767d7f'],
    brights=['505160','c15555','68877f','fcd37b','425682','b6aae2','92bbcc','536868']),
  'priapus': dict(ground='a6bf85', text='121212', accent='a7b777', sel='f2efb3',
    seeds=['1f211e','fc5870','5b6b54','f2d793','6f8ebc',PURPLE,'bcd8d6','747c5c'],
    brights=['4a5437','c15555','a7b777','cdce8c','425682',PURPLE,'92bbcc','3e3f2f']),
  'eros': dict(ground='3c2d66', text='d0daed', accent='fccb7b', sel='53475e',
    seeds=['2c243d','eda1a6','a7b777','fcd37b','6f8ebc',PURPLE,'92bbcc','d0daed'],
    brights=['705a7a','f9997f','a7b777','fccb7b','92bbcc','ad7082','ccdde2','d0daed']),
  'hades': dict(ground='eaeaea', text='181818', accent='d1ceca', sel='d1ceca',
    seeds=['181818','aa3a3a',GREEN,'c6c479','66929e',PURPLE,'8da5c9','7f7f7f'],
    brights=['5e5e5e','c44444',GREEN,'c6c479','425682',PURPLE,'8da5c9','423f3d']),
}

def derive(name, t):
    g = t['ground']
    dark = lum(hexrgb(g)) < 0.18
    fg = fit(t['text'], g, 7.0)
    # Cursor: the accent where it can be seen (3:1), otherwise the text colour.
    cursor = t['accent'] if contrast(hexrgb(t['accent']), hexrgb(g)) >= 3.0 else fg
    # Selection: the theme's pale token as the band, text on it fitted to 4.5.
    selbg = t['sel']; selfg = fit(t['text'], selbg, WCAG)
    cols = [fit(s, g) for s in t['seeds']]
    # Black is a ground for TUI panels (mc, htop) as often as it is a text
    # colour: on a light ground it is solid dark, on a dark ground it stays
    # the theme's own highlight shade, one step up from the tint, and only
    # bright black (8, the "dim" text colour) is pulled to 4.5:1.
    cols[0] = t['seeds'][0] if dark else fit(t['seeds'][0], g, 7.0)
    cols += [fit(s, g, WCAG, sat_boost=0.1, extra_l=0.04) for s in t['brights']]
    return dict(BG=g, FG=fg, CURSOR=cursor, SELBG=selbg, SELFG=selfg, cols=cols)

if __name__ == '__main__':
    for name, t in THEMES.items():
        p = derive(name, t)
        g = hexrgb(p['BG'])
        worst = min(contrast(hexrgb(c), g) for c in p['cols'][1:] + [p['FG']])
        print('    %s)  # worst contrast on the ground %.1f:1' % (name, worst))
        print('        BG=%s; FG=%s; CURSOR=%s; SELBG=%s; SELFG=%s' % (p['BG'], p['FG'], p['CURSOR'], p['SELBG'], p['SELFG']))
        for row in (range(0, 8), range(8, 16)):
            print('        ' + '  '.join('C%d=%s' % (i, p['cols'][i]) for i in row))
        print('        ;;')
