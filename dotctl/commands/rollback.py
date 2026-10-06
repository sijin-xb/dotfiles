"""rollback / restore：从快照还原 $HOME（有副作用）。

这两个命令会**真的覆盖** $HOME 下的文件，所以几处细节必须与 bash 版一致：
  · 覆盖前先把「当前状态」存成 pre-rollback 快照，否则 restore 没得回
  · 确认处的三种结果（确认 / 取消 / 返回）对应不同退出码与文案
  · 取消（答 n）时退出码是 1 且**一个字节都不写**
  · 快照里没有的文件不删 —— tar 解包只覆盖，不清理
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from .. import bashsrc, paths, prompt, snapshot, ui

PRE_ROLLBACK_PREFIX = 'pre-rollback'


def _help() -> str:
    """rollback / restore 的 -h 都打印**完整**帮助（与 bash 版一致）。

    文本取自 bash 侧同一份 print_help：它还被 update / archive / uninstall
    与主分发用着，搬到 Python 会立刻产生两份会漂移的文案。
    """
    return bashsrc.help_text()


def _reject_args(cmd: str, argv: list[str]) -> int | None:
    """统一的参数处理：认 -h，其余只告警不报错（与 bash 版一致）。

    返回 None 表示继续执行；返回 int 表示直接以该码结束。
    """
    if argv and argv[0] in ('-h', '--help'):
        print(_help(), end='')
        return 0
    if argv:
        ui.warn(f'{cmd} 不接受参数，已忽略: {" ".join(argv)}')
    return None


def _count_files(snap: Path) -> int:
    """快照内文件数（不含目录项）—— bash 是 `tar -tzf | grep -v '/$' | wc -l`。"""
    try:
        proc = subprocess.run(['tar', '-tzf', str(snap)], capture_output=True,
                              text=True, check=False)
    except OSError:
        return 0
    if proc.returncode != 0:
        return 0
    return sum(1 for line in proc.stdout.splitlines() if line and not line.endswith('/'))


def _apply(key: str) -> int:
    """把 state/<key> 指向的快照解到 $HOME。返回 0 / 1（2 = 用户按 b，见下）。

    对应 bash 的 apply_snapshot_from_state。

    ⚠ 提示语固定是 [y/N]，**没有** b(返回) 选项 —— 这是复刻 bash 的**实际**
    行为，不是漏了功能。bash 那两个调用点传的是字面量 "allow_back"，而函数里
    的判断是 `[[ "$allow_back" == "back" ]]`，永远不成立，于是永远走 else 分支
    用两选项的 confirm；confirm 里 b 又要 allow_back 非空才返回 2 —— 两条都
    堵着，back 分支是死代码。
    迁移目标是行为一致，所以照抄现状。要真正启用 b 得单独提一个改动，把 bash
    侧的调用点与判断一起改掉。
    """
    snap = snapshot.read_state(key)
    if snap is None:
        ui.warn(f'找不到可用的快照（state/{key} 丢失或快照文件不存在）')
        return 1

    nfiles = _count_files(snap)
    snapshot.session_warning_if_running()
    print('-' * 70)
    print(f'  快照文件 : {snap.name}')
    print(f'  创建时间 : {_mtime(snap)}')
    print(f'  覆盖目标 : {paths.home()}（只覆盖快照内包含的约 {nfiles} 个文件，'
          f'不会删除快照外的文件）')
    print('-' * 70)

    rc = prompt.confirm(f'确认从该快照覆盖写入 {paths.home()}？')
    if rc == 2:
        return 2
    if rc != 0:
        return 1

    ui.say(f'开始提取 {snap.name} ...')
    try:
        proc = subprocess.run(['tar', '--numeric-owner', '-pzxf', str(snap),
                               '-C', str(paths.home())], check=False)
    except OSError as exc:
        ui.warn(f'提取失败：{exc}')
        return 1
    if proc.returncode != 0:
        return 1
    ui.say(f'已提取完成（约 {nfiles} 个文件）')
    return 0


def _mtime(path: Path) -> str:
    """`stat -c '%y'` 的形状；取不到时 bash 打的是 unknown。"""
    try:
        proc = subprocess.run(['stat', '-c', '%y', str(path)],
                              capture_output=True, text=True, check=False)
    except OSError:
        return 'unknown'
    out = proc.stdout.strip()
    return out if out else 'unknown'


def _finish(rc: int, fail_msg: str) -> int:
    """确认/提取的三种结果 → 文案与退出码（与 bash 版逐字对齐）。"""
    if rc == 2:
        ui.say('已取消，返回。')
        return 0
    if rc != 0:
        ui.die(fail_msg)
        return 1
    return 0


def rollback(argv: list[str]) -> int:
    early = _reject_args('rollback', argv)
    if early is not None:
        return early

    snapshot.ensure_dirs()
    if snapshot.read_state('current') is None:
        ui.die('还没有 pre-install 快照，请先至少运行一次 ./install.sh install 来生成回档基线。')
        return 1

    ui.say('回档：先保存当前 rice 状态（restore 功能要用到）...')
    if not snapshot.snapshot_current(PRE_ROLLBACK_PREFIX, 'before-rollback'):
        ui.warn('pre-rollback 快照失败，restore 将不可用')

    rc = _apply('current')
    out = _finish(rc, '回档失败，见上方输出。')
    if out != 0:
        return out
    if rc == 0:
        # ⚠ 这里写死 ./install.sh 是**照抄 bash 版**：那一行是硬编码字面量，
        #   不是 $0（同一函数里的 die 提示也写死了同一个路径）。
        #   换成 paths.self_name() 反而会让输出与迁移前不一致。
        ui.say('回档完成。如果想再回到回档之前的 rice 状态，运行：./install.sh restore')
    return 0


def restore(argv: list[str]) -> int:
    early = _reject_args('restore', argv)
    if early is not None:
        return early

    snapshot.ensure_dirs()
    if snapshot.read_state('before-rollback') is None:
        ui.die('没有找到 pre-rollback 快照：还没执行过 rollback？或者快照文件已被手动删除？'
               '（不执行任何文件操作，退出）')
        return 1

    rc = _apply('before-rollback')
    out = _finish(rc, '恢复失败，见上方输出。')
    if out != 0:
        return out
    if rc == 0:
        ui.say('恢复完成：配置已还原为回档前的 rice 状态。')
    return 0
