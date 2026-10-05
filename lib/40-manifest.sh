# ============================================================
# 部署清单与计划（原 §2 尾部）
# 指纹、清单读写、源树遍历、增量计划收集 —— update / install 的共同底座。
# ============================================================
# ============================================================
# 2b. 升级（update）：部署清单 / 版本比对 / 增量同步
# ============================================================
#
# install 与 update 的分工：
#   install  从零部署：装包 → 拉底盘 → 编插件 → 部署文件。重跑一次好几分钟，
#            而且会重拉上游底盘（把本地对底盘的改动冲掉）。
#   update   只做**文件层**的增量同步：比对清单 → 新增/覆盖/清理 → 写回。
#            默认完全不碰 pacman / AUR / 底盘 clone（要的话加 --with-packages）。
#
# ── 为什么需要「部署清单」────────────────────────────────────────────────
# 没有清单就不知道**哪些文件是本脚本放进去的**，于是两个后果：
#   1. 仓库里删掉的文件永远留在 $HOME —— 残留的旧配置会让新版本行为诡异，
#      而且这类问题极难排查（文件在、名字对、内容过期）。
#   2. 因为不敢确定归属，清理也无从下手：删错了就是删用户的文件。
# 清单同时记录每个文件**部署时的内容指纹**，用来区分三种情况：
#   源变了 + 目标 == 清单指纹  → 用户没动过，安全覆盖
#   源变了 + 目标 != 清单指纹  → 用户在本地改过，覆盖前显式报出来（备份仍在）
#   源没变                     → 一个字节都不碰
#
# ⚠ 清单按「会话 + 合成器」分开存。部署范围本身就跟会话走（skip_by_shell /
#   skip_by_compositor），换会话就是另一套几百个文件；拿旧清单去 diff 会把
#   它们全判成「已删除」。分会话之后，换会话退化成「首次部署」：只新增/覆盖，
#   不做清理。
#
# ⚠ 清理（prune）一律**移到备份目录**，绝不 rm。备份根和 rollback 用的是同一个
#   （$BACKUP_ROOT/update-<时间戳>），出问题一条 cp 就能捞回来。

PRE_UPDATE_PREFIX="pre-update"

# 会话后缀：清单 / 版本记录按它分开
manifest_suffix() { printf '%s-%s' "${QS_SHELL:-unknown}" "${COMPOSITOR:-unknown}"; }
manifest_path()   { printf '%s/deployed-%s.tsv' "$STATE_DIR" "$(manifest_suffix)"; }
revision_path()   { printf '%s/deployed-revision-%s' "$STATE_DIR" "$(manifest_suffix)"; }
session_path()    { printf '%s/deployed-session' "$STATE_DIR"; }

# 内容指纹。
# ⚠ 符号链接记**链接目标**而不是跟随：systemd/user/symlink_mako.service 的内容
#   是 /dev/null，跟随过去会变成「哈希 /dev/null 的内容」，改链接目标检测不出来。
fingerprint() {
    local p="$1"
    if [[ -L "$p" ]]; then
        printf 'link:%s' "$(readlink "$p")"
    elif [[ -f "$p" ]]; then
        sha256sum "$p" 2>/dev/null | cut -d' ' -f1
    else
        printf 'absent'
    fi
}

# 写清单。$@ = 相对 $HOME 的路径
manifest_write() {
    local out; out="$(manifest_path)"
    ensure_dirs
    : > "$out"
    local rel
    for rel in "$@"; do
        [[ -n "$rel" ]] || continue
        printf '%s\t%s\n' "$(fingerprint "$HOME/$rel")" "$rel" >> "$out"
    done
}

# 读旧清单到关联数组 OLD_MANIFEST[relpath]=指纹。返回 1 = 没有清单（首次）
declare -A OLD_MANIFEST=()
manifest_read() {
    OLD_MANIFEST=()
    local f; f="$(manifest_path)"
    [[ -s "$f" ]] || return 1
    local fp rel
    while IFS=$'\t' read -r fp rel; do
        [[ -n "$rel" ]] && OLD_MANIFEST["$rel"]="$fp"
    done < "$f"
    return 0
}

current_revision() {
    if have git && [[ -d "$SRC/.git" ]]; then
        git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown
    else
        echo unknown
    fi
}

# 记录本次部署的版本与会话。update 靠它做版本比对、靠 session_path 沿用会话。
record_revision() {
    ensure_dirs
    local rev branch dirty
    rev="$(current_revision)"
    branch="$(git -C "$SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    dirty="$(git -C "$SRC" status --porcelain 2>/dev/null | wc -l)"
    {
        printf 'revision=%s\n'   "$rev"
        printf 'branch=%s\n'     "$branch"
        printf 'dirty=%s\n'      "$dirty"
        printf 'session=%s\n'    "${QS_SHELL:-unknown}"
        printf 'compositor=%s\n' "${COMPOSITOR:-unknown}"
        printf 'time=%s\n'       "$(date -Iseconds)"
    } > "$(revision_path)"
    printf '%s|%s\n' "${QS_SHELL:-unknown}" "${COMPOSITOR:-unknown}" > "$(session_path)"
}

# 把仓库源树遍历一遍，对每个「应该部署」的文件调用回调。
# 回调参数：源文件 / 目标目录 / 目标文件名 / 仓库内相对路径
# 过滤规则与 [5/7] 完全一致（chezmoi 前缀在 deploy_one_file 内部剥离）。
walk_sources() {
    local cb="$1"
    local f rel out base dir
    while IFS= read -r -d '' f; do
        rel="${f#"$SRC"/}"
        case "$rel" in
            .git/*|install.sh|README.md|LICENSE|check-qml-deps.py) continue ;;
            dot_*) out="$HOME/.${rel#dot_}" ;;
            *) continue ;;
        esac
        skip_by_compositor "$rel" && { skipped=$((skipped + 1)); continue; }
        skip_by_shell "$rel" && { skipped_shell=$((skipped_shell + 1)); continue; }
        base="${out##*/}"; dir="${out%/*}"
        "$cb" "$f" "$dir" "$base" "$rel"
    # ⚠ -path … -prune：仓库的 .git 可能有几千个对象文件，不剪枝的话每个都会被
    #   走一遍再被下面的 case 丢弃。功能上 case 挡得住，但白跑一遍。
    done < <(find "$SRC" -path "$SRC/.git" -prune -o -type f -print0)
}

# ── 部署回调（install 的 [5/7] 与 update 共用）────────────────────────────
# 除了部署，还负责记录「本脚本真正落盘的文件」—— 清单就靠它。
#
# ⚠ 被 .chezmoiignore 判定为 skip/keep 的文件**不能**进清单：
#   · skip 的是缓存 / 字节码 / 插件 git 元数据，本来就不该由我们管；
#   · keep 的是运行时生成物（matugen 配色等），目标是用户当前的值，
#     下次 update 拿它去比「已删除」会把用户自己的配置清掉。
#   所以用 ignored_* 计数器的变化来区分「真部署了」和「被忽略了」。
DEPLOYED_RELPATHS=()
# update 用：这批目标路径**不要部署**（首次升级时目标已存在且与源不同，
# 无法判断是「上次部署的旧版」还是「用户自己的文件」，默认不动）。
declare -A SKIP_DEPLOY=()
skipped_conflict=0
deploy_and_record() {
    local f="$1" dir="$2" base="$3"
    local rel="${dir#"$HOME"/}/$base"
    if [[ -n "${SKIP_DEPLOY[$rel]+x}" ]]; then
        skipped_conflict=$((skipped_conflict + 1))
        return 0
    fi
    local before_skip=$ignored_skip before_keep=$ignored_keep
    deploy_one_file "$f" "$dir" "$base"
    # 只有「真的落盘了」才计数与记录 —— ignored_* 计数器没变就说明这个文件被
    # .chezmoiignore 判成 skip/keep 了，既不该进清单（否则下次 update 会拿它
    # 去比「已删除」），也不该算进「已部署 N 个」的 N（那会让数字虚高）。
    if (( ignored_skip == before_skip && ignored_keep == before_keep )); then
        DEPLOYED_RELPATHS+=("${dir#"$HOME"/}/$base")
        installed=$((installed + 1))
    fi
}

# ── 壁纸目录：把仓库自带的壁纸铺到 ~/Pictures/Wallpapers ────────────────
# 壁纸选择器（Ctrl+Super+T）读的就是这个目录。仓库根下的 Pictures/Wallpapers
# 在 .chezmoiignore 里、walk_sources 不会部署它 —— 于是新装机器上目录不存在，
# 选择器永远显示「No wallpapers found」。
#
# 语义是**只补不覆盖**（与 update 的「只补不卸」一致）：
#   · 目标没有     → 复制过去
#   · 目标已有同名 → 内容相同就跳过；内容不同说明是用户自己的同名文件，不动
# 两边（install / update）都调它：往仓库加壁纸后，update 也能把新图带过去。
sync_wallpapers() {
    local src="$SRC/Pictures/Wallpapers"
    local dst="$HOME/Pictures/Wallpapers"
    [[ -d "$src" ]] || return 0
    mkdir -p "$dst"
    local f base n_copied=0 n_kept=0 n_same=0
    while IFS= read -r -d '' f; do
        base="$(basename "$f")"
        if [[ ! -e "$dst/$base" ]]; then
            cp -p "$f" "$dst/$base"
            n_copied=$((n_copied + 1))
        elif cmp -s "$f" "$dst/$base"; then
            n_same=$((n_same + 1))
        else
            n_kept=$((n_kept + 1))
        fi
    done < <(find "$src" -maxdepth 1 -type f -print0 | LC_ALL=C sort -z)
    say "壁纸目录已就绪：~/Pictures/Wallpapers（新铺 $n_copied，仓库与本地一致 $n_same，保留本地版本 $n_kept）"
}

# ── 计划回调（update 用）────────────────────────────────────────────────
# 只收集，不落盘。同时记住源路径，用来算「源内容变了没」。
#
# ⚠ 这里必须复刻 deploy_one_file 的 .chezmoiignore 判断，否则会出现两类噪声：
#   · skip 的（缓存 / 字节码 / 插件 git 元数据）根本不会被部署，列进计划纯属多余；
#   · keep 的（matugen 配色、btop.conf、fastsetup config 这类**运行时生成物**）
#     目标是用户当前的值，会被判成「目标存在且与源不同」→ 全被列成「冲突」，
#     把真正需要人工看的几项淹掉。
PLAN_PATHS=()
PLAN_SRCS=()
plan_collect() {
    local f="$1" dir="$2" base="$3"
    local rel="${dir#"$HOME"/}/$base"
    case "$(chezmoi_ignore_kind "$rel")" in
        skip) return 0 ;;
        keep) [[ -e "$HOME/$rel" || -L "$HOME/$rel" ]] && return 0 ;;
    esac
    PLAN_PATHS+=("$rel")
    PLAN_SRCS+=("$f")
}

