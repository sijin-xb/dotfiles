# ============================================================
# 子命令 update（原 §3b）
# ============================================================
# ============================================================
# 3b. update：增量升级（不重装包、不重拉底盘）
# ============================================================
#
# 用法：
#   ./install.sh update                    增量同步文件（最常用）
#   ./install.sh update --dry-run          只看会改什么，一个字节都不写
#   ./install.sh update --with-packages    顺便补齐新增的依赖包
#   ./install.sh update --no-prune         不做「已删除文件」清理
#   ./install.sh update --force            版本没变也照跑
#   ./install.sh update --yes              不交互确认
#
# 与 install 的边界：install 管「装包 → 拉底盘 → 编插件 → 部署」，重跑要几分钟，
# 而且会把本地对上游底盘的改动冲掉。update 只管**文件层**，且默认连仓库都不拉
# （拉仓库用 --pull，或直接在仓库里 git pull 后再 update）。
cmd_update() {
    local dry_run=0 with_packages=0 force=0 prune=1 assume_yes=0 pull=0
    while (($#)); do
        case "$1" in
            --dry-run|-n)    dry_run=1 ;;
            --with-packages) with_packages=1 ;;
            --force)         force=1 ;;
            --no-prune)      prune=0 ;;
            --pull)          pull=1 ;;
            --yes|-y)        assume_yes=1 ;;
            -h|--help)       print_help; return 0 ;;
            *) die "update 不认识参数: $1
    支持：--dry-run / --with-packages / --force / --no-prune / --pull / --yes" ;;
        esac
        shift
    done

    [[ -f /etc/arch-release ]] || die "本安装器仅支持 Arch Linux 系发行版（CachyOS / Arch 等）。"
    [[ ${EUID} -eq 0 ]] && die "请勿用 root 运行（makepkg/AUR 步骤需要普通用户）。"
    have pacman || die "找不到 pacman。"

    ensure_repo "$@"          # 单文件运行时自举拉仓库并 exec 重跑
    # --dry-run 承诺「一个字节都不写」，所以不建备份目录。
    # manifest_read 只读 $STATE_DIR，目录不存在时返回「没有旧清单」，行为正确。
    # ⚠ ensure_repo 无法避免：没有源树就算不出计划。单文件自举模式下它会
    #   clone 仓库再 exec 重跑 —— 那种情况下 dry-run 确实会动网络与磁盘。
    if ((dry_run)); then
        warn "--dry-run：不会写任何配置文件；但仓库源树仍是必需的（可能已 clone/拉取）。"
    else
        ensure_dirs
    fi
    session_warning_if_running

    # ── 可选：先把仓库拉到最新 ──────────────────────────────────────
    # 默认不拉：多数人是在仓库里改完再跑 update，自动 pull 反而会跟未提交改动打架。
    if ((pull)); then
        if [[ -d "$SRC/.git" ]]; then
            say "拉取仓库最新提交（--pull）"
            git -C "$SRC" pull --ff-only \
                || die "git pull 失败（有本地未提交改动或不是 fast-forward）。先手动处理再重试。"
        else
            warn "--pull 指定了但 $SRC 不是 git 仓库，跳过"
        fi
    fi

    # ── 会话：优先 SESSION 环境变量，其次沿用上次记录 ────────────────
    # ⚠ 必须显式提示沿用了哪个。部署范围跟会话走（skip_by_shell /
    #   skip_by_compositor），静默换会话会让清单和实际部署对不上。
    if [[ -z "${SESSION:-}" && -z "${QS_SHELL:-}" && -f "$(session_path)" ]]; then
        local saved; saved="$(<"$(session_path)")"
        local saved_shell="${saved%%|*}" saved_comp="${saved##*|}"
        if [[ -n "$saved_shell" && "$saved_shell" != "unknown" ]]; then
            QS_SHELL="$saved_shell"; COMPOSITOR="$saved_comp"
            echo "    沿用上次的会话：$QS_SHELL + $COMPOSITOR（要换：SESSION=dms $0 update）"
        fi
    fi
    if [[ -z "${QS_SHELL:-}" ]]; then
        choose_session
    fi

    # ── 版本比对 ────────────────────────────────────────────────────
    local old_rev="" new_rev dirty
    new_rev="$(current_revision)"
    [[ -f "$(revision_path)" ]] && old_rev="$(sed -n 's/^revision=//p' "$(revision_path)" | head -n1)"
    # wc -l 永远有输出（哪怕是 0），所以这里不需要「空则置 0」的兜底。
    dirty="$(git -C "$SRC" status --porcelain 2>/dev/null | wc -l)"

    echo "----------------------------------------------------------------------"
    echo "  部署会话 : $QS_SHELL + $COMPOSITOR"
    echo "  上次部署 : ${old_rev:-（无记录，按首次升级处理）}"
    if (( dirty > 0 )); then
        echo "  仓库当前 : $new_rev  （工作区 $dirty 处未提交改动）"
    else
        echo "  仓库当前 : $new_rev"
    fi
    if [[ -n "$old_rev" && "$old_rev" == "$new_rev" && $force -eq 0 && $dirty -eq 0 ]]; then
        echo "  状态     : 没有新提交 —— 仍会按清单核一遍文件（要跳过请 Ctrl-C）"
    fi
    echo "----------------------------------------------------------------------"

    # ── 算清单 diff ─────────────────────────────────────────────────
    local had_manifest=1
    manifest_read || had_manifest=0

    PLAN_PATHS=()
    local skipped=0 skipped_shell=0
    walk_sources plan_collect

    local -a added=() changed=() removed=() local_modified=() conflicts=()
    local i rel src_fp
    declare -A NEWSET=()
    for rel in "${PLAN_PATHS[@]}"; do NEWSET["$rel"]=1; done

    for ((i = 0; i < ${#PLAN_PATHS[@]}; i++)); do
        rel="${PLAN_PATHS[$i]}"
        src_fp="$(fingerprint "${PLAN_SRCS[$i]}")"
        if [[ -z "${OLD_MANIFEST[$rel]+x}" ]]; then
            # ── 首次升级的安全网 ──────────────────────────────────────
            # 没有旧清单时，分不清「目标文件是上次部署的」还是「用户自己建的 /
            # 自己改过的」。直接覆盖可能把用户的修复冲掉 —— 这不是假设：
            # 本机实测 ConfigComboBox.qml / CaelestiaPluginProbe.qml 两个文件
            # 仓库里是旧版、live 里是带修复的新版，一次盲覆盖就把修复退回去了。
            # 所以这类「目标已存在且与源不同」的文件默认**不部署**，列出来让人
            # 自己决定；确认要按仓库版本覆盖再加 --force。
            if [[ -e "$HOME/$rel" || -L "$HOME/$rel" ]] \
               && [[ "$(fingerprint "$HOME/$rel")" != "$src_fp" ]]; then
                conflicts+=("$rel")
            else
                added+=("$rel")
            fi
        elif [[ "${OLD_MANIFEST[$rel]}" != "$src_fp" ]]; then
            changed+=("$rel")
            # 用户在本地改过？（目标当前内容 != 部署时记下的内容）
            [[ "$(fingerprint "$HOME/$rel")" != "${OLD_MANIFEST[$rel]}" ]] && local_modified+=("$rel")
        fi
    done

    if ((had_manifest && prune)); then
        for rel in "${!OLD_MANIFEST[@]}"; do
            [[ -z "${NEWSET[$rel]+x}" ]] && removed+=("$rel")
        done
    fi

    # ── 计划 ────────────────────────────────────────────────────────
    echo
    echo "  将部署 ${#PLAN_PATHS[@]} 个文件"
    if (( ! had_manifest )); then
        echo "  · 没有旧清单（首次升级）→ 全部按新增处理，本次不做删除清理"
    fi
    printf '  · 新增   %d\n' "${#added[@]}"
    printf '  · 更新   %d\n' "${#changed[@]}"
    if (( ${#local_modified[@]} )); then
        printf '  · 其中 %d 个你在本地改过（会先备份再覆盖）：\n' "${#local_modified[@]}"
        printf '      %s\n' "${local_modified[@]:0:8}"
        (( ${#local_modified[@]} > 8 )) && printf '      …还有 %d 个\n' "$(( ${#local_modified[@]} - 8 ))"
    fi
    if (( prune )); then
        printf '  · 删除   %d（移到备份，不直接 rm）\n' "${#removed[@]}"
        (( ${#removed[@]} )) && printf '      %s\n' "${removed[@]:0:8}"
        (( ${#removed[@]} > 8 )) && printf '      …还有 %d 个\n' "$(( ${#removed[@]} - 8 ))"
    fi

    # ── 冲突：目标已存在且与源不同，且我们不知道它是不是我们部署的 ──
    SKIP_DEPLOY=()
    if (( ${#conflicts[@]} )); then
        if (( force )); then
            echo
            warn "以下 ${#conflicts[@]} 个文件目标已存在且与仓库版本不同，--force 已指定 → 会被仓库版本覆盖（覆盖前备份）"
            printf '      %s\n' "${conflicts[@]:0:8}"
            (( ${#conflicts[@]} > 8 )) && printf '      …还有 %d 个\n' "$(( ${#conflicts[@]} - 8 ))"
        else
            echo
            warn "以下 ${#conflicts[@]} 个文件目标已存在且与仓库版本不同，本次**不动**它们"
            printf '      %s\n' "${conflicts[@]:0:8}"
            (( ${#conflicts[@]} > 8 )) && printf '      …还有 %d 个\n' "$(( ${#conflicts[@]} - 8 ))"
            echo "    没有旧清单时无法判断这是「上次部署的旧版」还是「你自己的文件」。"
            echo "    · 想让仓库版本覆盖它们：加 --force"
            echo "    · 想保留本地版本并让仓库跟上：先 ./sync.sh <对应文件> 再跑 update"
            for rel in "${conflicts[@]}"; do SKIP_DEPLOY["$rel"]=1; done
        fi
    fi
    echo

    if ((dry_run)); then
        say "--dry-run：以上只是计划，没有写入任何文件。"
        return 0
    fi

    if (( ! assume_yes )); then
        confirm "确认执行以上变更？" || { say "已取消，未做任何改动。"; return 1; }
    fi

    # ── 升级前快照（失败安全的底座）──────────────────────────────────
    say "创建升级前快照（失败时可用 rollback 还原）"
    if ! snapshot_current "$PRE_UPDATE_PREFIX" before-update; then
        if (( ! assume_yes )); then
            confirm "快照创建失败，仍要继续？" || { say "已取消。"; return 1; }
        else
            warn "快照创建失败，继续（无法用 rollback 还原本次升级）"
        fi
    fi

    # ── 可选：补齐依赖 ──────────────────────────────────────────────
    if ((with_packages)); then
        say "补齐依赖包（--with-packages）"
        local -a _pkg=() _aur=()
        mapfile -t _pkg < <(fixed_pacman_pkgs)
        (( fonts_enabled )) && { local -a _f; mapfile -t _f < <(font_pacman_pkgs); _pkg+=("${_f[@]}"); }
        # shellcheck disable=SC2207
        _pkg+=($(compositor_pkgs)) ; # shellcheck disable=SC2207
        _pkg+=($(shell_pacman_pkgs)); # shellcheck disable=SC2207
        _pkg+=($(base_pacman_pkgs))
        if "${SUDO:-sudo}" pacman -S --needed --noconfirm "${_pkg[@]}"; then
            echo "    官方仓库包已就绪（${#_pkg[@]} 个）"
        else
            warn "部分 pacman 包安装失败，可稍后手动重跑（不影响文件部署）"
        fi

        mapfile -t _aur < <(fixed_aur_pkgs)
        (( fonts_enabled )) && { local -a _fa; mapfile -t _fa < <(font_aur_pkgs); _aur+=("${_fa[@]}"); }
        # shellcheck disable=SC2207
        _aur+=($(compositor_aur_pkgs)); # shellcheck disable=SC2207
        _aur+=($(shell_aur_pkgs));      # shellcheck disable=SC2207
        _aur+=($(base_aur_pkgs))
        local p
        for p in "${_aur[@]}"; do
            [[ -n "$p" ]] || continue
            if pacman -Q "$p" >/dev/null 2>&1; then
                echo "    已安装: $p"
            elif aur_install "$p"; then
                echo "    AUR 安装成功: $p"
            else
                warn "$p 安装失败（可稍后手动安装）"
            fi
        done
        echo "    注意：update 只补装，不卸载、不升级已装的包。"
    fi

    # ── 部署 ────────────────────────────────────────────────────────
    backup_dir="$BACKUP_ROOT/update-$(now_ts)"
    installed=0; backed=0; skipped=0; skipped_shell=0
    ignored_skip=0; ignored_keep=0; skipped_conflict=0
    DEPLOYED_RELPATHS=()
    walk_sources deploy_and_record
    say "已部署 $installed 个文件；$backed 个有差异的旧文件备份于 $backup_dir"
    sync_wallpapers
    (( skipped_conflict )) && say "另有 $skipped_conflict 个冲突文件按计划跳过（见上面的清单）"

    # ── 清理：仓库里已删除的文件 ────────────────────────────────────
    if (( prune )) && (( ${#removed[@]} )); then
        local n_pruned=0
        for rel in "${removed[@]}"; do
            [[ -e "$HOME/$rel" || -L "$HOME/$rel" ]] || continue
            mkdir -p "$backup_dir/removed/$(dirname "$rel")"
            mv "$HOME/$rel" "$backup_dir/removed/$rel" 2>/dev/null && n_pruned=$((n_pruned + 1))
        done
        say "已移走 $n_pruned 个仓库中已删除的文件（备份在 $backup_dir/removed/，没有 rm）"
    fi

    # ── 写回清单与版本 ──────────────────────────────────────────────
    manifest_write "${DEPLOYED_RELPATHS[@]}"
    record_revision
    say "清单已更新：$(manifest_path)"
    say "版本已记录：$(current_revision)（$(revision_path)）"

    # ── QML 模块依赖自检 ─────────────────────────────────────────────
    # 与 install 的 [7/7] 同一段逻辑（那边有完整注释，这里不再重复）。
    # update 也必须跑：升级会带进**新的 QML 文件**，新文件可能 import 了机器上
    # 还没有的 Qt 模块 —— 缺了照样是「组件静默消失、日志只有一行 WARN」。
    # 典型场景就是 qt6-positioning / kirigami / syntax-highlighting：
    # 装过 Plasma 的机器永远不缺，纯净机器 update 完就少一块。
    if [[ "$QS_SHELL" != "dms" && -x "$SRC/check-qml-deps.py" ]]; then
        local qml_report qml_rc
        qml_report="$("$SRC/check-qml-deps.py" --quiet 2>&1)"
        qml_rc=$?
        if (( qml_rc != 0 )); then
            echo
            warn "QML 模块依赖不全 —— 下面这些组件启动后会静默消失（不会报错）"
            printf '%s\n' "$qml_report"
            echo
            warn "补齐办法：$0 update --with-packages，或手动跑：$SRC/check-qml-deps.py"
        else
            echo "    QML 模块依赖自检：齐全"
        fi
    fi

    echo
    echo "----------------------------------------------------------------------"
    echo "  升级完成。"
    echo "  出问题就回滚：$0 rollback"
    echo "  回滚后再想回到升级后的状态：$0 restore"
    echo "----------------------------------------------------------------------"
    echo "  注：包 / 上游底盘 / Caelestia 插件不在 update 范围内。"
    echo "      需要时重跑 $0 install（--with-packages 只补装缺失的依赖）。"
}

