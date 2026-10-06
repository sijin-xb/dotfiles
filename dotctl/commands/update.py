"""update：增量升级 —— 只做文件层同步，不重装包、不重拉底盘。

与 install 的边界：install 管「装包 → 拉底盘 → 编插件 → 部署」，重跑要几分钟，
而且会把本地对上游底盘的改动冲掉。update 只管文件层，默认连仓库都不拉。

几处必须与 bash 版一致的地方：
  · 没有旧清单时走「首次升级」安全分支：目标已存在且与源不同的文件**不覆盖**，
    列出来让用户决定（本机实测：盲覆盖会把 live 里带修复的文件退回旧版）
  · 删除项一律移到备份，不 rm
  · 只有真落盘的文件才进清单（被忽略清单 skip/keep 的不进，否则下次会被误判
    「已删除」）
  · --dry-run 承诺一个字节都不写
"""
from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path

from .. import bashsrc, deploy, paths, prompt, snapshot, ui

PRE_UPDATE_PREFIX = 'pre-update'
MAX_LIST = 8


def _help() -> str:
    return bashsrc.help_text()


def _now_ts() -> str:
    return time.strftime('%Y%m%d-%H%M%S')


def _git(*args: str) -> str:
    try:
        proc = subprocess.run(['git', '-C', str(paths.repo()), *args],
                              capture_output=True, text=True, check=False)
    except OSError:
        return ''
    return proc.stdout.strip() if proc.returncode == 0 else ''


def _print_list(label: str, items: list[str], suffix: str = '') -> None:
    """打印一组明细（仅用于 local_modified / removed / conflicts）。

    ⚠ bash 只在**非空**时打印明细，且 `新增` / `更新` 两行**不列明细**
    （只有计数）—— 明细留给「本地改过」与「删除」这两类，因为那才是用户
    需要逐个确认的。多列会让输出与迁移前不一致（实测 diff 会指出来）。
    """
    if not items:
        return
    for rel in items[:MAX_LIST]:
        print(f'      {rel}')
    if len(items) > MAX_LIST:
        print(f'      …还有 {len(items) - MAX_LIST} 个')


def _load_session() -> tuple[str, str]:
    """会话：优先环境变量，其次沿用上次记录（与 bash 版一致，且要显式提示）。"""
    from .. import state
    shell, comp = state.session_from_env() if _env_session_set() else ('', '')
    if shell:
        return shell, comp
    saved = state.resolve_session()
    if saved[0] and saved[0] != 'unknown':
        print(f'    沿用上次的会话：{saved[0]} + {saved[1]}'
              f'（要换：SESSION=dms {paths.self_name()} update）')
        return saved
    return saved


def _env_session_set() -> bool:
    return bool(os.environ.get('SESSION') or os.environ.get('QS_SHELL'))


def _classify(plan_rels: list[str], plan_srcs: list[Path],
              old: dict[str, str], had_manifest: bool, prune: bool,
              home: Path) -> dict[str, list[str]]:
    """把计划分成 新增 / 更新 / 本地改过 / 冲突 / 删除。"""
    added: list[str] = []
    changed: list[str] = []
    local_modified: list[str] = []
    conflicts: list[str] = []

    for rel, src in zip(plan_rels, plan_srcs):
        src_fp = deploy.fingerprint(src)
        if rel not in old:
            target = home / rel
            if target.exists() and deploy.fingerprint(target) != src_fp:
                # 首次升级的安全网：分不清「上次部署的旧版」还是「用户自己的文件」
                conflicts.append(rel)
            else:
                added.append(rel)
        elif old[rel] != src_fp:
            changed.append(rel)
            if deploy.fingerprint(home / rel) != old[rel]:
                local_modified.append(rel)

    removed: list[str] = []
    if had_manifest and prune:
        newset = set(plan_rels)
        removed = [rel for rel in old if rel not in newset]
    return {'added': added, 'changed': changed, 'local_modified': local_modified,
            'conflicts': conflicts, 'removed': removed}


def _with_packages(shell: str, comp: str) -> None:
    """--with-packages：只补装缺失的包，不卸载、不升级。"""
    ui.say('补齐依赖包（--with-packages）')

    pacman: list[str] = []
    for kind in ('pacman', 'fonts-pacman'):
        pacman += bashsrc.packages(kind)
    if shutil.which('pacman'):
        proc = subprocess.run(['sudo', 'pacman', '-S', '--needed', '--noconfirm', *pacman],
                              check=False)
        if proc.returncode == 0:
            print(f'    官方仓库包已就绪（{len(pacman)} 个）')
        else:
            ui.warn('部分 pacman 包安装失败，可稍后手动重跑（不影响文件部署）')

    for pkg in bashsrc.packages('aur') + bashsrc.packages('fonts-aur'):
        if not pkg:
            continue
        if subprocess.run(['pacman', '-Q', pkg], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, check=False).returncode == 0:
            print(f'    已安装: {pkg}')
            continue
        try:
            ok = bashsrc.call_streaming('aur_install', pkg)
        except Exception:                       # noqa: BLE001
            ok = False
        if ok:
            print(f'    AUR 安装成功: {pkg}')
        else:
            ui.warn(f'{pkg} 安装失败（可稍后手动安装）')
    print('    注意：update 只补装，不卸载、不升级已装的包。')


def run(argv: list[str]) -> int:
    dry_run = with_packages = force = assume_yes = pull = False
    prune = True

    while argv:
        arg = argv.pop(0)
        if arg in ('--dry-run', '-n'):
            dry_run = True
        elif arg == '--with-packages':
            with_packages = True
        elif arg == '--force':
            force = True
        elif arg == '--no-prune':
            prune = False
        elif arg == '--pull':
            pull = True
        elif arg in ('--yes', '-y'):
            assume_yes = True
        elif arg in ('-h', '--help'):
            print(_help(), end='')
            return 0
        else:
            ui.die(f'update 不认识参数: {arg}\n'
                   '    支持：--dry-run / --with-packages / --force / --no-prune / --pull / --yes')
            return 1

    if not Path('/etc/arch-release').is_file():
        ui.die('本安装器仅支持 Arch Linux 系发行版（CachyOS / Arch 等）。')
        return 1
    if os.geteuid() == 0:
        ui.die('请勿用 root 运行（makepkg/AUR 步骤需要普通用户）。')
        return 1

    # 单文件自举：没有源树就算不出计划。bash 版这里会 clone 仓库再 exec 重跑，
    # 迁移期仍交给 bash 侧的 ensure_repo（它会 exec，不会返回）。
    bashsrc.call_streaming('ensure_repo')

    if dry_run:
        ui.warn('--dry-run：不会写任何配置文件；但仓库源树仍是必需的（可能已 clone/拉取）。')
    else:
        bashsrc.call('dotctl_ensure_frozen_dirs')
    bashsrc.call_streaming('session_warning_if_running')

    if pull:
        if (paths.repo() / '.git').is_dir():
            ui.say('拉取仓库最新提交（--pull）')
            if _git('pull', '--ff-only') == '' and subprocess.run(
                    ['git', '-C', str(paths.repo()), 'pull', '--ff-only'],
                    check=False).returncode != 0:
                ui.die('git pull 失败（有本地未提交改动或不是 fast-forward）。先手动处理再重试。')
                return 1
        else:
            ui.warn(f'--pull 指定了但 {paths.repo()} 不是 git 仓库，跳过')

    shell, comp = _load_session()
    if not shell:
        # 迁移期仍由 bash 侧交互选会话
        bashsrc.call_streaming('choose_session')
        shell, comp = _load_session()
    if not shell:
        ui.die('没能确定会话（QS_SHELL 为空）。用 SESSION=end4pc|caelestia|dms 指定。')
        return 1

    old_rev = ''
    rev_file = deploy.revision_path()
    if rev_file.is_file():
        for line in rev_file.read_text().splitlines():
            if line.startswith('revision='):
                old_rev = line[len('revision='):]
                break
    new_rev = _git('rev-parse', '--short', 'HEAD') or 'unknown'
    dirty = len(_git('status', '--porcelain').splitlines())

    print('-' * 70)
    print(f'  部署会话 : {shell} + {comp}')
    print(f'  上次部署 : {old_rev or "（无记录，按首次升级处理）"}')
    if dirty > 0:
        print(f'  仓库当前 : {new_rev}  （工作区 {dirty} 处未提交改动）')
    else:
        print(f'  仓库当前 : {new_rev}')
    if old_rev and old_rev == new_rev and not force and dirty == 0:
        print('  状态     : 没有新提交 —— 仍会按清单核一遍文件（要跳过请 Ctrl-C）')
    print('-' * 70)

    old = deploy.manifest_read()
    had_manifest = bool(old)
    plan_rels, plan_srcs = deploy.collect_plan()
    groups = _classify(plan_rels, plan_srcs, old, had_manifest, prune, paths.home())

    print()
    print(f'  将部署 {len(plan_rels)} 个文件')
    if not had_manifest:
        print('  · 没有旧清单（首次升级）→ 全部按新增处理，本次不做删除清理')
    # 间距与后缀照抄 bash 的 printf：'  · 新增   %d'（三个空格）
    print(f'  · 新增   {len(groups["added"])}')
    print(f'  · 更新   {len(groups["changed"])}')
    if groups['local_modified']:
        print(f'  · 其中 {len(groups["local_modified"])} 个你在本地改过（会先备份再覆盖）：')
        _print_list('', groups['local_modified'])
    if prune:
        print(f'  · 删除   {len(groups["removed"])}（移到备份，不直接 rm）')
        _print_list('', groups['removed'])

    skip_deploy: set[str] = set()
    if groups['conflicts']:
        if force:
            print()
            ui.warn(f'以下 {len(groups["conflicts"])} 个文件目标已存在且与仓库版本不同，'
                    '--force 已指定 → 会被仓库版本覆盖（覆盖前备份）')
            for rel in groups['conflicts'][:MAX_LIST]:
                print(f'      {rel}')
        else:
            print()
            ui.warn(f'以下 {len(groups["conflicts"])} 个文件目标已存在且与仓库版本不同，'
                    '本次**不动**它们')
            for rel in groups['conflicts'][:MAX_LIST]:
                print(f'      {rel}')
            print('    没有旧清单时无法判断这是「上次部署的旧版」还是「你自己的文件」。')
            print('    · 想让仓库版本覆盖它们：加 --force')
            print('    · 想保留本地版本并让仓库跟上：先 ./sync.sh <对应文件> 再跑 update')
            skip_deploy = set(groups['conflicts'])
    print()

    if dry_run:
        ui.say('--dry-run：以上只是计划，没有写入任何文件。')
        return 0

    if not assume_yes and prompt.confirm('确认执行以上变更？') != 0:
        ui.say('已取消，未做任何改动。')
        return 1

    ui.say('创建升级前快照（失败时可用 rollback 还原）')
    if not snapshot.snapshot_current(PRE_UPDATE_PREFIX, 'before-update'):
        if not assume_yes:
            if prompt.confirm('快照创建失败，仍要继续？') != 0:
                ui.say('已取消。')
                return 1
        else:
            ui.warn('快照创建失败，继续（无法用 rollback 还原本次升级）')

    if with_packages:
        _with_packages(shell, comp)

    backup_dir = paths.backup_root() / f'update-{_now_ts()}'
    installed = backed = ignored = skipped_conflict = 0
    deployed: list[str] = []

    rows = deploy.walk_sources()
    # 会话过滤：与 install 同样，一次问完 bash（见 deploy.session_skip_set）
    skip_rels = deploy.session_skip_set([r for _s, _d, r, _a in rows])
    for src, dst, rel, attrs in rows:
        if rel in skip_rels:
            continue
        target_rel = deploy._rel_from_home(dst)
        if target_rel in skip_deploy:
            skipped_conflict += 1
            continue
        before = (ignored, backed)
        result, _ = deploy.deploy_one_file(src, str(Path(dst).parent), Path(dst).name,
                                           attrs, backup_dir=str(backup_dir))
        if result == 'same':
            pass
        elif result == 'skip':
            ignored += 1
            continue
        if result == 'backup':
            backed += 1
        # 只有真落盘（或内容一致）的才进清单 —— 被忽略清单挡掉的不进，
        # 否则下次 update 会拿它去比「已删除」。
        deployed.append(target_rel)
        installed += 1

    ui.say(f'已部署 {installed} 个文件；{backed} 个有差异的旧文件备份于 {backup_dir}')
    bashsrc.call_streaming('sync_wallpapers')
    if skipped_conflict:
        ui.say(f'另有 {skipped_conflict} 个冲突文件按计划跳过（见上面的清单）')

    if prune and groups['removed']:
        n = 0
        for rel in groups['removed']:
            target = paths.home() / rel
            if not target.exists():
                continue
            dest = backup_dir / 'removed' / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            try:
                target.rename(dest)
                n += 1
            except OSError:
                pass
        ui.say(f'已移走 {n} 个仓库中已删除的文件（备份在 {backup_dir}/removed/，没有 rm）')

    deploy.manifest_write(deployed)
    bashsrc.call('record_revision')
    ui.say(f'清单已更新：{deploy.manifest_path()}')
    ui.say(f'版本已记录：{_git("rev-parse", "--short", "HEAD") or "unknown"}（{deploy.revision_path()}）')

    _qml_check(shell)

    print()
    print('-' * 70)
    print('  升级完成。')
    print(f'  出问题就回滚：{paths.self_name()} rollback')
    print(f'  回滚后再想回到升级后的状态：{paths.self_name()} restore')
    print('-' * 70)
    print('  注：包 / 上游底盘 / Caelestia 插件不在 update 范围内。')
    print(f'      需要时重跑 {paths.self_name()} install（--with-packages 只补装缺失的依赖）。')
    return 0


def _qml_check(shell: str) -> None:
    """QML 模块自检。与 install 的 [7/7] 同一段逻辑。

    update 也必须跑：升级会带进**新的 QML 文件**，可能 import 了机器上还没有
    的 Qt 模块 —— 缺了照样是「组件静默消失、日志只有一行 WARN」。
    """
    checker = paths.repo() / 'check-qml-deps.py'
    if shell == 'dms' or not checker.is_file():
        return
    if not shutil.which('python3'):
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
