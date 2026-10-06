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
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from dotctl import paths, state  # noqa: E402
from dotctl import prompt  # noqa: E402
from dotctl import deploy, prompt, snapshot, tmpfiles  # noqa: E402
from dotctl.commands import (archive, clean, deps, doctor, rollback,  # noqa: E402
                             status, theme, uninstall, update)


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



class TestClean(TempHome):
    """clean 会真删东西，所以测试重点在「该删的删、不该删的不删」，
    以及「非交互下不误删」这条安全保证。"""

    def make_snapshots(self, count: int) -> list[Path]:
        snaps = paths.snap_root()
        snaps.mkdir(parents=True, exist_ok=True)
        made = []
        for i in range(count):
            path = snaps / f'snap-{i}.tar.gz'
            path.write_bytes(b'x' * 8)
            os.utime(path, (1_700_000_000 + i * 60, 1_700_000_000 + i * 60))
            made.append(path)
        return made

    def run_clean(self, argv: list[str], answer: str = 'y') -> tuple[int, str]:
        out = io.StringIO()
        with mock.patch.object(prompt, 'read_answer', return_value=answer):
            with redirect_stdout(out):
                rc = clean.run(list(argv))
        return rc, out.getvalue()

    def test_nothing_to_clean(self) -> None:
        os.environ['TMPDIR'] = str(self.home / 'empty-tmp')
        (self.home / 'empty-tmp').mkdir()
        self.addCleanup(os.environ.pop, 'TMPDIR', None)
        rc, out = self.run_clean([])
        self.assertEqual(rc, 0)
        self.assertIn('没有需要清理的东西', out)

    def test_dry_run_deletes_nothing(self) -> None:
        snaps = self.make_snapshots(5)
        rc, out = self.run_clean(['--snapshots', '2', '--dry-run'])
        self.assertEqual(rc, 0)
        self.assertIn('--dry-run：什么都没删', out)
        self.assertEqual(len(list(paths.snap_root().glob('*.tar.gz'))), 5)

    def test_snapshots_keeps_newest(self) -> None:
        self.make_snapshots(5)
        rc, _ = self.run_clean(['--snapshots', '2'])
        self.assertEqual(rc, 0)
        left = sorted(p.name for p in paths.snap_root().glob('*.tar.gz'))
        self.assertEqual(left, ['snap-3.tar.gz', 'snap-4.tar.gz'])

    def test_default_does_not_touch_snapshots(self) -> None:
        """默认行为绝不能碰快照/备份 —— 那是 rollback 的退路。"""
        self.make_snapshots(3)
        updates = paths.backup_root() / 'update-20260101-000000'
        updates.mkdir(parents=True)
        (self.home / 'empty-tmp').mkdir()
        os.environ['TMPDIR'] = str(self.home / 'empty-tmp')
        self.addCleanup(os.environ.pop, 'TMPDIR', None)
        self.run_clean([])
        self.assertEqual(len(list(paths.snap_root().glob('*.tar.gz'))), 3)
        self.assertTrue(updates.is_dir())

    def test_own_tmpdir_is_skipped(self) -> None:
        """当前运行自己的 TMPRUN 不能被删 —— 删了本次运行的 mktemp 全失效。"""
        tmp = self.home / 'tmp'
        own = tmp / 'dotfiles-install.999'
        other = tmp / 'dotfiles-install.111'
        own.mkdir(parents=True)
        other.mkdir()
        os.environ['TMPDIR'] = str(tmp)
        os.environ['TMPRUN'] = str(own)
        self.addCleanup(os.environ.pop, 'TMPDIR', None)
        self.addCleanup(os.environ.pop, 'TMPRUN', None)
        rc, _ = self.run_clean([])
        self.assertEqual(rc, 0)
        self.assertTrue(own.is_dir(), '自己的 run 目录被误删')
        self.assertFalse(other.exists(), '别人的残留没删掉')

    def test_declined_confirmation_deletes_nothing(self) -> None:
        self.make_snapshots(5)
        rc, _ = self.run_clean(['--snapshots', '2'], answer='n')
        self.assertEqual(rc, 1)
        self.assertEqual(len(list(paths.snap_root().glob('*.tar.gz'))), 5)

    def test_eof_defaults_to_no(self) -> None:
        """非交互且 EOF：confirm 必须返回「否」—— 这条保证以前在 bash 的
        read_answer 里，现在复刻到 dotctl/prompt.py。"""
        snaps = self.make_snapshots(5)
        out = io.StringIO()
        with mock.patch.object(prompt, 'read_answer', return_value=''):
            with redirect_stdout(out):
                rc = clean.run(['--snapshots', '2'])
        self.assertEqual(rc, 1)
        self.assertTrue(all(p.exists() for p in snaps))

    def test_unknown_option(self) -> None:
        rc, out = self.run_clean(['--bogus'])
        self.assertEqual(rc, 2)
        self.assertIn('clean: 未知选项 --bogus', out)

    def test_self_name_in_help(self) -> None:
        os.environ['DOTCTL_SELF'] = '/opt/x/install.sh'
        self.addCleanup(os.environ.pop, 'DOTCTL_SELF', None)
        out = io.StringIO()
        with redirect_stdout(out):
            rc = clean.run(['-h'])
        self.assertEqual(rc, 0)
        self.assertIn('用法：/opt/x/install.sh clean', out.getvalue())


class TestPrompt(TempHome):
    """confirm 的语义对齐（不依赖真实 stdin）。"""

    def test_yes_variants(self) -> None:
        for answer in ('y', 'Y', 'yes', 'YES', 'Yes'):
            with mock.patch.object(prompt, 'read_answer', return_value=answer):
                out = io.StringIO()
                with redirect_stdout(out):
                    self.assertEqual(prompt.confirm('确认？'), 0)

    def test_no_is_default(self) -> None:
        for answer in ('', 'n', 'whatever'):
            with mock.patch.object(prompt, 'read_answer', return_value=answer):
                out = io.StringIO()
                with redirect_stdout(out):
                    self.assertEqual(prompt.confirm('确认？'), 1)

    def test_back_only_with_allow_back(self) -> None:
        with mock.patch.object(prompt, 'read_answer', return_value='b'):
            out = io.StringIO()
            with redirect_stdout(out):
                self.assertEqual(prompt.confirm('确认？', allow_back=True), 2)
        with mock.patch.object(prompt, 'read_answer', return_value='b'):
            out = io.StringIO()
            with redirect_stdout(out):
                self.assertEqual(prompt.confirm('确认？'), 1)

    def test_prompt_shape(self) -> None:
        with mock.patch.object(prompt, 'read_answer', return_value='n'):
            out = io.StringIO()
            with redirect_stdout(out):
                prompt.confirm('确认删除以上 3 项？')
        self.assertIn('确认删除以上 3 项？ [y/N] ', out.getvalue())
        with mock.patch.object(prompt, 'read_answer', return_value='n'):
            out = io.StringIO()
            with redirect_stdout(out):
                prompt.confirm('确认？', allow_back=True)
        self.assertIn('[y/N/b(返回)]', out.getvalue())



class TestDoctor(TempHome):
    """doctor 读真实系统（发行版、工具链、包），所以断言钉在**结构**上：
    六段标题、符号、退出码语义。逐字一致性由 /tmp 的迁移前后对照负责。"""

    def setUp(self) -> None:
        super().setUp()
        # 真实的 ~/.local/state 是存在的；临时 HOME 里得自己造，否则
        # 「备份目录可写」那一段会因为父目录都不存在而判成失败。
        (paths.home() / '.local/state').mkdir(parents=True, exist_ok=True)

    def run_doctor(self, argv: list[str] | None = None) -> tuple[int, str]:
        out = io.StringIO()
        # 只把依赖检查挡掉。**不要**全局 mock shutil.which —— 那会让 QML
        # 自检以为 python3 存在，于是真的去跑 check-qml-deps.py，在临时
        # HOME 下必然失败，用例就测不到排版了。
        def fake_which(name: str) -> str:
            # 工具链那一段要看到 pacman 存在（否则判「pacman 缺失」→ 退出码 1）。
            # 「有没有装包」由 _installed 控制，与 which 无关。
            return f'/usr/bin/{name}'

        with mock.patch.object(doctor, '_installed', return_value=True), \
             mock.patch.object(doctor.bashsrc, 'packages', return_value=[]), \
             mock.patch('shutil.which', side_effect=fake_which):
            with redirect_stdout(out):
                rc = doctor.run(list(argv or []))
        return rc, out.getvalue()

    def test_six_sections(self) -> None:
        rc, out = self.run_doctor()
        self.assertEqual(rc, 0)
        for head in ('── 系统 ──', '── 工具链 ──', '── 依赖包缺口 ──',
                     '── QML 模块自检 ──', '── 备份目录 ──', '── 结论 ──'):
            self.assertIn(head, out)
        self.assertIn('── 会话（end4pc', out)

    def test_all_clean_message(self) -> None:
        rc, out = self.run_doctor()
        self.assertEqual(rc, 0)
        # 临时 HOME 里没有已部署的配置，所以会有「需要注意」项；
        # 「一切正常」只在零警告零失败时出现，这里不该期待它。
        self.assertIn('0 项必须处理。', out)
        self.assertIn('✓', out)
        self.assertNotIn('✗', out)

    def test_missing_packages_warns_but_returns_zero(self) -> None:
        """缺包只是「需要注意」，不该让退出码变 1 —— 只有必须处理的项才返回 1。"""
        out = io.StringIO()
        def fake_which(name: str) -> str:
            # 工具链那一段要看到 pacman 存在（否则判「pacman 缺失」→ 退出码 1）。
            # 「有没有装包」由 _installed 控制，与 which 无关。
            return f'/usr/bin/{name}'

        def fake_packages(kind: str) -> list[str]:
            return ['pkg-a', 'pkg-b'] if kind == 'pacman' else []

        with mock.patch.object(doctor, '_installed', return_value=False), \
             mock.patch.object(doctor.bashsrc, 'packages', side_effect=fake_packages), \
             mock.patch('shutil.which', side_effect=fake_which):
            with redirect_stdout(out):
                rc = doctor.run([])
        self.assertEqual(rc, 0)
        self.assertIn('2 个包未安装：pkg-a pkg-b', out.getvalue())
        # 退出码 0 = 没有「必须处理」项；临时 HOME 下还会有「配置入口不存在」
        # 之类的「需要注意」项，所以只钉必须处理数为 0，不钉总数。
        self.assertIn('0 项必须处理。', out.getvalue())

    def test_non_arch_is_a_failure(self) -> None:
        out = io.StringIO()
        def fake_which(name: str) -> str:
            # 工具链那一段要看到 pacman 存在（否则判「pacman 缺失」→ 退出码 1）。
            # 「有没有装包」由 _installed 控制，与 which 无关。
            return f'/usr/bin/{name}'

        with mock.patch.object(doctor.Path, 'is_file', return_value=False), \
             mock.patch.object(doctor, '_installed', return_value=True), \
             mock.patch.object(doctor.bashsrc, 'packages', return_value=[]), \
             mock.patch('shutil.which', side_effect=fake_which):
            with redirect_stdout(out):
                rc = doctor.run([])
        self.assertEqual(rc, 1)
        self.assertIn('非 Arch 系', out.getvalue())

    def test_tilde_shortens_home(self) -> None:
        home = paths.home()
        self.assertEqual(doctor._tilde(home / '.config/hypr/hyprland.lua'),
                         '~/.config/hypr/hyprland.lua')
        # 不在 HOME 下的路径保持原样
        self.assertEqual(doctor._tilde(Path('/etc/arch-release')), '/etc/arch-release')

    def test_bash_version_from_env(self) -> None:
        os.environ['DOTCTL_BASH_VERSION'] = '9.9'
        self.addCleanup(os.environ.pop, 'DOTCTL_BASH_VERSION', None)
        _, out = self.run_doctor()
        self.assertIn('✓ bash 9.9', out)

    def test_bash_version_fallback(self) -> None:
        os.environ.pop('DOTCTL_BASH_VERSION', None)
        _, out = self.run_doctor()
        self.assertIn('bash 未知', out)

    def test_help_and_stray_args(self) -> None:
        rc, out = self.run_doctor(['-h'])
        self.assertEqual(rc, 0)
        self.assertIn('体检当前环境并打印缺口', out)

        rc, out = self.run_doctor(['--bogus'])
        self.assertEqual(rc, 2)
        self.assertIn('doctor 不接受参数：--bogus', out)

    def test_dms_skips_qml_check(self) -> None:
        self.write('.local/state/dotfiles-backup/state/deployed-session', 'dms|niri')
        _, out = self.run_doctor()
        self.assertIn('dms 会话不需要 QML 模块自检', out)
        self.assertIn('── 会话（dms', out)



class TestRollbackRestore(TempHome):
    """rollback / restore 会真的解 tar 到 $HOME。

    这里全部在临时 HOME 下跑，且把 `_apply` 里真正的 tar 提取替换掉 ——
    测的是**决策路径**（有没有快照、确认结果、先存 pre-rollback），
    真实提取由 /tmp 的隔离测试台负责（那边跑完整 CLI）。
    """

    def make_snapshot(self, key: str, name: str) -> Path:
        snap = paths.snap_root() / name
        snap.parent.mkdir(parents=True, exist_ok=True)
        snap.write_bytes(b'x' * 8)
        state = paths.state_dir()
        state.mkdir(parents=True, exist_ok=True)
        (state / key).write_text(str(snap) + '\n')
        return snap

    def run_cmd(self, func, argv: list[str], answer: str = 'n',
                snapshot_ok: bool = True) -> tuple[int, str, list[str]]:
        out, err = io.StringIO(), io.StringIO()
        calls: list[str] = []

        def fake_snap(prefix: str, state_key: str = '') -> bool:
            calls.append(f'snapshot:{prefix}:{state_key}')
            return snapshot_ok

        def fake_stream(func_name: str, *args: str) -> bool:
            calls.append(func_name)
            return True

        with mock.patch.object(snapshot, 'snapshot_current', side_effect=fake_snap), \
             mock.patch.object(snapshot, 'session_warning_if_running',
                               side_effect=lambda: calls.append('session_warning')), \
             mock.patch.object(rollback.bashsrc, 'call_streaming', side_effect=fake_stream), \
             mock.patch.object(prompt, 'read_answer', return_value=answer), \
             mock.patch.object(rollback, '_count_files', return_value=3):
            # ui.die 写 stderr（与 bash 的 die 一致），所以两个流都要接
            with redirect_stdout(out), redirect_stderr(err):
                # ui.die 走 SystemExit（与 bash 的 die 一样是「直接结束」），
                # 统一在这里收成退出码，用例不必各自 try。
                try:
                    rc = func(list(argv))
                except SystemExit as exc:
                    rc = int(exc.code or 0)
        return rc, out.getvalue() + err.getvalue(), calls

    def test_rollback_without_snapshot_dies(self) -> None:
        rc, out, calls = self.run_cmd(rollback.rollback, [])
        self.assertEqual(rc, 1)
        self.assertIn('还没有 pre-install 快照', out)
        # 没有快照时不该先去存 pre-rollback
        self.assertNotIn('snapshot:pre-rollback:before-rollback', calls)

    def test_restore_without_snapshot_dies(self) -> None:
        rc, out, _ = self.run_cmd(rollback.restore, [])
        self.assertEqual(rc, 1)
        self.assertIn('没有找到 pre-rollback 快照', out)

    def test_rollback_saves_pre_rollback_first(self) -> None:
        """回档前必须先存 pre-rollback 快照 —— 否则 restore 没得回。"""
        self.make_snapshot('current', 'pre-install-20260101.tar.gz')
        rc, out, calls = self.run_cmd(rollback.rollback, [], answer='n')
        self.assertEqual(rc, 1)                     # 答 n → 取消
        self.assertIn('snapshot:pre-rollback:before-rollback', calls)
        self.assertIn('回档：先保存当前 rice 状态', out)

    def test_declined_writes_nothing(self) -> None:
        """答 n 时不能动任何文件 —— 提取那一步不该发生。"""
        self.make_snapshot('current', 'pre-install-20260101.tar.gz')
        with mock.patch.object(rollback.subprocess, 'run') as run_mock:
            run_mock.return_value = mock.Mock(returncode=0)
            rc, _, _ = self.run_cmd(rollback.rollback, [], answer='n')
        self.assertEqual(rc, 1)
        for call in run_mock.call_args_list:
            self.assertNotIn('-pzxf', call[0][0],
                             f'取消后仍执行了提取：{call[0][0]}')

    def test_confirmed_rollback_extracts(self) -> None:
        self.make_snapshot('current', 'pre-install-20260101.tar.gz')
        with mock.patch.object(rollback.subprocess, 'run') as run_mock:
            run_mock.return_value = mock.Mock(returncode=0)
            rc, out, _ = self.run_cmd(rollback.rollback, [], answer='y')
        self.assertEqual(rc, 0)
        self.assertIn('已提取完成', out)
        self.assertIn('./install.sh restore', out)
        extract = [c for c in run_mock.call_args_list
                   if '-pzxf' in c[0][0]]
        self.assertEqual(len(extract), 1)

    def test_snapshot_failure_is_warned_not_fatal(self) -> None:
        self.make_snapshot('current', 'pre-install-20260101.tar.gz')
        _, out, _ = self.run_cmd(rollback.rollback, [], answer='n', snapshot_ok=False)
        self.assertIn('pre-rollback 快照失败，restore 将不可用', out)

    def test_restore_uses_before_rollback(self) -> None:
        self.make_snapshot('before-rollback', 'pre-rollback-20260101.tar.gz')
        with mock.patch.object(rollback.subprocess, 'run') as run_mock:
            run_mock.return_value = mock.Mock(returncode=0)
            rc, out, _ = self.run_cmd(rollback.restore, [], answer='y')
        self.assertEqual(rc, 0)
        self.assertIn('恢复完成：配置已还原为回档前的 rice 状态。', out)

    def test_help_prints_full_help(self) -> None:
        for func in (rollback.rollback, rollback.restore):
            out = io.StringIO()
            with mock.patch.object(rollback.bashsrc, 'help_text',
                                   return_value='FULL-HELP\n'):
                with redirect_stdout(out):
                    rc = func(['-h'])
            self.assertEqual(rc, 0)
            self.assertEqual(out.getvalue(), 'FULL-HELP\n')

    def test_stray_args_warn_but_continue(self) -> None:
        """多余参数只告警不报错（与 bash 版一致），继续往下走。"""
        self.make_snapshot('current', 'pre-install-20260101.tar.gz')
        rc, out, calls = self.run_cmd(rollback.rollback, ['--dry-run'], answer='n')
        self.assertIn('rollback 不接受参数，已忽略: --dry-run', out)
        # 告警之后照常执行：仍然存了 pre-rollback 快照
        self.assertIn('snapshot:pre-rollback:before-rollback', calls)
        self.assertEqual(rc, 1)          # 最后答 n → 取消


class TestSnapshotState(TempHome):
    """snapshot.read_state 的语义：state 文件与快照文件缺一不可。"""

    def test_both_present(self) -> None:
        snap = paths.snap_root() / 'a.tar.gz'
        snap.parent.mkdir(parents=True)
        snap.write_bytes(b'x')
        state = paths.state_dir()
        state.mkdir(parents=True)
        (state / 'current').write_text(str(snap) + '\n')
        self.assertEqual(snapshot.read_state('current'), snap)

    def test_state_file_missing(self) -> None:
        self.assertIsNone(snapshot.read_state('current'))

    def test_snapshot_file_missing(self) -> None:
        """state 文件在、但它指向的快照被删了 → 也算读不到。"""
        state = paths.state_dir()
        state.mkdir(parents=True)
        (state / 'current').write_text(str(paths.snap_root() / 'gone.tar.gz') + '\n')
        self.assertIsNone(snapshot.read_state('current'))

    def test_empty_state_file(self) -> None:
        state = paths.state_dir()
        state.mkdir(parents=True)
        (state / 'current').write_text('\n')
        self.assertIsNone(snapshot.read_state('current'))



class TestArchive(TempHome):
    """archive 的返回码语义是重点：2 = 用户取消，1 = 真的失败。

    cmd_uninstall 靠这个区分 —— 混淆会让用户以为已有备份就去删文件。
    """

    def setUp(self) -> None:
        super().setUp()
        self.write('.config/kitty/kitty.conf', 'x\n')
        self.out = self.home / 'out.tar.gz'

    def run_archive(self, argv: list[str], answer: str = 'y',
                    paths_list: list[str] | None = None) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        rows = paths_list if paths_list is not None else ['.config/kitty']
        with mock.patch.object(archive.bashsrc, 'call', return_value='\n'.join(rows)), \
             mock.patch.object(archive.bashsrc, 'call_streaming', return_value=True), \
             mock.patch.object(archive.prompt, 'read_answer', return_value=answer), \
             mock.patch.object(archive, '_run_tar', return_value=True), \
             mock.patch.object(archive.fsutil, 'du', return_value='4.0K'):
            with redirect_stdout(out), redirect_stderr(err):
                try:
                    rc = archive.run(list(argv))
                except SystemExit as exc:
                    rc = int(exc.code or 0)
        return rc, out.getvalue() + err.getvalue()

    def test_cancel_returns_2_not_1(self) -> None:
        rc, out = self.run_archive(['-o', str(self.out)], answer='n')
        self.assertEqual(rc, 2, '取消必须返回 2，否则 uninstall 会当成「存档失败」')
        self.assertIn('已取消打包，未写入任何文件。', out)
        self.assertFalse(self.out.exists())

    def test_no_paths_returns_1(self) -> None:
        rc, out = self.run_archive(['-o', str(self.out)], paths_list=[])
        self.assertEqual(rc, 1)
        self.assertIn('没有可打包的 rice 相关文件', out)

    def test_success_returns_0(self) -> None:
        rc, out = self.run_archive(['-o', str(self.out)])
        self.assertEqual(rc, 0)
        self.assertIn('打包完成', out)

    def test_missing_output_dir(self) -> None:
        rc, out = self.run_archive(['-o', str(self.home / 'nope/out.tar.gz')])
        self.assertEqual(rc, 1)
        self.assertIn('输出目录不存在', out)

    def test_dash_o_without_value(self) -> None:
        rc, out = self.run_archive(['-o'])
        self.assertEqual(rc, 1)
        self.assertIn('archive: -o 需要一个输出路径参数', out)

    def test_unknown_arg_warns_but_continues(self) -> None:
        rc, out = self.run_archive(['--bogus', '-o', str(self.out)])
        self.assertIn('archive 未知参数: --bogus（已忽略）', out)
        self.assertEqual(rc, 0)

    def test_plan_marks_present_and_missing(self) -> None:
        _, out = self.run_archive(['-o', str(self.out)],
                                  paths_list=['.config/kitty', '.config/nvim'])
        # 色码夹在符号两侧（硬编码的，见下一条测试），所以断言带上它们
        self.assertIn('\033[1;32m✓\033[0m ~/.config/kitty', out)
        self.assertIn('\033[1;33m·\033[0m ~/.config/nvim （缺失，跳过）', out)

    def test_plan_always_colored(self) -> None:
        """计划清单的色码是硬编码的（照抄 bash）—— 管道下也带 ANSI。

        与 ui.GREEN 的「非终端就关色」不同，这是 bash 侧的不一致，迁移期
        照抄；这条测试把现状钉住，将来修的时候会立刻发现。
        """
        _, out = self.run_archive(['-o', str(self.out)],
                                  paths_list=['.config/kitty'])
        self.assertIn('\033[1;32m✓\033[0m', out)


class TestTmpfiles(TempHome):
    """临时文件落在 $TMPRUN 里 —— tests 的 SIGINT 那节靠这个可观察副作用。"""

    def test_mktmpd_creates_run_dir(self) -> None:
        run = self.home / 'run'
        os.environ['TMPRUN'] = str(run)
        self.addCleanup(os.environ.pop, 'TMPRUN', None)
        made = tmpfiles.mktmpd()
        self.assertTrue(run.is_dir(), 'TMPRUN 目录没被建出来')
        self.assertEqual(made.parent, run)

    def test_mktmp_creates_run_dir(self) -> None:
        run = self.home / 'run2'
        os.environ['TMPRUN'] = str(run)
        self.addCleanup(os.environ.pop, 'TMPRUN', None)
        made = tmpfiles.mktmp()
        self.assertTrue(run.is_dir())
        self.assertTrue(made.is_file())

    def test_fallback_without_tmp_run(self) -> None:
        os.environ.pop('TMPRUN', None)
        os.environ['TMPDIR'] = str(self.home / 'tmp')
        self.addCleanup(os.environ.pop, 'TMPDIR', None)
        made = tmpfiles.mktmpd()
        self.assertIn('dotfiles-install.', str(made))

    def test_cleanup_removes_tree(self) -> None:
        os.environ['TMPRUN'] = str(self.home / 'run3')
        self.addCleanup(os.environ.pop, 'TMPRUN', None)
        made = tmpfiles.mktmpd()
        (made / 'inner.txt').write_text('x')
        tmpfiles.cleanup(made)
        self.assertFalse(made.exists())
        tmpfiles.cleanup(made)          # 再删一次不应抛异常


class TestFrozenPaths(TempHome):
    """路径常量优先用 bash 传下来的冻结值。

    bash 的 BACKUP_ROOT / SNAP_ROOT / STATE_DIR 是 source 时算好的，不随
    $HOME 变；Python 若总是动态推，会在「改 HOME 再调函数」时分叉。
    """

    def test_frozen_values_win(self) -> None:
        frozen = self.home / 'frozen-backup'
        os.environ['DOTCTL_BACKUP_ROOT'] = str(frozen)
        os.environ['DOTCTL_SNAP_ROOT'] = str(frozen / 'snap')
        os.environ['DOTCTL_STATE_DIR'] = str(frozen / 'state')
        for key in ('DOTCTL_BACKUP_ROOT', 'DOTCTL_SNAP_ROOT', 'DOTCTL_STATE_DIR'):
            self.addCleanup(os.environ.pop, key, None)
        self.assertEqual(paths.backup_root(), frozen)
        self.assertEqual(paths.snap_root(), frozen / 'snap')
        self.assertEqual(paths.state_dir(), frozen / 'state')

    def test_fallback_to_home(self) -> None:
        for key in ('DOTCTL_BACKUP_ROOT', 'DOTCTL_SNAP_ROOT', 'DOTCTL_STATE_DIR'):
            os.environ.pop(key, None)
        self.assertEqual(paths.backup_root(),
                         paths.home() / '.local/state/dotfiles-backup')



class TestUninstall(TempHome):
    """uninstall 是唯一会递归删 $HOME 下路径的命令，测试重点全在边界上：
    只删清单里的项、按会话过滤、任一确认答 n 都不删、区分两种失败。
    """

    def setUp(self) -> None:
        super().setUp()
        for rel in ('.config/kitty/kitty.conf', '.config/fish/config.fish',
                    '.config/hypr/hyprland.lua', '.config/quickshell/end4-pC/shell.qml',
                    '.config/quickshell/caelestia/shell.qml'):
            self.write(rel, 'x\n')
        self.write('unrelated.txt', 'keep\n')

    def run_uninstall(self, answers: list[str], plan: list[str] | None = None,
                      archive_rc: int = 0, argv: list[str] | None = None,
                      extra: str = '') -> tuple[int, str]:
        """answers 依次喂给每次 confirm；plan 是 bash 侧返回的删除清单；
        extra 是 dotctl_extra_paths 的输出（EXTRA_ARCHIVE_PATHS）。"""
        out, err = io.StringIO(), io.StringIO()
        rows = plan if plan is not None else ['.config/kitty']
        pending = list(answers)

        def fake_answer(*_a, **_k) -> str:
            return pending.pop(0) if pending else ''

        def fake_stream(func_name: str, *args: str) -> bool:
            # dotctl_uninstall_plan 把清单写进 $1 指向的文件
            if func_name == 'dotctl_uninstall_plan' and args:
                Path(args[0]).write_text('SCOPE=end4-pC|hyprland|0\n' + '\n'.join(rows) + '\n')
            return True

        with mock.patch.object(uninstall.prompt, 'read_answer', side_effect=fake_answer), \
             mock.patch.object(uninstall.bashsrc, 'call_streaming', side_effect=fake_stream), \
             mock.patch.object(uninstall.bashsrc, 'call', return_value=extra), \
             mock.patch.object(uninstall, '_read_plan',
                               return_value=('end4-pC|hyprland|0', list(rows))), \
             mock.patch.object(archive, 'run', return_value=archive_rc):
            with redirect_stdout(out), redirect_stderr(err):
                try:
                    rc = uninstall.run(list(argv or []))
                except SystemExit as exc:
                    rc = int(exc.code or 0)
        return rc, out.getvalue() + err.getvalue()

    def test_declined_delete_removes_nothing(self) -> None:
        rc, out = self.run_uninstall(['n', 'n'], plan=['.config/kitty'])
        self.assertEqual(rc, 0)
        self.assertTrue((paths.home() / '.config/kitty/kitty.conf').exists())
        self.assertNotIn('已删除', out)

    def test_confirmed_deletes_only_plan_entries(self) -> None:
        rc, out = self.run_uninstall(['n', 'y'], plan=['.config/kitty'])
        self.assertEqual(rc, 0)
        self.assertIn('已删除 ~/.config/kitty', out)
        # 清单外的文件绝不能碰
        self.assertTrue((paths.home() / '.config/fish/config.fish').exists())
        self.assertTrue((paths.home() / 'unrelated.txt').exists())

    def test_session_filter_keeps_other_shell(self) -> None:
        """只删 end4-pC 时，caelestia 必须留着。"""
        rc, _ = self.run_uninstall(['n', 'y'],
                                   plan=['.config/quickshell/end4-pC'])
        self.assertEqual(rc, 0)
        self.assertFalse((paths.home() / '.config/quickshell/end4-pC').exists())
        self.assertTrue((paths.home() / '.config/quickshell/caelestia').exists())

    def test_missing_entries_are_skipped_silently(self) -> None:
        rc, out = self.run_uninstall(['n', 'y'],
                                     plan=['.config/nvim', '.config/kitty'])
        self.assertEqual(rc, 0)
        self.assertNotIn('已删除 ~/.config/nvim', out)
        self.assertIn('已删除 ~/.config/kitty', out)

    def test_archive_refused_asks_again(self) -> None:
        """用户在打包确认处按 n（arc_rc=2）→ 必须再问一次，不能直接删。"""
        rc, out = self.run_uninstall(['y', 'n'], archive_rc=2)
        self.assertEqual(rc, 0)
        self.assertIn('你取消了存档 —— 本次卸载**没有备份**。', out)
        self.assertIn('已中止，未删除任何文件。', out)
        self.assertTrue((paths.home() / '.config/kitty/kitty.conf').exists())

    def test_archive_refused_but_user_continues(self) -> None:
        rc, out = self.run_uninstall(['y', 'y', 'y'], archive_rc=2,
                                     plan=['.config/kitty'])
        self.assertEqual(rc, 0)
        self.assertIn('已删除 ~/.config/kitty', out)

    def test_archive_failure_only_warns(self) -> None:
        """arc_rc=1（真的失败）只告警，不重复确认。"""
        rc, out = self.run_uninstall(['y', 'y'], archive_rc=1, plan=['.config/kitty'])
        self.assertEqual(rc, 0)
        self.assertIn('存档失败，将继续执行卸载（无备份）', out)
        self.assertIn('已删除 ~/.config/kitty', out)

    def test_extra_paths_are_also_removed(self) -> None:
        """EXTRA_ARCHIVE_PATHS（quickshell 状态等）也在删除范围内。"""
        self.write('.local/state/quickshell/x', 'q\n')
        rc, out = self.run_uninstall(['n', 'y'], plan=['.config/kitty'],
                                     extra='.local/state/quickshell')
        self.assertEqual(rc, 0)
        self.assertFalse((paths.home() / '.local/state/quickshell').exists())

    def test_help_and_stray_args(self) -> None:
        with mock.patch.object(uninstall.bashsrc, 'help_text', return_value='H\n'):
            out = io.StringIO()
            with redirect_stdout(out):
                rc = uninstall.run(['-h'])
        self.assertEqual(rc, 0)
        self.assertEqual(out.getvalue(), 'H\n')

        _, out = self.run_uninstall(['n', 'n'], argv=['--bogus'])
        self.assertIn('uninstall 不接受参数，已忽略: --bogus', out)


class TestPromptUnbuffered(TempHome):
    """read_answer 必须逐字节读，不能预读缓冲。

    用 readline() 会把管道里剩下的答案一次读进用户态缓冲，之后 fork 出去的
    bash 子进程只剩 EOF —— uninstall 实测踩到（shell 范围恒为默认值）。
    """

    def _feed(self, data: bytes, reads: int) -> list[str]:
        r, w = os.pipe()
        os.write(w, data)
        os.close(w)
        old = os.dup(0)
        os.dup2(r, 0)
        try:
            out = []
            with mock.patch.object(prompt.sys.stdin, 'isatty', return_value=True):
                for _ in range(reads):
                    out.append(prompt.read_answer())
        finally:
            os.dup2(old, 0)
            os.close(old)
            os.close(r)
        return out

    def test_sequential_reads_see_all_lines(self) -> None:
        got = self._feed(b'first\nsecond\nthird\n', 3)
        self.assertEqual(got, ['first', 'second', 'third'])

    def test_child_process_can_still_read(self) -> None:
        """读完一行后，子进程仍应能读到下一行（这正是 uninstall 的场景）。"""
        r, w = os.pipe()
        os.write(w, b'python-line\nbash-line\n')
        os.close(w)
        old = os.dup(0)
        os.dup2(r, 0)
        try:
            with mock.patch.object(prompt.sys.stdin, 'isatty', return_value=True):
                first = prompt.read_answer()
            proc = subprocess.run(['bash', '-c', 'read -r x; echo "$x"'],
                                  capture_output=True, text=True)
        finally:
            os.dup2(old, 0)
            os.close(old)
            os.close(r)
        self.assertEqual(first, 'python-line')
        self.assertEqual(proc.stdout.strip(), 'bash-line',
                         'bash 子进程读不到第二行 —— read_answer 预读了缓冲')



class TestChezmoiIgnore(TempHome):
    """忽略清单判定的纯逻辑测试。

    ⚠ 有一组用例是「拿真实 .chezmoiignore 的每条模式去探」—— 那正是发现
    `case` 的 glob 里 `*` 会跨 `/` 的方式（我原先按段比较，107 条里错 1 条）。
    真实清单会演进，所以这里对**模式形状**断言，不写死具体路径。
    """

    def write_ignore(self, body: str) -> Path:
        """写到临时 HOME 下的文件，**绝不碰仓库里真实的 .chezmoiignore**。

        ⚠ 第一版直接写 paths.repo()/'.chezmoiignore'，把仓库的忽略清单覆盖成
        三行玩具内容，害得 install-sh-behaviour-test.sh 的 G 组整组失败
        （它读的是真实清单）。测试污染仓库是硬错误，改成写临时文件。
        """
        path = self.home / 'chezmoiignore-test'
        path.write_text(body)
        return path

    def test_missing_file_returns_empty(self) -> None:
        with mock.patch.object(deploy, 'ignore_file', return_value=self.home / 'nope'):
            self.assertEqual(deploy.parse_ignore(), [])
            self.assertEqual(deploy.ignore_kind('.config/x'), '')

    def test_comments_and_blanks_stripped(self) -> None:
        path = self.write_ignore('# 注释\n\n  .config/a  # 尾注\n\t.config/b\t\n')
        with mock.patch.object(deploy, 'ignore_file', return_value=path):
            self.assertEqual(deploy.parse_ignore(), ['.config/a', '.config/b'])

    def test_directory_prefix(self) -> None:
        """目录模式是**前缀**匹配，且带尾斜杠 —— 所以 `.config/x` 本身不算命中
        （bash 是 `[[ $target == "$pat"* ]]`，'.config/x' 不以 '.config/x/' 开头）。"""
        with mock.patch.object(deploy, 'parse_ignore', return_value=['.config/x/']):
            self.assertEqual(deploy.ignore_kind('.config/x'), '')
            self.assertEqual(deploy.ignore_kind('.config/x/y'), 'skip')
            self.assertEqual(deploy.ignore_kind('.config/xy'), '')

    def test_double_star_matches_any_depth(self) -> None:
        with mock.patch.object(deploy, 'parse_ignore', return_value=['**/__pycache__']):
            self.assertEqual(deploy.ignore_kind('__pycache__'), 'skip')
            self.assertEqual(deploy.ignore_kind('a/__pycache__'), 'skip')
            self.assertEqual(deploy.ignore_kind('a/b/__pycache__'), 'skip')
            self.assertEqual(deploy.ignore_kind('a/__pycache__/x.pyc'), 'skip')
            self.assertEqual(deploy.ignore_kind('a/pycache'), '')

    def test_glob_star_crosses_slash(self) -> None:
        """bash 的 `case` glob 里 `*` 是跨 `/` 的（实测确认）。

        这是路径名展开与 case 的区别 —— 前者不跨 /，后者跨。
        """
        with mock.patch.object(deploy, 'parse_ignore',
                               return_value=['.config/niri/dms/*.bak*']):
            self.assertEqual(deploy.ignore_kind('.config/niri/dms/x.bak-1'), 'skip')
            self.assertEqual(deploy.ignore_kind('.config/niri/dms/a/b.baka/b'), 'skip')
            self.assertEqual(deploy.ignore_kind('.config/niri/dms/alttab.kdl'), '')

    def test_exact_match_is_keep_not_skip(self) -> None:
        """无通配的模式返回 keep（不是 skip）—— 两者在 deploy_one_file 里
        含义不同：keep = 该文件由仓库提供、不覆盖用户改动。"""
        with mock.patch.object(deploy, 'parse_ignore', return_value=['.config/mimeapps.list']):
            self.assertEqual(deploy.ignore_kind('.config/mimeapps.list'), 'keep')
            self.assertEqual(deploy.ignore_kind('.config/mimeapps.list/x'), '')

    def test_first_match_wins(self) -> None:
        with mock.patch.object(deploy, 'parse_ignore',
                               return_value=['.config/a', '.config/a/']):
            self.assertEqual(deploy.ignore_kind('.config/a'), 'keep')

    def test_never_touches_repo_ignore_file(self) -> None:
        """防回归：测试不得写仓库里真实的 .chezmoiignore。

        第一版 write_ignore 直接写它，把仓库清单覆盖成三行玩具内容，
        害得 install-sh-behaviour-test.sh 的 G 组整组失败。
        """
        real = paths.repo() / '.chezmoiignore'
        before = real.read_text()
        self.write_ignore('# 玩具\n.config/toy\n')
        with mock.patch.object(deploy, 'ignore_file',
                               return_value=self.home / 'chezmoiignore-test'):
            deploy.parse_ignore()
        self.assertEqual(real.read_text(), before, '仓库的 .chezmoiignore 被测试改动了')

    def test_real_ignore_file_has_no_surprises(self) -> None:
        """真实清单的每条模式都应能被判定，不抛异常。"""
        for pat in deploy.parse_ignore():
            probe = pat.rstrip('/').replace('**/', '').replace('*', 'X')
            if probe:
                deploy.ignore_kind(probe)      # 只要求不抛


class TestDeployMapping(TempHome):
    """chezmoi 前缀 → 目标路径的映射。"""

    def test_dot_prefix(self) -> None:
        self.assertEqual(deploy.map_target('dot_config/kitty/kitty.conf'),
                         ('.config/kitty/kitty.conf', mock.ANY))

    def test_non_dot_ignored(self) -> None:
        self.assertIsNone(deploy.map_target('lib/00-env.sh'))
        self.assertIsNone(deploy.map_target('README.md'))

    def test_executable_attribute(self) -> None:
        target, attrs = deploy.map_target('dot_config/fish/executable_config.fish')
        self.assertEqual(target, '.config/fish/config.fish')
        self.assertTrue(attrs['exec'])

    def test_private_attribute(self) -> None:
        target, attrs = deploy.map_target('dot_config/fcitx5/private_config')
        self.assertEqual(target, '.config/fcitx5/config')
        self.assertTrue(attrs['private'])

    def test_symlink_attribute(self) -> None:
        target, attrs = deploy.map_target('dot_config/systemd/user/symlink_mako.service')
        self.assertEqual(target, '.config/systemd/user/mako.service')
        self.assertTrue(attrs['symlink'])

    def test_stacked_attributes(self) -> None:
        target, attrs = deploy.map_target('dot_x/executable_private_y')
        self.assertEqual(target, '.x/y')
        self.assertTrue(attrs['exec'])
        self.assertTrue(attrs['private'])

    def test_walk_sources_only_dot_entries(self) -> None:
        rows = deploy.walk_sources()
        self.assertTrue(rows, '源树里应该有可部署条目')
        for _src, _dst, rel, _attrs in rows:
            self.assertTrue(rel.startswith('dot_'), rel)
            self.assertNotIn('/.git/', rel)


class TestDeployOneFile(TempHome):
    """落盘行为：幂等、备份、属性。"""

    def setUp(self) -> None:
        super().setUp()
        self.src = self.home / 'src-file'
        self.src.write_text('content\n')
        self.dstdir = str(self.home / 'target')

    def test_new_file(self) -> None:
        with mock.patch.object(deploy, 'ignore_kind', return_value=''):
            result, rel = deploy.deploy_one_file(self.src, self.dstdir, 'out.conf', {})
        self.assertEqual(result, 'new')
        self.assertEqual((Path(self.dstdir) / 'out.conf').read_text(), 'content\n')

    def test_identical_content_is_idempotent(self) -> None:
        dst = Path(self.dstdir) / 'out.conf'
        dst.parent.mkdir(parents=True)
        dst.write_text('content\n')
        before = dst.stat().st_mtime_ns
        with mock.patch.object(deploy, 'ignore_kind', return_value=''):
            result, _ = deploy.deploy_one_file(self.src, self.dstdir, 'out.conf', {})
        self.assertEqual(result, 'same')
        self.assertEqual(dst.stat().st_mtime_ns, before, '内容一致却改动了文件')

    def test_different_content_backs_up(self) -> None:
        dst = Path(self.dstdir) / 'out.conf'
        dst.parent.mkdir(parents=True)
        dst.write_text('old\n')
        backup = str(self.home / 'backup')
        with mock.patch.object(deploy, 'ignore_kind', return_value=''):
            result, _ = deploy.deploy_one_file(self.src, self.dstdir, 'out.conf', {},
                                               backup_dir=backup)
        self.assertEqual(result, 'backup')
        self.assertEqual(dst.read_text(), 'content\n')
        self.assertTrue((Path(backup) / _rel(dst)).exists(), '旧内容没被备份')

    def test_skip_by_ignore(self) -> None:
        with mock.patch.object(deploy, 'ignore_kind', return_value='skip'):
            result, _ = deploy.deploy_one_file(self.src, self.dstdir, 'out.conf', {})
        self.assertEqual(result, 'skip')
        self.assertFalse((Path(self.dstdir) / 'out.conf').exists())

    def test_executable_bit(self) -> None:
        with mock.patch.object(deploy, 'ignore_kind', return_value=''):
            deploy.deploy_one_file(self.src, self.dstdir, 'run.sh', {'exec': True})
        self.assertTrue(os.access(Path(self.dstdir) / 'run.sh', os.X_OK))

    def test_private_mode(self) -> None:
        with mock.patch.object(deploy, 'ignore_kind', return_value=''):
            deploy.deploy_one_file(self.src, self.dstdir, 'secret', {'private': True})
        self.assertEqual((Path(self.dstdir) / 'secret').stat().st_mode & 0o777, 0o600)

    def test_symlink_uses_file_content_as_target(self) -> None:
        self.src.write_text('/dev/null\n')
        with mock.patch.object(deploy, 'ignore_kind', return_value=''):
            result, _ = deploy.deploy_one_file(self.src, self.dstdir, 'mako.service',
                                               {'symlink': True})
        self.assertEqual(result, 'link')
        self.assertTrue((Path(self.dstdir) / 'mako.service').is_symlink())
        self.assertEqual(os.readlink(Path(self.dstdir) / 'mako.service'), '/dev/null')

    def test_fingerprint_uses_link_target(self) -> None:
        """符号链接记链接目标，不跟随 —— 跟随会把 /dev/null 的内容当指纹，
        改链接目标就检测不出来了。"""
        link = self.home / 'a-link'
        os.symlink('/dev/null', link)
        self.assertEqual(deploy.fingerprint(link), 'link:/dev/null')
        os.unlink(link)
        os.symlink('/dev/zero', link)
        self.assertEqual(deploy.fingerprint(link), 'link:/dev/zero')
        self.assertEqual(deploy.fingerprint(self.home / 'nope'), 'absent')


def _rel(path: Path) -> str:
    return str(path)[len(str(paths.home())) + 1:]



class TestUpdateClassify(TempHome):
    """update 的计划分类：新增 / 更新 / 冲突 / 删除。

    这里测的是**决策**，不跑真实部署 —— 那部分由 /tmp 的隔离 harness
    对跑完整 CLI 负责。
    """

    def src(self, name: str, body: str = 'x\n') -> Path:
        path = self.home / 'src' / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)
        return path

    def test_new_file_is_added(self) -> None:
        src = self.src('a.conf')
        groups = update._classify(['.config/a.conf'], [src], {}, False, True, paths.home())
        self.assertEqual(groups['added'], ['.config/a.conf'])
        self.assertEqual(groups['conflicts'], [])

    def test_existing_different_without_manifest_is_conflict(self) -> None:
        """首次升级的安全网：目标已存在且与源不同 → 不覆盖，列为冲突。

        本机实测过盲覆盖的代价 —— 会把 live 里带修复的文件退回仓库旧版。
        """
        src = self.src('a.conf', 'repo\n')
        self.write('.config/a.conf', 'local-fix\n')
        groups = update._classify(['.config/a.conf'], [src], {}, False, True, paths.home())
        self.assertEqual(groups['conflicts'], ['.config/a.conf'])
        self.assertEqual(groups['added'], [])

    def test_existing_identical_is_added(self) -> None:
        src = self.src('a.conf', 'same\n')
        self.write('.config/a.conf', 'same\n')
        groups = update._classify(['.config/a.conf'], [src], {}, False, True, paths.home())
        self.assertEqual(groups['added'], ['.config/a.conf'])
        self.assertEqual(groups['conflicts'], [])

    def test_changed_detected_by_fingerprint(self) -> None:
        src = self.src('a.conf', 'new\n')
        self.write('.config/a.conf', 'old\n')
        old = {'.config/a.conf': deploy.fingerprint(self.home / '.config/a.conf')}
        groups = update._classify(['.config/a.conf'], [src], old, True, True, paths.home())
        self.assertEqual(groups['changed'], ['.config/a.conf'])
        self.assertEqual(groups['local_modified'], [])

    def test_local_modification_flagged(self) -> None:
        """用户在本地改过（目标当前内容 != 部署时记下的）→ 单独列出。"""
        src = self.src('a.conf', 'new\n')
        self.write('.config/a.conf', 'user-edited\n')
        old = {'.config/a.conf': 'deadbeef'}          # 与目标当前指纹不同
        groups = update._classify(['.config/a.conf'], [src], old, True, True, paths.home())
        self.assertEqual(groups['changed'], ['.config/a.conf'])
        self.assertEqual(groups['local_modified'], ['.config/a.conf'])

    def test_removed_only_with_manifest_and_prune(self) -> None:
        src = self.src('a.conf')
        old = {'.config/gone.conf': 'x', '.config/a.conf': deploy.fingerprint(src)}
        groups = update._classify(['.config/a.conf'], [src], old, True, True, paths.home())
        self.assertEqual(groups['removed'], ['.config/gone.conf'])

        # 没有旧清单 → 不做删除清理（首次升级时 OLD_MANIFEST 是空的）
        groups = update._classify(['.config/a.conf'], [src], {}, False, True, paths.home())
        self.assertEqual(groups['removed'], [])

        # --no-prune → 也不删
        groups = update._classify(['.config/a.conf'], [src], old, True, False, paths.home())
        self.assertEqual(groups['removed'], [])


class TestUpdateRun(TempHome):
    """update 的参数处理与 --dry-run 的「不写任何东西」承诺。"""

    def setUp(self) -> None:
        super().setUp()
        # ⚠ 不要全局 mock Path.is_file —— 那会让「读 deployed-revision-*」也
        #   以为文件存在，然后 read_text 抛 FileNotFoundError（实测踩到）。
        #   /etc/arch-release 的检查改成精确 mock 那个具体路径。
        real_is_file = Path.is_file

        def fake_is_file(self) -> bool:                      # noqa: ANN001
            if str(self) == '/etc/arch-release':
                return True
            return real_is_file(self)

        patcher = mock.patch.object(Path, 'is_file', fake_is_file)
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_update(self, argv: list[str]) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(update.bashsrc, 'call', return_value=''), \
             mock.patch.object(update.bashsrc, 'call_streaming', return_value=True), \
             mock.patch.object(update, '_load_session', return_value=('end4-pC', 'hyprland')), \
             mock.patch.object(update.deploy, 'collect_plan', return_value=([], [])), \
             mock.patch.object(update.deploy, 'manifest_read', return_value={}), \
             mock.patch.object(update.deploy, 'revision_path',
                               return_value=self.home / 'nope'), \
             mock.patch.object(update, '_git', return_value='abc1234'):
            with redirect_stdout(out), redirect_stderr(err):
                try:
                    rc = update.run(list(argv))
                except SystemExit as exc:
                    rc = int(exc.code or 0)
        return rc, out.getvalue() + err.getvalue()

    def test_dry_run_writes_nothing(self) -> None:
        rc, out = self.run_update(['--dry-run'])
        self.assertEqual(rc, 0)
        self.assertIn('--dry-run：以上只是计划，没有写入任何文件。', out)
        # 不该建备份目录（bash 版的承诺：dry-run 一个字节都不写）
        self.assertFalse((paths.home() / '.local/state/dotfiles-backup/state').exists())

    def test_unknown_arg_dies(self) -> None:
        rc, out = self.run_update(['--bogus'])
        self.assertEqual(rc, 1)
        self.assertIn('update 不认识参数: --bogus', out)

    def test_help(self) -> None:
        with mock.patch.object(update.bashsrc, 'help_text', return_value='H\n'):
            rc, out = self.run_update(['-h'])
        self.assertEqual(rc, 0)
        self.assertEqual(out, 'H\n')

    def test_root_refused(self) -> None:
        with mock.patch.object(update.os, 'geteuid', return_value=0):
            rc, out = self.run_update(['--dry-run'])
        self.assertEqual(rc, 1)
        self.assertIn('请勿用 root 运行', out)

    def test_no_manifest_note(self) -> None:
        rc, out = self.run_update(['--dry-run'])
        self.assertIn('没有旧清单（首次升级）', out)


class TestUpdateWithPackages(TempHome):
    """--with-packages 必须包含字体包。

    ⚠ 这是修掉的一个 bash 既存 bug：原实现写 `(( fonts_enabled ))`，把**函数名**
    当算术变量求值 —— 永远失败且 set -u 报错中断，于是合成器 / shell / base
    包与整个 AUR 段都跑不到，字体包也永远补不上。install 用的是正确的
    `if fonts_enabled`，只有 update 有这个 bug。
    """

    def test_fonts_packages_included(self) -> None:
        seen: list[str] = []

        def fake_packages(kind: str) -> list[str]:
            seen.append(kind)
            return {'pacman': ['git'], 'fonts-pacman': ['noto-fonts'],
                    'aur': ['matugen'], 'fonts-aur': ['otf-misans']}[kind]

        with mock.patch.object(update.bashsrc, 'packages', side_effect=fake_packages), \
             mock.patch.object(update.bashsrc, 'call_streaming', return_value=True), \
             mock.patch('shutil.which', return_value='/usr/bin/pacman'), \
             mock.patch.object(update.subprocess, 'run') as run_mock:
            run_mock.return_value = mock.Mock(returncode=0)
            out = io.StringIO()
            with redirect_stdout(out):
                update._with_packages('end4-pC', 'hyprland')
        self.assertIn('fonts-pacman', seen, '字体包被漏掉了 —— 正是 bash 版的 bug')
        self.assertIn('fonts-aur', seen)
        self.assertIn('noto-fonts', ' '.join(run_mock.call_args_list[0][0][0]))


if __name__ == '__main__':
    unittest.main()
