# ============================================================
# 底盘装配与单文件部署
# 底盘完整性自检、clone 合并、运行时清单判定、单条目落盘。
# ============================================================
# 自检 end4-PC 底盘是否完整。
#
# 清单里只能放 pctrade/end4-PC 真的提供的路径。列了上游没有的路径，
# 自检会永远判缺，重拉也补不上，[4/7] 直接 die。
# 加条目前先核：gh api repos/pctrade/end4-PC/contents/<路径>
#
# 输出：完整 → 无输出且返回 1；残缺 → 打印第一个缺失项并返回 0。
# 调用方写 x="$(end4pc_base_missing || true)"，|| true 不能省：
# 赋值语句的退出码取自命令替换，返回 1 会让整个赋值非零退出。
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
# 以 clone 为基准而非硬编码清单，上游增删文件不用改这里。
# 必须在删掉临时 clone 目录之前调用。
# 输出同 end4pc_base_missing。
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

# 把 clone 出来的目录合并进目标目录，不带 .git。
#
# .git 不属于运行时配置目录，塞进去是十几 MB 的无用 pack，还会被快照整包打包。
# 更糟的是属主或权限不对时，重跑会在 .git/objects/pack 上 EACCES 半途而废，
# 底盘只拷进去一半，下次自检判不完整又重拉，在同一个位置反复失败。
merge_clone_into() {
    local src="$1" dst="$2"
    rm -rf "$src/.git"
    mkdir -p "$dst"
    cp -a "$src/." "$dst/" \
        || die "合并 $src → $dst 失败（检查磁盘空间，以及 $dst 及其子目录的属主是否为当前用户）"
}

# 清掉历史上误拷进来的 .git。属主是 root 时普通用户删不掉，
# 提示手工命令而不是假装成功。
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

# 判断目标相对路径（相对 $HOME）是否命中 runtime-keep.txt。
# 命中输出处理方式，未命中输出空：
#   keep   精确路径 → 目标已存在时不覆盖
#   skip   目录     → 一律跳过
#
# 仓库里有些文件只是某次提交时的快照，实机由程序按当前状态重写。
# 不屏蔽就会用旧快照覆盖运行时状态，最典型的是 hyprland/colors.lua：
# matugen 按当前壁纸生成，仓库那份是旧调色板，每重跑一次安装就打回旧值。
#
# 精确路径只在目标不存在时部署，新机器仍拿到可用默认值。
# 目录条目一律跳过（缓存、字节码、插件 git 元数据、UI 写回的配置）。
runtime_keep_kind() {
    local target="$1"
    local keep_file="$SRC/runtime-keep.txt"
    local line pat tp
    [[ -f $keep_file ]] || return 0
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
    done < "$keep_file"
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
# 抽成独立函数以便脱离 pacman / AUR / 网络单独测试。
deploy_one_file() {
    local f="$1" dir="$2" base="$3"

    # 属性后缀：.private → 0600，.symlink → 文件内容是链接目标。
    # fcitx5 会写回这些 conf，权限不对改不动；mako.service 指向 /dev/null
    # 以屏蔽系统 mako，避免与 quickshell 抢 org.freedesktop.Notifications。
    # 执行位不走后缀，由源文件 mode 决定。
    local private=0 symlink=0
    while :; do
        case "$base" in
            *.private) base="${base%.private}"; private=1 ;;
            *.symlink) base="${base%.symlink}"; symlink=1 ;;
            *) break ;;
        esac
    done

    mkdir -p "$dir"

    # 必须在备份与写入之前判断，否则既白备份，又会用仓库旧快照
    # 覆盖运行时生成物。
    local target_rel
    if [[ "$dir" == "$HOME" ]]; then target_rel="$base"; else target_rel="${dir#"$HOME"/}/$base"; fi
    case "$(runtime_keep_kind "$target_rel")" in
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

    # 有差异才备份。符号链接要比链接本身而不是 cmp：
    # mako.service -> /dev/null 会被 cmp 跟随成拿 /dev/null 的内容去比。
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
            # -a 而非 -p：备份符号链接要保留链接本身，不能解引用
            cp -a "$dir/$base" "$backup_dir/$dir/$base"
            backed=$((backed + 1))
        fi
    fi

    if ((symlink)); then
        ln -sfn "$(head -n1 "$f")" "$dir/$base"
    else
        cp "$f" "$dir/$base"
        # 执行位跟随源文件：git 的 mode 位是唯一来源
        if [[ -x "$f" ]]; then chmod +x "$dir/$base"; fi
        if ((private)); then chmod 600 "$dir/$base"; fi
    fi
}

