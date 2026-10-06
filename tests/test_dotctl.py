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
from dotctl.commands import status  # noqa: E402


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


if __name__ == '__main__':
    unittest.main()
