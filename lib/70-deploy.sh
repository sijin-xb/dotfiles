# ============================================================
# 底盘装配与单文件部署（原 §2 尾部）
# 上游底盘完整性自检、clone 合并、.chezmoiignore 判定、单条目落盘。
# ============================================================
# 自检 end4-PC 底盘是否**完整**（不只是"入口文件在"）。
#
# ⚠ 清单里**只能放底盘（pctrade/end4-PC）真的提供**的落点。
#   这里以前还列了 4 项 modules/ii/dashboard-caelestia/**：
#
#       modules/ii/dashboard-caelestia/dashboard/Content.qml
#       modules/ii/dashboard-caelestia/components/filedialog/FileDialog.qml
#       modules/ii/dashboard-caelestia/components/controls/ButtonBase.qml
#       modules/ii/dashboard-caelestia/shim/qmldir
#
#   但上游 modules/ii/ 下**根本没有 dashboard-caelestia 这个目录**
#   （本仓库自己的定制层，IslandHost.qml 直接 import
#    "../modules/ii/dashboard-caelestia/components/filedialog"，由 [5/7] 部署）。
#   于是自检永远判"缺"→ 重拉上游也补不上 → 在 [4/7] 报
#   "底盘拉取后仍缺少 …" 直接 die，安装永远走不完。
#
#   改清单前先核一遍（有 = 底盘提供，才可以列进来）：
#     gh api repos/pctrade/end4-PC/contents/<路径>
#
# 输出：完整 → 无输出且返回 1；残缺 → 打印**第一个**缺失项并返回 0。
# ⚠ 返回 1 表示"完整"，调用方用 `x="$(end4pc_base_missing || true)"` 取值，
#   `|| true` 不能省（赋值语句的退出码取自命令替换结果）。
end4pc_base_missing() {
    local dst="${1:-$HOME/.config/quickshell/end4-pC}"
    local rel
    # 下面每一项都按上面的办法核过：上游确实提供，缺了才说明 clone 残缺。
    for rel in \
        shell.qml \
        modules/common/Config.qml \
        modules/common/Appearance.qml \
        services \
        scripts/colors/switchwall.sh
    do
        [[ -e "$dst/$rel" ]] || { printf '%s' "$rel"; return 0; }
    done
    return 1
}

# 精确自检：clone 里有的每个文件，dst 里都该有。
#
# 这才是"cp 半途而废 / 磁盘写满"的**准确**判据 —— 只需要拿 clone 当基准，
# 上游以后加文件、删目录都不用来改这里（硬编码清单会腐烂，见上面那次事故）。
# ⚠ 必须在删掉临时 clone 目录**之前**调用。
# 输出同 end4pc_base_missing：完整 → 无输出且返回 1。
base_tree_missing() {
    local src="$1" dst="$2" rel f
    [[ -d "$src" ]] || { printf '（clone 目录不存在：%s）' "$src"; return 0; }
    # ⚠ 这里刻意**不用** `< <(find …)` 进程替换：它依赖 /dev/fd，容器 / 精简
    #   chroot 里可能不存在，一旦不可用整段判据会静默失效 —— 而这是"完整性"
    #   的最后一道闸，失效就等于放行半残的树。改用临时清单文件。
    local listf; listf="$(mktmp)"
    find "$src" -type f -print0 > "$listf" 2>/dev/null
    while IFS= read -r -d '' f; do
        rel="${f#"$src"/}"
        [[ -e "$dst/$rel" ]] && continue
        printf '%s' "$rel"
        rm -f "$listf"
        return 0
    done < "$listf"
    rm -f "$listf"
    return 1
}

# 把 clone 出来的目录合并进目标目录，**不带 .git**。
#
# ⚠ 为什么必须剥掉 .git（以前两处 `cp -a "$src/." "$dst/"` 都漏了）
# ------------------------------------------------------------------
# 1) ~/.config/quickshell 是**运行时配置命名空间**，不是放源码的地方。
#    [5/7] 的部署循环自己就写着 `.git/*) continue`（跳过仓库元数据），
#    说明 .git 本就不属于这里 —— 唯独漏了 clone 合并这两处。塞进去的是
#    一个十几 MB 的 pack，既没有任何用处，还会被 [0/7] 的快照/归档整包打包。
# 2) 更糟的是它会让安装**永久卡死**：一旦这个 .git 的属主或权限不允许当前
#    用户写入，重跑时 cp 会在 .git/objects/pack/ 上 EACCES 并半途而废，
#    底盘只拷进去一半 → 下次自检判"不完整"→ 又重拉 → 又在同一个位置失败。
#    报错指向 .git，看起来像权限问题，真因却是"压根不该拷"。
merge_clone_into() {
    local src="$1" dst="$2"
    rm -rf "$src/.git"
    mkdir -p "$dst"
    cp -a "$src/." "$dst/" \
        || die "合并 $src → $dst 失败（检查磁盘空间，以及 $dst 及其子目录的属主是否为当前用户）"
}

# 清掉历史上被上面那步误拷进来的 .git（它从来没被用过，可以安全删除）。
# 属主是 root 时普通用户删不掉（要对 .git/objects/pack 有写权限），这时
# 提示手工命令而不是假装成功 —— 留着它不影响 shell 运行，但会一直占空间。
cleanup_stray_git() {
    local dst="$1"
    [[ -e "$dst/.git" ]] || return 0
    if rm -rf "$dst/.git" 2>/dev/null; then
        echo "    已清理历史遗留的 .git（clone 元数据，不属于配置目录）"
    else
        warn "无法删除 $dst/.git（属主可能不是当前用户）"
        warn "  它没有任何用处，可手动清理：sudo rm -rf '$dst/.git'"
    fi
}

# 判断某个**目标相对路径**（相对 $HOME，如 .config/hypr/hyprland/colors.lua）
# 是否命中 $SRC/.chezmoiignore。命中则输出处理方式，未命中输出空：
#   keep   精确路径条目   → 目标已存在时**不覆盖**
#   skip   glob / 目录条目 → 一律跳过
#
# 为什么要读 chezmoi 的忽略清单
# ----------------------------
# install.sh 与 chezmoi 部署同一份源树，规则必须一致。漏读的后果是**用仓库里的
# 旧快照覆盖运行时生成物** —— 最典型的是 .config/hypr/hyprland/colors.lua：
# 那是 matugen 按当前壁纸生成的，仓库里那份只是某次提交时的调色板。实测差异：
#     仓库  active_border = "rgba(90d5aeAA)"
#     实机  active_border = "rgba(feb0d3AA)"
# 也就是说，每重跑一次安装就把用户配色打回旧值。仓库 .chezmoiignore 的注释
# 本身就写着「install.sh 直接遍历源目录复制…不读取本文件」，这条就是要补的差。
#
# 语义与 chezmoi 对齐：
#   · 精确路径   → 只在目标**不存在**时部署（新机器仍拿到一份可用默认值）
#   · glob / 目录 → 一律跳过（缓存、字节码、插件 git 元数据、UI 写回的配置）
chezmoi_ignore_kind() {
    local target="$1"
    local ignore_file="$SRC/.chezmoiignore"
    local line pat tp
    [[ -f $ignore_file ]] || return 0
    while IFS= read -r line || [[ -n $line ]]; do
        pat="${line%%#*}"                                  # 去注释
        pat="${pat#"${pat%%[![:space:]]*}"}"               # 去首空白
        pat="${pat%"${pat##*[![:space:]]}"}"               # 去尾空白
        [[ -z $pat ]] && continue
        if [[ $pat == */ ]]; then                          # 目录
            [[ $target == "$pat"* ]] && { printf 'skip'; return 0; }
            continue
        fi
        if [[ $pat == *'**'* ]]; then                      # **/X → 任意深度的 X
            tp="${pat##*\*\*/}"
            [[ $target == $tp || $target == */"$tp" || $target == */"$tp"/* ]] \
                && { printf 'skip'; return 0; }
            continue
        fi
        if [[ $pat == *'*'* ]]; then                       # 单层 glob
            # shellcheck disable=SC2254
            case "$target" in $pat) printf 'skip'; return 0 ;; esac
            continue
        fi
        [[ $target == "$pat" ]] && { printf 'keep'; return 0; }
    done < "$ignore_file"
    return 0
}

# 部署单个源文件到 $HOME（[5/7] 的循环体）。
#
# $1 = 源文件绝对路径
# $2 = 目标目录（绝对路径，已含 $HOME 前缀）
# $3 = 目标文件名（含 chezmoi 属性前缀）
#
# 依赖调用方设置的全局量：
#   $backup_dir  有差异的旧文件备份根
#   $backed      备份计数（本函数自增）
#
# 抽成独立函数是为了**能脱离 pacman / AUR / 网络单独测**：这段逻辑以前内联在
# [5/7] 的 while 里，只能靠跑一遍完整安装来验证，而完整安装要 sudo。
deploy_one_file() {
    local f="$1" dir="$2" base="$3"

    # ── chezmoi 属性前缀 ────────────────────────────────────────────
    # 本脚本直接遍历源目录复制，不经过 chezmoi，所以得自己认这些前缀；
    # 漏认的后果是**把前缀当成文件名的一部分部署出去**（静默故障：
    # 文件在、名字错、程序读不到）。
    #   executable_ → 剥前缀 + chmod +x
    #   private_    → 剥前缀 + chmod 600
    #                 （fcitx5 的 config / conf/*.conf 用它；fcitx5 会写回
    #                   这些文件，权限不对会改不动）
    #   symlink_    → 剥前缀 + 建符号链接，文件**内容**就是链接目标
    #                 （systemd/user/symlink_mako.service 内容为 /dev/null，
    #                   用来屏蔽系统 mako 服务，避免和 quickshell 的
    #                   通知服务抢 org.freedesktop.Notifications）
    # ⚠ create_ **不在此列**，必须保持字面文件名：chezmoi 的 create_ 语义是
    #   「不存在才创建」并会剥前缀，但 hyprland/services/init.lua 里写的是
    #   require("hyprland/services/create_custom_config")，剥成
    #   custom_config.lua 反而 require 不到 —— .chezmoiignore 里记的就是
    #   这个冲突。所以这里只认上面三个。
    # 前缀可以叠加（private_executable_xxx），所以用循环而不是 if。
    local execbit=0 private=0 symlink=0
    while :; do
        case "$base" in
            executable_*) base="${base#executable_}"; execbit=1 ;;
            private_*)    base="${base#private_}";    private=1 ;;
            symlink_*)    base="${base#symlink_}";    symlink=1 ;;
            *) break ;;
        esac
    done

    mkdir -p "$dir"

    # ── .chezmoiignore：与 chezmoi 对齐（见 chezmoi_ignore_kind 的说明）──
    # 必须在备份/写入之前判断：否则既会白备份，又会把运行时生成物
    # （matugen 配色等）用仓库旧快照覆盖掉。
    local target_rel
    if [[ "$dir" == "$HOME" ]]; then target_rel="$base"; else target_rel="${dir#"$HOME"/}/$base"; fi
    case "$(chezmoi_ignore_kind "$target_rel")" in
        skip)
            ignored_skip=$((ignored_skip + 1))
            return 0
            ;;
        keep)
            # 运行时生成物且目标已存在：保留用户当前值，不动也不备份
            if [[ -e "$dir/$base" || -L "$dir/$base" ]]; then
                ignored_keep=$((ignored_keep + 1))
                return 0
            fi
            ;;
    esac

    # 有差异才备份。符号链接不能直接 cmp（会跟随链接比到目标文件，
    # 比如 mako.service -> /dev/null 会变成拿 /dev/null 的内容去比），
    # 得比链接本身。
    if [[ -e "$dir/$base" || -L "$dir/$base" ]]; then
        local differs=0
        if [[ -L "$dir/$base" ]]; then
            [[ "$(readlink "$dir/$base")" == "$(head -n1 "$f")" ]] || differs=1
        elif [[ -f "$dir/$base" ]]; then
            cmp -s "$f" "$dir/$base" || differs=1
        else
            differs=1
        fi
        if ((differs)); then
            mkdir -p "$backup_dir/$dir"
            # -a 而不是 -p：备份符号链接时要保留链接本身，不能解引用
            cp -a "$dir/$base" "$backup_dir/$dir/$base"
            backed=$((backed + 1))
        fi
    fi

    if ((symlink)); then
        ln -sfn "$(head -n1 "$f")" "$dir/$base"
    else
        cp "$f" "$dir/$base"
        if ((execbit)); then chmod +x "$dir/$base"; fi
        if ((private)); then chmod 600 "$dir/$base"; fi
    fi
}

