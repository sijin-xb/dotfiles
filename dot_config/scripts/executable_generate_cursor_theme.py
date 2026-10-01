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

Under niri the rebuild alone is not enough: niri only reloads the cursor
theme when the *value* of its cursor config changes, so a same-named theme
whose files were rewritten keeps rendering with the old cached textures.
refresh_niri_cursor() therefore flips the theme name between two equivalent
names (the second one a symlink to the first) in DMS's generated cursor.kdl.

That flip only works if niri is actually pointing at our theme. In the niri
session the authoritative value is DMS's cursorSettings.theme, and it was
still holding a stock catppuccin name left over from the old
nearest-accent implementation -- so the compositor kept drawing the
unmodified catppuccin cursor while XCURSOR_THEME pointed at Matugen-Cursors.
reconcile_dms_cursor() repairs that on every run (it is a no-op once the
value is ours, and it leaves a deliberately chosen third-party theme alone).
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
SHELL_CONFIG_PATH = Path.home() / ".config/illogical-impulse/config.json"
SRC_THEME = Path("/usr/share/icons/catppuccin-mocha-pink-cursors")
DST_THEME = Path.home() / ".local/share/icons/Matugen-Cursors"
STATE_PATH = Path.home() / ".cache/cursor_theme"
CACHE_NAME = ".source-color"

THEME_NAME = "Matugen-Cursors"
SIZE = 24
RENDER_SIZES = (24, 32, 48)
SOURCE_ACCENT = "#f5c2e7"

# niri 只在 cursor 配置的「值」发生变化时才重载光标主题。见 niri 源码
# src/niri.rs 的 reload_config：
#
#     if config.cursor != old_config.cursor {
#         self.niri.cursor_manager.reload(&config.cursor.xcursor_theme, ...);
#         self.niri.cursor_texture_cache.clear();
#     }
#
# 主题目录的内容（颜色）变了、但主题名没变时，niri 判定「配置没变」→ 不重载
# 也不清纹理缓存，屏幕上还是旧颜色的光标，要等重新登录才更新。
# 所以重建完主题后，在 DMS 生成的 cursor.kdl 里把主题名在两个等价名字之间
# 交替一次（-alt 是指向同一目录的符号链接，渲染出来完全一样），制造一次真实
# 的值变化。这样 DMS 的 settings.json、环境变量、手写的 config.kdl 都不用动。
ALT_THEME_NAME = THEME_NAME + "-alt"
NIRI_CURSOR_KDL = Path.home() / ".config/niri/dms/cursor.kdl"
CURSOR_THEME_RE = re.compile(r'xcursor-theme\s+"([^"]*)"')

# DMS 的光标设置是 niri 会话里真正生效的来源（它据此生成 dms/cursor.kdl）。
DMS_SETTINGS_PATH = Path.home() / ".config/DankMaterialShell/settings.json"

# 旧实现 apply_cursor_theme.py 从 14 个 catppuccin mocha accent 里挑「最近的
# 一个」，所以 DMS 里记下的是 catppuccin-mocha-<accent>-cursors。换成精确取色
# 的新实现后，生成的是 Matugen-Cursors，但没人去改 DMS 的那个值 ——
# 结果 niri 合成器一直画原始 catppuccin 光标，而 XCURSOR_THEME 指向
# Matugen-Cursors，合成器和程序看到的是两套光标。
#
# 只在这种「stock catppuccin 残留」的情况下改写。用户如果在 DMS 界面里选了
# 别的主题（Bibata 之类），那是明确的选择，不动。
STOCK_CURSOR_RE = re.compile(r'^catppuccin-[a-z0-9-]*-cursors$')


def log(msg):
    print(f"cursor-theme: {msg}", file=sys.stderr)


def cursor_theming_enabled():
    """Honor the Settings > Interface > Color generation cursor toggle.

    Missing file or missing key means enabled, so an install that predates
    the toggle keeps working.
    """
    try:
        cfg = json.loads(SHELL_CONFIG_PATH.read_text())
    except Exception:
        return True
    value = cfg.get("appearance", {}).get("wallpaperTheming", {}).get("enableCursor")
    return value is not False


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


def ensure_alt_theme():
    """Make ALT_THEME_NAME resolve to the freshly rebuilt theme.

    A symlink (not a copy) so there is exactly one generated theme on disk and
    both names always render identical cursors. Returns False if the path is
    occupied by something we did not create.
    """
    alt = DST_THEME.with_name(ALT_THEME_NAME)
    if alt.is_symlink():
        if os.readlink(alt) == THEME_NAME:
            return True
        alt.unlink()
    elif alt.exists():
        log(f"{alt} exists and is not a symlink, leaving it alone")
        return False
    alt.symlink_to(THEME_NAME)
    return True


def refresh_niri_cursor():
    """Force niri to reload the cursor theme after the palette changed.

    Only touches the theme *name* in DMS's cursor.kdl, and only when it is
    currently one of our two equivalent names -- if the user picked a different
    cursor theme in DMS, the file is left for DMS to own.

    Note the name flip does not need NIRI_SOCKET: writing cursor.kdl is enough,
    because niri watches its own config file. The explicit `niri msg` below is
    just to make it immediate, so it is the only part that needs the socket.
    """
    if not NIRI_CURSOR_KDL.is_file():
        return

    text = NIRI_CURSOR_KDL.read_text()
    match = CURSOR_THEME_RE.search(text)
    if match is None:
        return

    current = match.group(1)
    if current == THEME_NAME:
        new_name = ALT_THEME_NAME
    elif current == ALT_THEME_NAME:
        new_name = THEME_NAME
    else:
        return

    if new_name == ALT_THEME_NAME and not ensure_alt_theme():
        return

    NIRI_CURSOR_KDL.write_text(
        text[: match.start(1)] + new_name + text[match.end(1):]
    )
    log(f"niri cursor theme name -> {new_name}")

    # niri 自己会监视配置文件，这一步只是让它立刻生效。NIRI_SOCKET 缺失
    # （从 TTY 跑）或指向已消失的旧会话时跳过即可，改名仍会随文件监视生效。
    if os.environ.get("NIRI_SOCKET") and shutil.which("niri") is not None:
        subprocess.run(
            ["niri", "msg", "action", "load-config-file"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )


def reconcile_dms_cursor():
    """把 DMS 的 cursorSettings.theme 从 stock catppuccin 残留改成 Matugen-Cursors。

    返回 True 表示确实改过。原子写（临时文件 + rename），避免和正在运行的
    DMS 抢写导致 settings.json 出现半截内容。
    """
    if not DMS_SETTINGS_PATH.is_file():
        return False

    try:
        data = json.loads(DMS_SETTINGS_PATH.read_text())
    except Exception as e:
        log(f"cannot read DMS settings ({DMS_SETTINGS_PATH}): {e}")
        return False

    cursor_settings = data.get("cursorSettings")
    if not isinstance(cursor_settings, dict):
        return False

    current = cursor_settings.get("theme")
    if not isinstance(current, str):
        return False
    if current in (THEME_NAME, ALT_THEME_NAME):
        return False
    if not STOCK_CURSOR_RE.match(current):
        log(f"DMS cursor theme is '{current}' (not a stock catppuccin name), leaving it alone")
        return False

    cursor_settings["theme"] = THEME_NAME
    try:
        tmp = DMS_SETTINGS_PATH.with_name(DMS_SETTINGS_PATH.name + ".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        tmp.replace(DMS_SETTINGS_PATH)
    except Exception as e:
        log(f"cannot write DMS settings: {e}")
        return False

    log(f"DMS cursorSettings.theme: {current} -> {THEME_NAME}")
    return True


def write_niri_cursor_kdl(name=THEME_NAME):
    """把 dms/cursor.kdl 的主题名直接写成 name。

    该文件头写着 DO NOT EDIT / AUTO-GENERATED，但 DMS 只在设置变更或启动时
    重写它。这里立刻写一份，省得等 DMS 重新生成；而 settings.json 已经改好，
    所以 DMS 下次写回时不会退回旧值。
    """
    if not NIRI_CURSOR_KDL.is_file():
        return False
    text = NIRI_CURSOR_KDL.read_text()
    new = CURSOR_THEME_RE.sub(f'xcursor-theme "{name}"', text, count=1)
    if new == text:
        return False
    NIRI_CURSOR_KDL.write_text(new)
    log(f"niri cursor.kdl -> {name}")
    return True


def apply_theme(skip_niri_flip=False):
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

    # 如果这一轮已经把 cursor.kdl 从「stock catppuccin」改成 Matugen-Cursors，
    # 那次改名本身就会让 niri 重载，不需要再交替一次。
    if skip_niri_flip:
        log("niri cursor.kdl 刚改写过，跳过本次交替")
    else:
        refresh_niri_cursor()


def main():
    if not cursor_theming_enabled():
        log("cursor theming disabled in settings, skipping")
        return 0

    primary = read_primary()
    if primary is None:
        return 0

    # DMS 的设置可能还停在旧实现的 stock catppuccin 名字上。每轮都核对一次 ——
    # 用户在 DMS 界面里动一次光标设置就会把它写回去，只有这里能纠回来。
    reconciled = reconcile_dms_cursor()
    if reconciled:
        write_niri_cursor_kdl()

    cache = DST_THEME / CACHE_NAME
    if cache.is_file() and cache.read_text().strip().lower() == primary:
        log(f"accent unchanged ({primary}), skipping rebuild")
        apply_theme(skip_niri_flip=reconciled)
        return 0

    if not generate(primary):
        log("generation failed, keeping previous theme")
        return 0

    (DST_THEME / CACHE_NAME).write_text(primary + "\n")
    apply_theme(skip_niri_flip=reconciled)
    return 0


if __name__ == "__main__":
    sys.exit(main())
