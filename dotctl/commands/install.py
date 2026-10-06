"""install：完整安装（7 步）。

分工：**编排与文件层在 Python，外部流程经 bashsrc 调**。
  · 纯文件逻辑（[0/7] 快照、[5/7] 部署、清单与版本写回）在 Python 里做 ——
    这部分可测，也是迁移的价值所在
  · 装包（pacman / AUR）、clone 上游底盘、cmake 编译 Caelestia 插件、venv
    这些以「调外部命令」为主的段落留在 bash（lib/15-python.sh 末尾），
    Python 负责按顺序调用并处理结果 —— 包一层 bash 不算没迁，把它们重写成
    Python 只会把同样的 subprocess 调用再抄一遍

⚠ 与 update 的关键差异：install 会**重装包、重拉上游底盘、重编插件**，重跑要
  几分钟，且会把本地对上游底盘的改动冲掉。日常升级用 update。
"""
from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

from .. import bashsrc, deploy, paths, prompt, snapshot, ui

PRE_INSTALL_PREFIX = 'pre-install'


def _help() -> str:
    return bashsrc.help_text()


def _now_ts() -> str:
    return time.strftime('%Y%m%d-%H%M%S')


def _fonts_enabled() -> bool:
    return os.environ.get('FONTS', '1') == '1'


def _step(n: str, title: str) -> None:
    ui.say(f'[{n}/7] {title}')


def run(argv: list[str]) -> int:
    if argv:
        ui.warn(f'install 不接受参数，已忽略: {" ".join(argv)}'
                f'（选会话请用 SESSION=dms|caelestia|end4pc {paths.self_name()} install）')

    if not Path('/etc/arch-release').is_file():
        ui.die('本安装器仅支持 Arch Linux 系发行版（CachyOS / Arch 等）。')
        return 1
    if os.geteuid() == 0:
        ui.die('请勿用 root 运行（makepkg/AUR 步骤需要普通用户）。')
        return 1
    if not _which('pacman'):
        ui.die('找不到 pacman。')
        return 1

    # 单文件自举：没有源树就算不出计划。ensure_repo 会 clone 并 exec 重跑。
    bashsrc.call_streaming('ensure_repo')
    bashsrc.call('dotctl_ensure_frozen_dirs')
    bashsrc.call_streaming('session_warning_if_running')

    # ── [0/7] 安装前快照 ────────────────────────────────────────
    _step('0', '安装前自动保存当前配置快照（回档用）')
    if not snapshot.snapshot_current(PRE_INSTALL_PREFIX, 'current'):
        ui.warn('创建 pre-install 快照失败（可继续安装，但 rollback 将不可用）')

    # ── [1/7] 基础工具与会话依赖 ────────────────────────────────
    _step('1', '安装基础工具与会话依赖')
    # ⚠ 选会话的结果要回读：choose_session 设的是 bash 变量，Python 是独立
    #   进程看不到。dotctl_choose_session 在同一个 bash 进程里选完，把结果
    #   写到 stderr 供这里解析（stdout 留给交互提示）。
    _pick_session()
    bashsrc.call_streaming('choose_fonts')
    shell = _current_shell()
    comp = _current_compositor()

    pacman_pkgs = bashsrc.packages('pacman')
    print(f'==>     合成器相关包: {bashsrc.call("compositor_pkgs").strip()}')
    shell_pkgs = bashsrc.call('shell_pacman_pkgs').strip()
    if shell_pkgs:
        print(f'==>     {shell} 专属包: {shell_pkgs}')
    base_pkgs = bashsrc.call('base_pacman_pkgs').strip()
    if base_pkgs:
        print(f'==>     Caelestia 插件依赖: {base_pkgs}')
    if _fonts_enabled():
        pacman_pkgs += bashsrc.packages('fonts-pacman')
        print('==>     字体（pacman）: Nerd Mono / Noto CJK / 思源黑体')
    else:
        print('==>     字体: 已跳过（FONTS=0），不安装任何系统字体包')

    if os.environ.get('FULL_UPGRADE', '0') == '1':
        ui.say('    FULL_UPGRADE=1：执行全系统升级（pacman -Syu）')
        rc = _sudo(['pacman', '-Syu', '--needed', '--noconfirm', *pacman_pkgs])
        if rc != 0:
            ui.die('全系统升级失败。常见原因是镜像未同步或密钥过期：'
                   '先手动执行 sudo pacman -Syu && sudo pacman -S archlinux-keyring 后重试。')
            return 1
    else:
        rc = _sudo(['pacman', '-S', '--needed', '--noconfirm', *pacman_pkgs])
        if rc != 0:
            ui.die('依赖安装失败。若提示找不到包，先手动执行 sudo pacman -Syu 更新软件库后重试。')
            return 1

    # ── [2/7] AUR ───────────────────────────────────────────────
    _step('2', 'AUR 依赖')
    if not _which('yay') and not _which('paru'):
        ui.say('    未找到 AUR helper，引导安装 yay（编译约 1-2 分钟，需要 base-devel）')
        if not bashsrc.call_streaming('dotctl_bootstrap_yay'):
            ui.die('yay 编译/安装失败，见上方输出。手动装好 paru 或 yay 后重跑即可跳过本步。')
            return 1

    # ⚠ 顺序照抄 bash：fixed → 字体 → 合成器 → shell → base。
    #   packages('aur') 内部已经把 fixed + compositor + shell + base 串好了
    #   （见 lib/15-python.sh 的 deps_collect），所以字体要**插在中间**而不是
    #   追加在末尾 —— 直接 += 会让 libcava / qt6-m3shapes-git 落到最后，
    #   与迁移前的输出顺序不一致。
    aur_pkgs = bashsrc.packages('aur')
    if _fonts_enabled():
        fixed_aur = bashsrc.call('fixed_aur_pkgs').split()
        font_aur = bashsrc.packages('fonts-aur')
        aur_pkgs = fixed_aur + font_aur + [p for p in aur_pkgs if p not in fixed_aur]
        print('==>     字体（AUR）  : MiSans / Maple Mono NF / 霞鹜文楷三兄弟')
    for pkg in aur_pkgs:
        if not pkg:
            continue
        if subprocess.run(['pacman', '-Q', pkg], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, check=False).returncode == 0:
            print(f'    已安装: {pkg}')
            continue
        if bashsrc.call_streaming('aur_install', pkg):
            print(f'    AUR 安装成功: {pkg}')
        else:
            ui.warn(f'{pkg} 安装失败（可稍后手动安装）')

    # ── [3/7] quickshell ────────────────────────────────────────
    _step('3', 'quickshell')
    bashsrc.call_streaming('install_quickshell')
    if not _which('qs'):
        ui.die('quickshell 安装失败，请检查上方输出。')
        return 1

    # ── [4/7] 桌面 Shell ────────────────────────────────────────
    _step('4', f'桌面 Shell（{shell}）')
    # ⚠ 顺序：插件必须先于 shell 本体（end4-pC 的锁屏硬依赖它）。
    #   dms 不走 quickshell，跳过 —— 不给纯 niri 用户多拉一份 caelestia 源码。
    if shell != 'dms':
        bashsrc.call_streaming('install_caelestia_plugin')
    bashsrc.call_streaming('dotctl_install_shell', shell)

    # ── [5/7] 部署配置文件 ──────────────────────────────────────
    _step('5', '部署配置文件')
    backup_dir = paths.backup_root() / _now_ts()
    installed = backed = 0
    ignored_skip = ignored_keep = 0
    skipped = skipped_shell = 0
    deployed: list[str] = []

    rows = deploy.walk_sources()
    # 会话过滤：一次问完 bash（见 deploy.session_skip_set 的说明）
    skip_rels = deploy.session_skip_set([rel for _s, _d, rel, _a in rows])
    for src, dst, rel, attrs in rows:
        target_rel = deploy._rel_from_home(dst)
        if rel in skip_rels:
            # 合成器 / shell 维度的跳过分别计数（bash 是两个计数器）
            if rel.startswith('dot_config/hypr/') or rel.startswith('dot_config/niri/'):
                skipped += 1
            else:
                skipped_shell += 1
            continue
        result, _ = deploy.deploy_one_file(src, str(Path(dst).parent), Path(dst).name,
                                           attrs, backup_dir=str(backup_dir))
        if result == 'skip':
            ignored_skip += 1
            continue
        if result == 'keep':
            ignored_keep += 1
            continue
        if result == 'backup':
            backed += 1
        deployed.append(target_rel)
        installed += 1

    ui.say(f'已部署 {installed} 个文件；{backed} 个有差异的旧文件备份于 {backup_dir}')
    bashsrc.call_streaming('sync_wallpapers')
    deploy.manifest_write(deployed)
    bashsrc.call('record_revision')
    print(f'    部署清单: {deploy.manifest_path()}（{len(deployed)} 条）')
    if ignored_skip or ignored_keep:
        print(f'    按 .chezmoiignore 跳过 {ignored_skip} 个（缓存/字节码/插件元数据/UI 写回的配置）；')
        print(f'    {ignored_keep} 个运行时生成物已存在，保留当前值不覆盖（matugen 配色等）。')
        print('    想强制用仓库快照覆盖它们：先删掉目标文件再重跑安装。')
    if skipped:
        other = 'hypr' if comp == 'niri' else 'niri'
        ui.warn(f'已跳过 {skipped} 个文件：未选择的另一套合成器 ~/.config/{other} 原样保留，一个字节都没动。')
        ui.warn(f'  想两套都部署：INSTALL_BOTH_COMPOSITORS=1 {paths.self_name()} install')
    if skipped_shell:
        ui.warn(f'已跳过 {skipped_shell} 个文件：不属于所选 shell（{shell}）的差异层原样保留。')

    # ── [6/7] 运行环境与歌词缓存 ────────────────────────────────
    _step('6', '运行环境与歌词缓存')
    bashsrc.call_streaming('dotctl_setup_runtime', '1' if _fonts_enabled() else '0')
    # ⚠ QML 自检**不要**在这里再调一次：它属于 [6/7] 尾部，已随
    #   dotctl_setup_runtime 一起抽到 bash 侧（那边就是原 cmd_install 的
    #   那段代码）。第一版两边都跑，于是「QML 模块依赖自检：齐全」打了两遍。

    # ── [7/7] 收尾 ──────────────────────────────────────────────
    _step('7', '完成！接下来的步骤：')
    bashsrc.call_streaming('dotctl_install_outro')
    return 0


def _pick_session() -> None:
    """跑 choose_session 并把结果写回 os.environ。

    ⚠ 必须在同一个 bash 进程里完成「选 + 输出」，见 lib/15-python.sh 的
    dotctl_choose_session：choose_session 设的是 bash 变量，而 dotctl 是独立
    进程，分两次调的话第二次看不到第一次设的值。

    交互提示走 stdout（原样转发给用户，与 bash 版一致），结果走 stderr 的
    DOTCTL_SESSION= 行 —— 两者分流才能既保留提示又拿到值。
    """
    if os.environ.get('QS_SHELL'):
        bashsrc.call_streaming('choose_session')       # 已预设，函数直接返回
        return
    proc = subprocess.run(
        ['bash', '-c', bashsrc._LOADER, 'dotctl-bashsrc', str(paths.repo()),
         'dotctl_choose_session'],
        capture_output=True, text=True, check=False)
    sys.stdout.write(proc.stdout)
    sys.stdout.flush()
    for line in proc.stderr.splitlines():
        if line.startswith('DOTCTL_SESSION='):
            value = line[len('DOTCTL_SESSION='):]
            shell, _, comp = value.partition('|')
            os.environ['QS_SHELL'] = shell
            os.environ['COMPOSITOR'] = comp


def _which(name: str) -> bool:
    import shutil
    return shutil.which(name) is not None


def _sudo(args: list[str]) -> int:
    """sudo 前缀可被 SUDO 覆盖（bash 侧是 "${SUDO:-sudo}"，dryrun 测试台靠它）。"""
    prefix = os.environ.get('SUDO', 'sudo').split()
    try:
        return subprocess.run([*prefix, *args], check=False).returncode
    except OSError:
        return 1


def _current_shell() -> str:
    return os.environ.get('QS_SHELL', '')


def _current_compositor() -> str:
    return os.environ.get('COMPOSITOR', '')


def _qml_check(shell: str) -> None:
    """QML 模块依赖自检（与 update 的收尾同一段逻辑）。"""
    checker = paths.repo() / 'check-qml-deps.py'
    if shell == 'dms' or not checker.is_file() or not _which('python3'):
        return
    proc = subprocess.run(['python3', str(checker), '--quiet'],
                          capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        print()
        ui.warn('QML 模块依赖不全 —— 下面这些组件启动后会静默消失（不会报错）')
        print((proc.stdout + proc.stderr).rstrip())
        print()
        ui.warn(f'补齐办法：{paths.self_name()} update --with-packages，'
                f'或手动跑：{checker}')
    else:
        print('    QML 模块依赖自检：齐全')
