#!/usr/bin/env python3
"""Map the matugen palette to the nearest catppuccin mocha cursor accent.

Reads the primary color from the quickshell-generated colors.json, finds the
closest catppuccin mocha accent by HSL hue/chroma, applies the matching
catppuccin-mocha-<accent>-cursors theme via hyprctl, and persists the theme
name to ~/.cache/cursor_theme for use at session start (see execs.lua).
"""

import colorsys
import json
import os
import subprocess
import sys

COLORS_PATH = os.path.expanduser(
    "~/.local/state/quickshell/user/generated/colors.json"
)
STATE_PATH = os.path.expanduser("~/.cache/cursor_theme")
DEFAULT_THEME = "catppuccin-mocha-flamingo-cursors"
SIZE = 24

# catppuccin mocha accents
ACCENTS = {
    "rosewater": "#f5e0dc",
    "flamingo": "#f2cdcd",
    "pink": "#f5c2e7",
    "mauve": "#cba6f7",
    "red": "#f38ba8",
    "maroon": "#eba0ac",
    "peach": "#fab387",
    "yellow": "#f9e2af",
    "green": "#a6e3a1",
    "teal": "#94e2d5",
    "sky": "#89dceb",
    "sapphire": "#74c7ec",
    "blue": "#89b4fa",
    "lavender": "#b4befe",
}


def hex_to_hsl(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hue, light, sat = colorsys.rgb_to_hls(r, g, b)
    # HLS: (hue 0-1, light, sat) -> compare with (hue, saturation, lightness)
    return hue * 360, sat, light


def main():
    try:
        colors = json.load(open(COLORS_PATH))
        primary = colors["primary"]
    except Exception as e:
        print(f"cursor-theme: cannot read {COLORS_PATH}: {e}", file=sys.stderr)
        return 0

    hue, sat, light = hex_to_hsl(primary)
    best, best_score = None, 1e9
    for name, hexval in ACCENTS.items():
        h2, s2, l2 = hex_to_hsl(hexval)
        dh = min(abs(hue - h2), 360 - abs(hue - h2)) / 180.0
        score = dh * 1.2 + abs(sat - s2) * 0.5 + abs(light - l2)
        if score < best_score:
            best, best_score = name, score

    theme = f"catppuccin-mocha-{best}-cursors"
    with open(STATE_PATH, "w") as f:
        f.write(theme + "\n")

    print(f"cursor-theme: primary {primary} -> {theme}")
    # Apply live if a Hyprland session is running
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        subprocess.run(["hyprctl", "setcursor", theme, str(SIZE)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0


if __name__ == "__main__":
    sys.exit(main())
