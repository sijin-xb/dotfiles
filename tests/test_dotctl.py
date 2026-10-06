#!/usr/bin/env python3
"""dotctl 的契约测试（纯标准库 unittest）。

每个用例都在临时 HOME 下跑，不碰真实的 ~/.config 与 ~/.local/state。
paths 里全是函数（不是模块级常量），所以改 HOME 环境变量就生效。

用法：
    python3 -m unittest discover -s tests -p 'test_*.py' -t .
"""
from __future__ import annotations

import io
import os
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from dotctl import paths, state  # noqa: E402
from dotctl.commands import deps, status, theme  # noqa: E402


class TempHome(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.home = Path(self._tmp.name)
        patcher = mock.patch.dict(os.environ, {'HOME': str(self.home)})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self._tmp.cleanup)
        os.environ.pop('SESSION', None)

    def write(self, rel: str, text: str) -> Path:
        path = paths.home() / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def run_status(self, argv: list[str] | None = None) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(status, '_git', return_value=''):
            with redirect_stdout(out), redirect_stderr(err):
                rc = status.run(list(argv or []))
        return rc, out.getvalue(), err.getvalue()


class TestStatus(TempHome):
    def test_empty_home(self) -> None:
        rc, out, _ = self.run_status()
        self.assertEqual(rc, 0)
        self.assertIn('会话        end4pc', out)
        self.assertIn('部署清单    无', out)
        self.assertIn('上次部署    无记录', out)
        self.assertIn('快照        0 份', out)
        self.assertIn('备份占用    无', out)

    def test_manifest_count_matches_wc_l(self) -> None:
        """计数刻意等价 `wc -l`（bash 版用的就是它）：末尾有换行才算一行。

        这里不用 splitlines() 就是这个原因 —— 它会把没有尾换行的最后一行
        也算上，于是同一个清单在 bash 版和 Python 版显示成不同的项数。
        """
        shell, comp = state.DEFAULT_SESSION
        rel = f'.local/state/dotfiles-backup/state/deployed-{shell}-{comp}.tsv'

        self.write(rel, 'src/a\t.config/a\nsrc/b\t.config/b\n')
        _, out, _ = self.run_status()
        self.assertIn('· 2 项', out)

        # 尾行没有换行符：wc -l 数 1，splitlines() 会数 2
        self.write(rel, 'src/a\t.config/a\nsrc/b\t.config/b')
        _, out, _ = self.run_status()
        self.assertIn('· 1 项', out)

    def test_session_record_wins_over_env(self) -> None:
        self.write('.local/state/dotfiles-backup/state/deployed-session', 'dms|niri')
        os.environ['SESSION'] = 'end4pc'
        _, out, _ = self.run_status()
        self.assertIn('dms（niri + DankMaterialShell）', out)

    def test_revision_block(self) -> None:
        shell, comp = state.DEFAULT_SESSION
        self.write('.local/state/dotfiles-backup/state/deployed-session', f'{shell}|{comp}')
        self.write(f'.local/state/dotfiles-backup/state/deployed-revision-{shell}-{comp}',
                   'revision=abc1234\nbranch=main\ndirty=7\ntime=2026-10-06T08:00:00+08:00\n')
        _, out, _ = self.run_status()
        self.assertIn('2026-10-06T08:00:00+08:00（revision abc1234 · main · 当时工作区改动 7 项）', out)

    def test_snapshot_picks_newest(self) -> None:
        snaps = paths.snap_root()
        snaps.mkdir(parents=True)
        old, new = snaps / 'pre-install-old.tar.gz', snaps / 'pre-rollback-new.tar.gz'
        old.write_bytes(b'x' * 16)
        new.write_bytes(b'x' * 16)
        os.utime(old, (time.time() - 600, time.time() - 600))
        _, out, _ = self.run_status()
        self.assertIn('快照        2 份', out)
        self.assertIn('最近 pre-rollback-new.tar.gz', out)

    def test_help_and_stray_args(self) -> None:
        rc, out, _ = self.run_status(['--help'])
        self.assertEqual(rc, 0)
        self.assertIn('用法：./install.sh status', out)

        rc, out, _ = self.run_status(['--bogus'])
        self.assertEqual(rc, 2)
        self.assertIn('status 不接受参数：--bogus', out)


class TestSessionInference(TempHome):
    def test_presets(self) -> None:
        for raw, want in (('end4pc', ('end4-pC', 'hyprland')),
                          ('caelestia', ('caelestia', 'hyprland')),
                          ('dms', ('dms', 'niri'))):
            os.environ['SESSION'] = raw
            self.assertEqual(state.session_from_env(), want)

    def test_unknown_falls_back_with_warning(self) -> None:
        os.environ['SESSION'] = 'nonsense'
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(state.session_from_env(), state.DEFAULT_SESSION)
        # warn 走 stdout（与 bash 的 warn 一致）
        self.assertIn('未知的 SESSION 预设值', out.getvalue())

    def test_empty_env_is_silent(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(state.session_from_env(), state.DEFAULT_SESSION)
        self.assertEqual(out.getvalue(), '')

    def test_unset_home_falls_back(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop('HOME', None)
            self.assertTrue(str(paths.home()))



class TestDeps(TempHome):
    """包列表来自 bash 侧（bashsrc），所以这几条会真的 fork 一次 bash。

    断言只钉「输出形状与选项行为」，不钉具体包名 —— 包列表本来就该由
    lib/60-packages.sh 那边演进，钉死了每次加包都要改测试。
    """

    def run_deps(self, argv: list[str] | None = None) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        # pacman -Q 全部当作「没装」，输出就与机器实际状态无关了
        with mock.patch.object(deps, '_installed', return_value=False):
            with redirect_stdout(out), redirect_stderr(err):
                rc = deps.run(list(argv or []))
        return rc, out.getvalue(), err.getvalue()

    def test_all_groups(self) -> None:
        rc, out, _ = self.run_deps()
        self.assertEqual(rc, 0)
        self.assertIn('会话: end4pc', out)
        for title in ('官方仓库（pacman）', 'AUR', '字体（pacman）', '字体（AUR）'):
            self.assertIn(title, out)
        self.assertIn('以上为完整清单。只看缺口加 --missing。', out)

    def test_fonts_only(self) -> None:
        _, out, _ = self.run_deps(['--fonts'])
        self.assertIn('字体（pacman）', out)
        self.assertNotIn('官方仓库（pacman）', out)

    def test_missing_note_and_filter(self) -> None:
        _, out, _ = self.run_deps(['--missing'])
        self.assertIn('过滤: 只看未安装', out)
        self.assertIn('以上为未安装项。补齐：', out)

    def test_installed_packages_are_filtered_out(self) -> None:
        with mock.patch.object(deps, '_installed', return_value=True):
            out = io.StringIO()
            with redirect_stdout(out):
                deps.run(['--missing'])
        # 全装了 → 各组都空 → 只剩头两行与结尾提示
        self.assertNotIn('官方仓库（pacman）', out.getvalue())

    def test_self_name_follows_env(self) -> None:
        os.environ['DOTCTL_SELF'] = '/opt/dotfiles/install.sh'
        self.addCleanup(os.environ.pop, 'DOTCTL_SELF', None)
        rc, out, _ = self.run_deps(['-h'])
        self.assertEqual(rc, 0)
        self.assertIn('用法：/opt/dotfiles/install.sh deps', out)

    def test_unknown_option(self) -> None:
        rc, out, _ = self.run_deps(['--bogus'])
        self.assertEqual(rc, 2)
        self.assertIn('deps: 未知选项 --bogus', out)



class TestTheme(TempHome):
    """theme 只读配置文件，所以断言可以钉得很死 —— 每个 sink 写什么、就应
    该读到什么，不依赖机器实际状态（gsettings 例外，用 mock 挡掉）。"""

    def run_theme(self, argv: list[str] | None = None,
                  gsettings: dict[str, str] | None = None) -> tuple[int, str]:
        table = gsettings or {}
        out = io.StringIO()

        def fake(schema: str, key: str) -> str:
            return table.get(f'{schema}.{key}', '未设置')

        with mock.patch.object(theme, '_gsettings', side_effect=fake):
            with redirect_stdout(out):
                rc = theme.run(list(argv or []))
        return rc, out.getvalue()

    def test_sections_and_labels(self) -> None:
        rc, out = self.run_theme()
        self.assertEqual(rc, 0)
        for section in ('── 图标主题 ──', '── 光标主题 ──', '── GTK 主题 ──'):
            self.assertIn(section, out)
        for label in ('gsettings', 'gtk-3.0', 'gtk-4.0', 'gtk-2.0',
                      'qt5ct', 'qt6ct', 'fuzzel', 'xsettingsd', 'rofi'):
            self.assertIn(label, out)
        self.assertIn('matugen 的 [templates.gtk-folder]', out)

    def test_consistent(self) -> None:
        for rel, key in (('.config/gtk-3.0/settings.ini', 'gtk-icon-theme-name'),
                         ('.config/gtk-4.0/settings.ini', 'gtk-icon-theme-name'),
                         ('.config/qt5ct/qt5ct.conf', 'icon_theme'),
                         ('.config/qt6ct/qt6ct.conf', 'icon_theme')):
            self.write(rel, f'[Settings]\n{key}=Paper\n')
        self.write('.config/fuzzel/fuzzel.ini', 'icon-theme=Paper\n')
        self.write('.config/xsettingsd/xsettingsd.conf', 'Net/IconThemeName "Paper"\n')
        self.write('.config/rofi/themes/icons.rasi', '* {\n  icon-theme: "Paper";\n}\n')
        self.write('.gtkrc-2.0', 'gtk-icon-theme-name="Paper"\n')
        _, out = self.run_theme(gsettings={'org.gnome.desktop.interface.icon-theme': 'Paper'})
        self.assertIn('一致：Paper', out)
        self.assertNotIn('不一致', out)

    def test_inconsistent_lists_both(self) -> None:
        self.write('.config/gtk-3.0/settings.ini', 'gtk-icon-theme-name=Paper\n')
        self.write('.config/gtk-4.0/settings.ini', 'gtk-icon-theme-name=WhiteSur\n')
        _, out = self.run_theme(gsettings={'org.gnome.desktop.interface.icon-theme': 'Paper'})
        self.assertIn('不一致：Paper / WhiteSur', out)

    def test_nothing_set(self) -> None:
        _, out = self.run_theme()
        self.assertIn('没有任何一处设置了主题', out)

    def test_missing_file_marker(self) -> None:
        _, out = self.run_theme()
        # 一个 sink 文件都不存在时，该行显示「无此文件」而不是留空
        self.assertIn('无此文件', out)

    def test_gtkrc_quotes_stripped(self) -> None:
        self.write('.gtkrc-2.0', 'gtk-icon-theme-name="Quoted"\n')
        _, out = self.run_theme(gsettings={'org.gnome.desktop.interface.icon-theme': 'Quoted'})
        self.assertIn('一致：Quoted', out)
        self.assertNotIn('"Quoted"', out)

    def test_byte_padding_matches_bash(self) -> None:
        """bash 的 `printf %-22s` 是 C 语义按字节补位，中文标签「一致性」9 字节
        —— 用 Python 的 `:<22`（按字符）会少补 6 格，整行输出就对不上了。

        行形状：2 空格 + 标签补到 22 字节 + 1 空格 + 值，即值从第 25 字节开始。
        """
        _, out = self.run_theme()
        line = next((ln for ln in out.splitlines() if ln.startswith('  一致性')), None)
        self.assertIsNotNone(line, '没找到「一致性」行')
        raw = line.encode()
        self.assertEqual(raw[:2], b'  ')
        tail = raw[25:].decode()
        # 三种取值都要落在同一列上
        self.assertTrue(tail.startswith(('一致：', '不一致：', '没有任何一处设置了主题')),
                        f'值未从第 25 字节开始：{tail!r}')

    def test_self_name_and_unknown_option(self) -> None:
        os.environ['DOTCTL_SELF'] = '/opt/x/install.sh'
        self.addCleanup(os.environ.pop, 'DOTCTL_SELF', None)
        rc, out = self.run_theme(['-h'])
        self.assertEqual(rc, 0)
        self.assertIn('用法：/opt/x/install.sh theme', out)

        rc, out = self.run_theme(['--bogus'])
        self.assertEqual(rc, 2)
        self.assertIn('theme 不接受参数：--bogus', out)


if __name__ == '__main__':
    unittest.main()
