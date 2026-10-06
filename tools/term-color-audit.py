#!/usr/bin/env python3
"""终端配色体检：把各终端的 ANSI 槽位拉齐，算 WCAG 对比度与明度关系。

不依赖任何第三方库。用来判断「哪个槽位在暗色背景上其实看不清」这类
肉眼容易漏的问题 —— 也用来在改模板后做前后对照。
"""
import re
import pathlib
import sys

HOME = pathlib.Path.home()


def hex2rgb(h):
    h = h.strip().lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rel_lum(rgb):
    def f(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (f(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = rel_lum(a), rel_lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def parse_kitty(p):
    d = {}
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split()
        if len(parts) == 2 and re.fullmatch(r'#[0-9a-fA-F]{6}', parts[1]):
            d[parts[0]] = hex2rgb(parts[1])
    out = {'background': d.get('background'), 'foreground': d.get('foreground'),
           'cursor': d.get('cursor'), 'cursor_text': d.get('cursor_text_color'),
           'sel_bg': d.get('selection_background'), 'sel_fg': d.get('selection_foreground')}
    for i in range(16):
        out[f'color{i}'] = d.get(f'color{i}')
    return out


def parse_alacritty(p):
    d = {}
    section = None
    for line in p.read_text().splitlines():
        line = line.strip()
        m = re.match(r'^\[colors\.(\w+)\]', line)
        if m:
            section = m.group(1)
            continue
        m = re.match(r"^(\w+)\s*=\s*'?(#[0-9a-fA-F]{6})'?", line)
        if m and section:
            d[f'{section}.{m.group(1)}'] = hex2rgb(m.group(2))
    names = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white']
    out = {'background': d.get('primary.background'), 'foreground': d.get('primary.foreground'),
           'cursor': d.get('cursor.cursor'), 'cursor_text': d.get('cursor.text'),
           'sel_bg': d.get('selection.background'), 'sel_fg': d.get('selection.text')}
    for i, n in enumerate(names):
        out[f'color{i}'] = d.get(f'normal.{n}')
        out[f'color{i + 8}'] = d.get(f'bright.{n}')
    return out


def parse_foot(p):
    # ⚠ 必须跟踪段名：文件里有 [colors] / [colors.cursor] / [colors.selection]
    #   三段，键名（background / foreground）互相重名，不区分段就会读串。
    d = {}
    section = ''
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        m = re.match(r'^\[(.+)\]', line)
        if m:
            section = m.group(1) + '.'
            continue
        m = re.match(r'^([\w-]+)\s*=\s*([0-9a-fA-F]{6})\s*$', line)
        if m:
            d[section + m.group(1)] = hex2rgb(m.group(2))
    out = {'background': d.get('colors.background'), 'foreground': d.get('colors.foreground'),
           'cursor': d.get('colors.cursor.cursor'), 'cursor_text': d.get('colors.cursor.text'),
           'sel_bg': d.get('colors.selection.background'), 'sel_fg': d.get('colors.selection.foreground')}
    for i in range(8):
        out[f'color{i}'] = d.get(f'colors.regular{i}')
        out[f'color{i + 8}'] = d.get(f'colors.bright{i}')
    return out


def parse_konsole(p):
    d = {}
    section = None
    for line in p.read_text().splitlines():
        line = line.strip()
        m = re.match(r'^\[(\w+)\]', line)
        if m:
            section = m.group(1)
            continue
        m = re.match(r'^Color\s*=\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)', line)
        if m and section:
            d[section] = tuple(int(x) for x in m.groups())
    out = {'background': d.get('Background'), 'foreground': d.get('Foreground'),
           'cursor': d.get('Cursor'), 'cursor_text': None,
           'sel_bg': d.get('SelectionBackground'), 'sel_fg': d.get('SelectionForeground')}
    for i in range(8):
        out[f'color{i}'] = d.get(f'Color{i}')
        out[f'color{i + 8}'] = d.get(f'Color{i}Intense')
    return out


TARGETS = [
    ('kitty', HOME / '.config/kitty/current-theme.conf', parse_kitty),
    ('alacritty', HOME / '.config/alacritty/matugen-theme.toml', parse_alacritty),
    ('foot', HOME / '.config/foot/matugen.ini', parse_foot),
    ('konsole', HOME / '.local/share/konsole/Matugen.colorscheme', parse_konsole),
]

ANSI_NAMES = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white']
issues = []

for name, path, parser in TARGETS:
    if not path.exists():
        print(f'\n### {name}: 文件不存在（{path}）')
        continue
    try:
        d = parser(path)
    except Exception as e:                       # noqa: BLE001
        print(f'\n### {name}: 解析失败 {e}')
        continue
    bg = d.get('background')
    if not bg:
        print(f'\n### {name}: 没解析到 background')
        continue

    print(f'\n### {name}   bg={("#%02x%02x%02x" % bg)}  fg={("#%02x%02x%02x" % d["foreground"]) if d.get("foreground") else "?"}')
    print(f'{"槽位":<6}{"normal":<10}{"对比度":<9}{"bright":<10}{"对比度":<9}{"亮差"}')
    for i in range(8):
        n, b = d.get(f'color{i}'), d.get(f'color{i + 8}')
        cn = contrast(n, bg) if n else None
        cb = contrast(b, bg) if b else None
        # bright 应该比 normal 亮；差值为负说明反了
        dl = (rel_lum(b) - rel_lum(n)) if (n and b) else None
        flag = ''
        if cn is not None and cn < 4.5:
            flag += ' LOW'
            issues.append(f'{name}: color{i}（{ANSI_NAMES[i]}）对比度只有 {cn:.2f}')
        if cb is not None and cb < 4.5:
            flag += ' LOW-BRIGHT'
            issues.append(f'{name}: color{i + 8}（bright {ANSI_NAMES[i]}）对比度只有 {cb:.2f}')
        if dl is not None and dl <= 0:
            flag += ' BRIGHT-NOT-BRIGHTER'
            issues.append(f'{name}: bright {ANSI_NAMES[i]} 不比 normal 亮（Δlum={dl:+.4f}）')
        print(f'{ANSI_NAMES[i]:<6}'
              f'{"#%02x%02x%02x" % n if n else "?":<10}{f"{cn:.2f}" if cn else "-":<9}'
              f'{"#%02x%02x%02x" % b if b else "?":<10}{f"{cb:.2f}" if cb else "-":<9}'
              f'{f"{dl:+.4f}" if dl is not None else "-"}{flag}')

    cur, curt = d.get('cursor'), d.get('cursor_text')
    if cur:
        c = contrast(cur, bg)
        line = f'cursor       {"#%02x%02x%02x" % cur}  vs bg {c:.2f}'
        if curt:
            line += f'  vs cursor_text {contrast(curt, cur):.2f}'
        print(line)
    sb, sf = d.get('sel_bg'), d.get('sel_fg')
    if sb:
        line = f'selection    {"#%02x%02x%02x" % sb}  vs bg {contrast(sb, bg):.2f}'
        if sf:
            line += f'  fg/bg {contrast(sf, sb):.2f}'
            if contrast(sf, sb) < 4.5:
                issues.append(f'{name}: 选中态文字对比度只有 {contrast(sf, sb):.2f}')
        print(line)

print('\n════ 问题清单 ════')
if not issues:
    print('  无')
else:
    for i in issues:
        print('  · ' + i)
sys.exit(0)
