"""部署核心：源树遍历、忽略清单判定、单条目落盘。

对应 lib/40-manifest.sh 的 walk_sources 与 lib/70-deploy.sh 的
chezmoi_ignore_kind / deploy_one_file。

⚠ 迁移期这里是**第二份实现**，不是包装 bash —— 与 deps_collect / snapshot
那类「bash 仍是唯一来源」的东西不同：部署逻辑是 install 与 update 的核心
路径，包一层 bash 等于没迁。所以必须在 Python 里真正重写，并用对照测试
（tests/test_dotctl.py 的 TestDeploy / TestChezmoiIgnore）钉住与 bash 一致。
"""
from __future__ import annotations

import fnmatch
import os
import re
import shutil
import subprocess
from pathlib import Path

# 仓库根下这些条目不部署（与 walk_sources 的 case 一致）
SKIP_TOP = {'install.sh', 'README.md', 'LICENSE', 'check-qml-deps.py'}

# chezmoi 前缀：目录用 dot_ 前缀映射到 $HOME 下的隐藏目录；
# 文件还有若干属性前缀，deploy_one_file 按顺序剥离。
DOT_PREFIX = 'dot_'

# ⚠ 只认这三个前缀 —— 与 lib/70-deploy.sh 一致。
#   `create_` **必须保持字面文件名**：chezmoi 的 create_ 语义是「不存在才创建」
#   并会剥前缀，但 hyprland/services/init.lua 里写的是
#   `require("hyprland/services/create_custom_config")`，剥成 custom_config.lua
#   反而 require 不到（.chezmoiignore 里记的就是这个冲突）。
#   第一版我把 create_ / empty_ / readonly_ 也列进来，于是
#   create_custom_config.lua 被剥成了 custom_config.lua —— dryrun 的
#   「create_custom_config 字面名」那条立刻抓到。
ATTR_PREFIXES = (
    ('executable_', 'exec'),
    ('private_', 'private'),
    ('symlink_', 'symlink'),
)


def repo_root() -> Path:
    from . import paths
    return paths.repo()


def ignore_file() -> Path:
    return repo_root() / '.chezmoiignore'


def parse_ignore() -> list[str]:
    """读 .chezmoiignore，去注释与首尾空白，丢掉空行。"""
    try:
        text = ignore_file().read_text(errors='replace')
    except OSError:
        return []
    patterns = []
    for line in text.splitlines():
        pat = line.split('#', 1)[0].strip()
        if pat:
            patterns.append(pat)
    return patterns


def ignore_kind(target: str) -> str:
    """判定 target（相对 $HOME 的路径）被忽略清单如何处理。

    返回 'skip' / 'keep' / ''（未命中）。
    与 bash 的 chezmoi_ignore_kind 逐分支对齐：
      · 以 / 结尾 → 目录前缀匹配
      · 含 **    → `**/X` 视为「任意深度的 X」
      · 含单个 * → 交给 shell case 的 glob（Python 侧用 fnmatch）
      · 其余     → 精确相等才算 keep
    """
    for pat in parse_ignore():
        if pat.endswith('/'):
            if target.startswith(pat):
                return 'skip'
            continue
        if '**' in pat:
            tail = pat.rsplit('**/', 1)[-1]
            if target == tail or target.endswith('/' + tail) or f'/{tail}/' in target:
                return 'skip'
            continue
        if '*' in pat:
            # bash 的 `case "$target" in $pat)` 是 shell glob：* 不跨 /。
            # fnmatch 的 * 会跨 /，所以逐段比较才能对齐。
            if _shell_glob_match(pat, target):
                return 'skip'
            continue
        if target == pat:
            return 'keep'
    return ''


def _shell_glob_match(pattern: str, target: str) -> bool:
    """shell case 的 glob 语义。

    ⚠ 一开始我以为 bash 的 `*` 不跨 `/`（那是**路径名展开**的规则），按段比较
    写，结果 107 条对照里有 1 条对不上：`.config/niri/dms/*.bak*` 在 bash 下
    能匹配 `.config/niri/dms/a/b.baka/b`。`case` 的 glob 与 fnmatch 一样，
    `*` 是「任意字符（含 /）」—— 实测确认后改回 fnmatchcase。

    ⚠ 必须用 fnmatchcase 而不是 fnmatch：后者会把两边都按 os.path.normcase
    处理，在大小写敏感的文件系统上引入多余的不确定性。
    """
    return fnmatch.fnmatchcase(target, pattern)


def split_attributes(rel: str) -> tuple[str, dict[str, bool], str]:
    """剥离 chezmoi 属性前缀。

    返回 (去掉前缀后的路径, 属性字典, 原始 rel)。属性可以叠加
    （如 executable_private_x），按 ATTR_PREFIXES 的顺序反复剥。
    """
    attrs = {name: False for _pfx, name in ATTR_PREFIXES}
    parts = rel.split('/')
    base = parts[-1]
    changed = True
    while changed:
        changed = False
        for prefix, name in ATTR_PREFIXES:
            if base.startswith(prefix):
                attrs[name] = True
                base = base[len(prefix):]
                changed = True
    parts[-1] = base
    return '/'.join(parts), attrs, rel


def map_target(rel: str) -> tuple[str, dict[str, bool]] | None:
    """源树相对路径 → (目标相对 $HOME 的路径, 属性)。

    只处理 dot_ 前缀；其余返回 None（= 不部署）。
    """
    if not rel.startswith(DOT_PREFIX):
        return None
    inner = rel[len(DOT_PREFIX):]
    mapped, attrs, _ = split_attributes(inner)
    return '.' + mapped, attrs


def session_skip_set(rels: list[str]) -> set[str]:
    """一次问 bash 哪些 rel 该按会话跳过。

    ⚠ 逐条调 skip_by_compositor / skip_by_shell 要 fork 上千次；而且那两个
    函数读的是 bash 变量（COMPOSITOR / QS_SHELL / INSTALL_BOTH_COMPOSITORS），
    Python 侧看不到 —— 只能在这边判。所以整份清单一次问完。
    """
    if not rels:
        return set()
    import subprocess
    from . import bashsrc
    proc = subprocess.run(
        ['bash', '-c', bashsrc._LOADER, 'dotctl-bashsrc', str(repo_root()),
         'dotctl_skip_rels'],
        input='\n'.join(rels) + '\n', capture_output=True, text=True, check=False)
    return {line for line in proc.stdout.splitlines() if line}


def walk_sources(skip_compositor=None, skip_shell=None) -> list[tuple[Path, str, str, dict[str, bool]]]:
    """遍历源树，产出待部署条目。

    返回 [(源文件绝对路径, 目标绝对路径, rel, 属性), ...]。
    skip_compositor / skip_shell 是可选回调，返回 True 表示跳过该 rel
    （对应 bash 的 skip_by_compositor / skip_by_shell）。
    """
    from . import paths
    root = repo_root()
    home = paths.home()
    out: list[tuple[Path, str, str, dict[str, bool]]] = []
    for dirpath, dirnames, filenames in os.walk(root):
        # 剪枝 .git（bash 用 -path ... -prune，同理：仓库的 .git 有几千个对象）
        dirnames[:] = [d for d in dirnames if d != '.git']
        for name in filenames:
            src = Path(dirpath) / name
            rel = str(src.relative_to(root))
            if rel in SKIP_TOP or rel.startswith('.git/'):
                continue
            mapped = map_target(rel)
            if mapped is None:
                continue
            target_rel, attrs = mapped
            if skip_compositor and skip_compositor(rel):
                continue
            if skip_shell and skip_shell(rel):
                continue
            out.append((src, str(home / target_rel), rel, attrs))
    out.sort(key=lambda row: row[2])
    return out


def fingerprint(path: Path) -> str:
    """内容指纹。符号链接记**链接目标**，不跟随 —— 与 bash 的 fingerprint 一致：
    systemd/user/symlink_mako.service 的内容是 /dev/null，跟随过去会变成
    「哈希 /dev/null」，改链接目标检测不出来。"""
    if path.is_symlink():
        try:
            return 'link:' + os.readlink(path)
        except OSError:
            return 'absent'
    if path.is_file():
        try:
            return subprocess.run(['sha256sum', str(path)], capture_output=True,
                                  text=True, check=False).stdout.split()[0]
        except (OSError, IndexError):
            return 'absent'
    return 'absent'


def deploy_one_file(src: Path, dst_dir: str, base: str, attrs: dict[str, bool],
                    backup_dir: str | None = None) -> tuple[str, str]:
    """落盘一个条目。返回 (结果, 说明)。

    结果取值：'new' 新建 / 'same' 内容一致跳过 / 'backup' 覆盖前备份了
    / 'link' 建了符号链接 / 'skip' 因忽略清单跳过。
    与 bash 的 deploy_one_file 对齐：内容一致就不动（幂等），有差异先备份。
    """
    target_rel = _rel_from_home(str(Path(dst_dir) / base))
    dst = Path(dst_dir) / base

    # ⚠ keep 分支必须在这里处理，不能只在 collect_plan 里判：install 直接调
    #   本函数，绕过 collect_plan。漏了它的后果是**运行时生成物被备份并覆盖** ——
    #   matugen 配色（.config/hypr/hyprland/colors.lua 等）每次重跑 install
    #   都会被仓库快照盖回去，正是 .chezmoiignore 里那条 keep 想防的事。
    #   dryrun 的「重复运行 0 备份」从 20 涨到 23 就是这么来的。
    #   判断时机与 bash 一致：在备份/写入之前。
    kind = ignore_kind(target_rel)
    if kind == 'skip':
        return 'skip', target_rel
    if kind == 'keep' and (dst.exists() or dst.is_symlink()):
        # 返回 'keep' 而不是 'skip'：调用方要分开计数（bash 版是两个计数器，
        # 输出里也是两句不同的说明）。混在一起会让「运行时生成物保留 N 个」
        # 恒为 0。
        return 'keep', target_rel

    dst_dir_p = Path(dst_dir)
    dst_dir_p.mkdir(parents=True, exist_ok=True)

    if attrs.get('symlink'):
        try:
            link_target = src.read_text().strip()
        except OSError:
            return 'skip', target_rel
        if dst.is_symlink() and os.readlink(dst) == link_target:
            return 'same', target_rel
        if dst.exists() or dst.is_symlink():
            _backup(dst, backup_dir)
        dst.unlink(missing_ok=True)
        os.symlink(link_target, dst)
        return 'link', target_rel


    # ⚠ 返回值要区分「新建」与「覆盖并备份过」—— 调用方（update）用 backup
    #   计数报给用户「N 个有差异的旧文件备份于 …」。第一版写成
    #   `'backup' if backup_dir else 'new'`，于是只要传了 backup_dir，新建的
    #   文件也被算成备份（实测 39 个新增报成 39 个备份，而 bash 报 0）。
    #
    # ⚠ 差异判断要照抄 bash 的形状（lib/70-deploy.sh）：
    #     目标是符号链接 → 比 `readlink(dst)` 与**源文件首行**
    #     否则           → 比内容
    #   不能用 fingerprint() 一刀切：源文件本身也可能是符号链接（差异层里
    #   就有，如 assets/icons/ai-openai-symbolic.svg -> openai-symbolic.svg），
    #   那时 fingerprint 给的是 "link:目标"，而 bash 读的是**链接指向文件的
    #   首行** —— 两者不等，于是每次重跑都判「有差异」并多备份一份。
    #   dryrun 的备份数因此从 20 涨到 22。
    backed_up = False
    if dst.exists() or dst.is_symlink():
        if dst.is_symlink():
            try:
                same = os.readlink(dst) == _first_line(src)
            except OSError:
                same = False
        else:
            # ⚠ 源是符号链接时也要比内容：bash 用的是 `cmp -s "$f" "$dir/$base"`，
            #   而 cmp（与 cp）默认**跟随**符号链接。差异层里就有这种源
            #   （assets/icons/ai-openai-symbolic.svg -> openai-symbolic.svg），
            #   目标被 cp 成了普通文件 —— 第二遍比内容相同，bash 判无差异。
            #   第一版在这里加 `src.is_symlink() → same = False`，于是每次重跑
            #   都多备份一份（dryrun 从 20 涨到 22）。
            same = _same_content(src, dst)
        if same:
            return 'same', target_rel
        _backup(dst, backup_dir)
        backed_up = True

    shutil.copy2(src, dst, follow_symlinks=True)
    if attrs.get('exec'):
        dst.chmod(dst.stat().st_mode | 0o111)
    if attrs.get('private'):
        dst.chmod(0o600)
    return ('backup' if backed_up else 'new'), target_rel


def _first_line(src: Path) -> str:
    """源文件的**首行**（跟随符号链接）—— 对应 bash 的 `head -n1 "$f"`。"""
    try:
        with open(src, 'r', errors='replace') as fh:
            return fh.readline().rstrip('\n')
    except OSError:
        return ''


def _same_content(a: Path, b: Path) -> bool:
    """等价 bash 的 `cmp -s "$f" "$dir/$base"`。"""
    try:
        if a.stat().st_size != b.stat().st_size:
            return False
        with open(a, 'rb') as fa, open(b, 'rb') as fb:
            while True:
                ba, bb = fa.read(65536), fb.read(65536)
                if ba != bb:
                    return False
                if not ba:
                    return True
    except OSError:
        return False


def _rel_from_home(path: str) -> str:
    from . import paths
    home = str(paths.home())
    return path[len(home) + 1:] if path.startswith(home + '/') else path


def _backup(dst: Path, backup_dir: str | None) -> None:
    if not backup_dir:
        return
    dest = Path(backup_dir) / _rel_from_home(str(dst))
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        shutil.copy2(dst, dest)
    except OSError:
        pass


# ── 部署清单（对应 lib/40-manifest.sh 的 manifest_read / manifest_write）─────

def manifest_path() -> Path:
    from . import paths, state
    shell, comp = state.resolve_session()
    return paths.state_dir() / f'deployed-{shell}-{comp}.tsv'


def revision_path() -> Path:
    from . import paths, state
    shell, comp = state.resolve_session()
    return paths.state_dir() / f'deployed-revision-{shell}-{comp}'


def manifest_read() -> dict[str, str]:
    """读旧清单 {rel: 指纹}。文件不存在或为空时返回空 dict。

    对应 bash 的 manifest_read：它返回 1 表示「没有旧清单」，调用方据此走
    「首次升级」的安全分支（目标已存在且与源不同的文件不覆盖）。
    """
    out: dict[str, str] = {}
    try:
        text = manifest_path().read_text(errors='replace')
    except OSError:
        return out
    for line in text.splitlines():
        if '\t' in line:
            fp, rel = line.split('\t', 1)
            if rel:
                out[rel] = fp
    return out


def manifest_write(rels: list[str]) -> None:
    """写回清单。每行「指纹<TAB>相对路径」，指纹取自**目标**文件当前内容。"""
    from . import paths
    out = manifest_path()
    out.parent.mkdir(parents=True, exist_ok=True)
    home = paths.home()
    lines = []
    for rel in rels:
        if not rel:
            continue
        lines.append(f'{fingerprint(home / rel)}\t{rel}')
    out.write_text('\n'.join(lines) + ('\n' if lines else ''))


def collect_plan(skip_compositor=None, skip_shell=None) -> tuple[list[str], list[Path]]:
    """算部署计划：返回 (相对路径列表, 对应源文件列表)。

    对应 bash 的 walk_sources + plan_collect：
      · .chezmoiignore 判 skip → 不进计划
      · 判 keep 且目标已存在 → 不进计划（该文件由用户保留）
    """
    rels: list[str] = []
    srcs: list[Path] = []
    for src, dst, rel, _attrs in walk_sources(skip_compositor, skip_shell):
        from . import paths
        target_rel = _rel_from_home(dst)
        kind = ignore_kind(target_rel)
        if kind == 'skip':
            continue
        if kind == 'keep' and (paths.home() / target_rel).exists():
            continue
        rels.append(target_rel)
        srcs.append(src)
    return rels, srcs
