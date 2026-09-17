#!/usr/bin/env python3
"""Compute a dominant-colour bucket for every wallpaper in a directory.

The wallpaper selector uses these buckets to offer colour filtering. Results
are cached per directory and keyed on (name, mtime, size), so repeated runs
over an unchanged directory are cheap.

Usage:
    index_colors.py <src_dir> [cache_dir]

Prints the index as JSON on stdout. When cache_dir is given, the same JSON is
also written to <cache_dir>/dirs/<dirhash>/colors.json.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

try:
    from PIL import Image

    HAS_PIL = True
except ImportError:
    HAS_PIL = False

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif", ".tif", ".tiff"}
VIDEO_EXTS = {".mp4", ".mkv", ".mov", ".webm", ".avi"}


def dir_hash(path: str) -> str:
    return hashlib.sha256(os.path.abspath(path).encode("utf-8")).hexdigest()[:16]


def colour_bucket(hex_str: str) -> str:
    """Map a hex colour to a coarse hue bucket, mirroring the picker's chips."""
    if not hex_str:
        return "Monochrome"
    value = str(hex_str).strip().lstrip("#")[:6]
    if len(value) != 6:
        return "Monochrome"
    try:
        r = int(value[0:2], 16) / 255.0
        g = int(value[2:4], 16) / 255.0
        b = int(value[4:6], 16) / 255.0
    except ValueError:
        return "Monochrome"

    mx = max(r, g, b)
    mn = min(r, g, b)
    delta = mx - mn
    sat = 0.0 if mx == 0 else delta / mx
    val = mx

    hue = 0.0
    if delta != 0:
        if mx == r:
            hue = (g - b) / delta + (6.0 if g < b else 0.0)
        elif mx == g:
            hue = (b - r) / delta + 2.0
        else:
            hue = (r - g) / delta + 4.0
        hue *= 60.0

    if sat < 0.05 or val < 0.08:
        return "Monochrome"
    if hue >= 345 or hue < 15:
        return "Red"
    if 15 <= hue < 45:
        return "Orange"
    if 45 <= hue < 75:
        return "Yellow"
    if 75 <= hue < 165:
        return "Green"
    if 165 <= hue < 260:
        return "Blue"
    if 260 <= hue < 315:
        return "Purple"
    return "Pink"


def extract_colour(path: str) -> str:
    """Average an image down to a single pixel and return it as #rrggbb."""
    if HAS_PIL:
        try:
            with Image.open(path) as im:
                im = im.convert("RGB").resize((1, 1), Image.Resampling.BOX)
                r, g, b = im.getpixel((0, 0))
                return "#%02x%02x%02x" % (r, g, b)
        except Exception:
            pass

    for cmd in ("magick", "convert"):
        try:
            out = subprocess.check_output(
                [cmd, f"{path}[0]", "-resize", "1x1!", "-format", "%[hex:p{0,0}]", "info:-"],
                stderr=subprocess.DEVNULL,
                timeout=10,
            ).decode("utf-8").strip()
            if len(out) >= 6:
                return "#" + out[:6]
        except Exception:
            continue
    return "#808080"


def process_entry(entry, cached):
    name, path, mtime, size = entry
    previous = cached.get(name)
    if previous and previous.get("mtime") == mtime and previous.get("size") == size:
        return previous

    hex_colour = extract_colour(path)
    return {
        "fileName": name,
        "hex": hex_colour,
        "bucket": colour_bucket(hex_colour),
        "mtime": mtime,
        "size": size,
    }


def collect(src_dir: str):
    entries = []
    seen_paths = set()
    try:
        scanned = list(os.scandir(src_dir))
    except OSError:
        return entries

    for item in scanned:
        try:
            if not item.is_file():
                continue
        except OSError:
            continue

        ext = os.path.splitext(item.name)[1].lower()
        if ext in VIDEO_EXTS:
            continue  # videos are bucketed as "Video" by the shell, no colour needed
        if ext not in IMAGE_EXTS:
            continue

        try:
            real = os.path.realpath(item.path)
            if real in seen_paths:
                continue
            stat = item.stat()
        except OSError:
            continue

        seen_paths.add(real)
        entries.append((item.name, os.path.abspath(item.path), int(stat.st_mtime), int(stat.st_size)))
    return entries


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: index_colors.py <src_dir> [cache_dir]", file=sys.stderr)
        return 2

    src_dir = sys.argv[1]
    if src_dir.startswith("file://"):
        src_dir = src_dir[7:]
    src_dir = os.path.abspath(src_dir)

    cache_dir = sys.argv[2] if len(sys.argv) > 2 else ""

    index_file = ""
    if cache_dir:
        per_dir = os.path.join(cache_dir, "dirs", dir_hash(src_dir))
        index_file = os.path.join(per_dir, "colors.json")
        os.makedirs(per_dir, exist_ok=True)

    cached = {}
    if index_file and os.path.exists(index_file):
        try:
            with open(index_file, "r", encoding="utf-8") as handle:
                for item in json.load(handle).get("items", []):
                    if item.get("fileName"):
                        cached[item["fileName"]] = item
        except Exception:
            cached = {}

    entries = collect(src_dir)
    workers = min(12, max(4, os.cpu_count() or 4))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(lambda e: process_entry(e, cached), entries))

    payload = {
        "srcDir": src_dir,
        "dirHash": dir_hash(src_dir),
        "updatedAt": int(time.time()),
        "items": results,
    }

    if index_file:
        tmp = f"{index_file}.tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, indent=2)
            os.replace(tmp, index_file)
        except Exception:
            pass

    sys.stdout.write(json.dumps(payload))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
