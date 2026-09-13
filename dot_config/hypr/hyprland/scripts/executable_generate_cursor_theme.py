#!/usr/bin/env python3
"""Rebuild the cursor theme with the exact matugen primary color.

Previous implementation (apply_cursor_theme.py) picked the nearest of the
14 fixed catppuccin mocha accents, which visibly mismatched whenever the
matugen primary fell between two of them (e.g. pink #ffb2bf -> peach
#fab387, a brownish tone).

This script instead recolors the catppuccin cursor SVG templates with the
exact matugen primary and rebuilds a complete XCursor theme under
~/.local/share/icons/Matugen-Cursors. Hyprland picks it up through
~/.cache/cursor_theme (still written, same as before).

Invoked by matugen-update.sh after every palette change. Regeneration is
skipped when the primary color has not changed since the last run.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

SVG_SIZE_RE = re.compile(r'<svg[^>]*?\bwidth="([0-9.]+)"', re.IGNORECASE)
SVG_VIEWBOX_RE = re.compile(r'<svg[^>]*?\bviewBox="[0-9.\-\s]*?([0-9.]+)\s+([0-9.]+)"', re.IGNORECASE)


def svg_viewport(svg_text):
    """Return the SVG's user-space size (width, height).

    Metadata hotspots are expressed in this coordinate system, not in
    nominal_size units. Catppuccin templates draw on a 32x32 canvas while
    advertising nominal_size=24, so a hotspot of y=26 is legitimate -- it
    only looks out of bounds when wrongly divided by the nominal size.
    """
    m = SVG_SIZE_RE.search(svg_text)
    if m:
        size = float(m.group(1))
        return size, size
    m = SVG_VIEWBOX_RE.search(svg_text)
    if m:
        return float(m.group(1)), float(m.group(2))
    return None

COLORS_PATH = Path.home() / ".local/state/quickshell/user/generated/colors.json"
SRC_THEME = Path("/usr/share/icons/catppuccin-mocha-pink-cursors")
DST_THEME = Path.home() / ".local/share/icons/Matugen-Cursors"
STATE_PATH = Path.home() / ".cache/cursor_theme"
CACHE_NAME = ".source-color"

THEME_NAME = "Matugen-Cursors"
SIZE = 24
RENDER_SIZES = (24, 32, 48)
SOURCE_ACCENT = "#f5c2e7"


def log(msg):
    print(f"cursor-theme: {msg}", file=sys.stderr)


def read_primary():
    try:
        colors = json.loads(COLORS_PATH.read_text())
    except Exception as e:
        log(f"cannot read {COLORS_PATH}: {e}")
        return None
    primary = colors.get("primary")
    if not isinstance(primary, str) or not primary.startswith("#"):
        log("primary color missing or malformed in colors.json")
        return None
    return primary.lower()


def generate(primary):
    if not SRC_THEME.is_dir():
        log(f"source theme missing: {SRC_THEME}")
        return False
    for tool in ("rsvg-convert", "xcursorgen"):
        if shutil.which(tool) is None:
            log(f"required tool missing: {tool}")
            return False

    tmp = DST_THEME.with_name(DST_THEME.name + ".tmp")
    if tmp.exists():
        shutil.rmtree(tmp)
    (tmp / "cursors").mkdir(parents=True)
    (tmp / "cursors_scalable").mkdir()

    src_cursors = SRC_THEME / "cursors"
    src_scalable = SRC_THEME / "cursors_scalable"
    dst_cursors = tmp / "cursors"
    dst_scalable = tmp / "cursors_scalable"

    generated = symlinked = 0
    for entry in sorted(src_cursors.iterdir()):
        name = entry.name

        if entry.is_symlink():
            (dst_cursors / name).symlink_to(os.readlink(entry))
            symlinked += 1
            continue

        src_dir = src_scalable / name
        meta_path = src_dir / "metadata.json"
        if not meta_path.is_file():
            log(f"no metadata for {name}, skipping")
            continue

        try:
            meta = json.loads(meta_path.read_text())
        except Exception as e:
            log(f"bad metadata for {name}: {e}")
            return False

        out_dir = dst_scalable / name
        out_dir.mkdir()

        frames = []
        for item in meta:
            fname = item["filename"]
            svg_out = out_dir / fname
            svg_text = (src_dir / fname).read_text().replace(SOURCE_ACCENT, primary)
            svg_out.write_text(svg_text)

            viewport = svg_viewport(svg_text)
            if viewport is None:
                log(f"cannot determine viewport for {name}/{fname}")
                return False
            vw, vh = viewport

            hx = item["hotspot_x"] / vw
            hy = item["hotspot_y"] / vh
            delay = item.get("delay", 0)

            for size in RENDER_SIZES:
                png = out_dir / f"{fname}.{size}.png"
                proc = subprocess.run(
                    ["rsvg-convert", "-w", str(size), "-h", str(size),
                     str(svg_out), "-o", str(png)],
                    capture_output=True,
                )
                if proc.returncode != 0:
                    log(f"rsvg-convert failed: {name}/{fname}@{size}")
                    return False
                frames.append((size, round(hx * size), round(hy * size), png, delay))

        cfg = out_dir / "cursor.cfg"
        with open(cfg, "w") as f:
            for size, x, y, png, delay in frames:
                f.write(f"{size} {x} {y} {png} {delay}\n")

        proc = subprocess.run(
            ["xcursorgen", str(cfg), str(dst_cursors / name)],
            capture_output=True,
        )
        if proc.returncode != 0:
            log(f"xcursorgen failed: {name}: {proc.stderr.decode()[:200]}")
            return False

        for _, _, _, png, _ in frames:
            png.unlink(missing_ok=True)
        cfg.unlink(missing_ok=True)
        generated += 1

    (tmp / "index.theme").write_text(
        "[Icon Theme]\n"
        f"Name={THEME_NAME}\n"
        "Comment=Generated from the matugen wallpaper palette\n"
    )

    if not build_hyprcursors(tmp, primary):
        log("hyprcursor build failed, XCursor fallback will be used")
        shutil.rmtree(tmp / "hyprcursors", ignore_errors=True)
        (tmp / "manifest.hl").unlink(missing_ok=True)

    if DST_THEME.exists():
        shutil.rmtree(DST_THEME)
    tmp.rename(DST_THEME)
    log(f"rebuilt {generated} cursors + {symlinked} symlinks with accent {primary}")
    return True


def build_hyprcursors(tmp, primary):
    """Repackage the hyprcursor archives with the recolored SVGs.

    Hyprland prefers hyprcursors/*.hlc over XCursor files, so without this
    the cursor would keep rendering in the old source accent. Each .hlc is
    a zip holding the SVG plus a meta.hl; only the SVG bytes need rewriting.
    """
    src_hypr = SRC_THEME / "hyprcursors"
    if not src_hypr.is_dir():
        return False

    dst_hypr = tmp / "hyprcursors"
    dst_hypr.mkdir(exist_ok=True)

    for hlc in sorted(src_hypr.glob("*.hlc")):
        try:
            with zipfile.ZipFile(hlc) as zin:
                items = {n: zin.read(n) for n in zin.namelist()}
        except zipfile.BadZipFile:
            log(f"corrupt hyprcursor archive: {hlc.name}")
            return False

        with zipfile.ZipFile(dst_hypr / hlc.name, "w", zipfile.ZIP_DEFLATED) as zout:
            for name, data in items.items():
                if name.endswith(".svg"):
                    data = data.replace(
                        SOURCE_ACCENT.encode(), primary.encode()
                    )
                zout.writestr(name, data)

    (tmp / "manifest.hl").write_text(
        f"name = {THEME_NAME}\n"
        "description = Generated from the matugen wallpaper palette\n"
        'version = "1.0"\n'
        "cursors_directory = hyprcursors\n"
    )
    return True


def apply_theme():
    if not (DST_THEME / "cursors").is_dir():
        log("generated theme missing, not applying")
        return

    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(THEME_NAME + "\n")

    for key, value in (
        ("cursor-theme", THEME_NAME),
        ("cursor-size", str(SIZE)),
    ):
        subprocess.run(
            ["gsettings", "set", "org.gnome.desktop.interface", key, value],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        subprocess.run(
            ["hyprctl", "setcursor", THEME_NAME, str(SIZE)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )


def main():
    primary = read_primary()
    if primary is None:
        return 0

    cache = DST_THEME / CACHE_NAME
    if cache.is_file() and cache.read_text().strip().lower() == primary:
        log(f"accent unchanged ({primary}), skipping rebuild")
        apply_theme()
        return 0

    if not generate(primary):
        log("generation failed, keeping previous theme")
        return 0

    (DST_THEME / CACHE_NAME).write_text(primary + "\n")
    apply_theme()
    return 0


if __name__ == "__main__":
    sys.exit(main())
