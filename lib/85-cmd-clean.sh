# ============================================================
# 子命令 clean：清理临时残留、自举缓存、旧快照与旧备份
# ============================================================
# 默认只清 /tmp 里的安装残留（最安全）。要动快照/备份必须显式给选项 ——
# 那些是回滚的退路，不该被一条「顺手清一下」的命令带走。
# 一律先列清单再删，且支持 --dry-run。

cmd_clean() {
    local dry=0 do_tmp=1 do_cache=0 do_snaps=0 keep_snaps=3 do_updates=0
    while (($#)); do
        case "$1" in
            -n|--dry-run) dry=1; shift ;;
            --cache)      do_cache=1; shift ;;
            --snapshots)  do_snaps=1; shift
                          # 可选数字：不写就保留最近 3 份
                          if [[ "${1:-}" =~ ^[0-9]+$ ]]; then keep_snaps="$1"; shift; fi ;;
            --updates)    do_updates=1; shift ;;
            --all)        do_cache=1; do_snaps=1; do_updates=1; shift ;;
            -h|--help)
                cat <<EOF
用法：$0 clean [选项]

清理安装残留与缓存。默认只清 /tmp 下的安装残留（最安全）。

选项：
  --cache            删自举缓存（$REPO_CACHE）
  --snapshots [N]    快照只保留最近 N 份（默认 3），其余删除
  --updates          删 $BACKUP_ROOT/update-* 旧升级备份
  --all              上面三项全做（仍会先列清单再确认）
  -n, --dry-run      只列会删什么，一个字节都不删
  -h, --help         显示本帮助

⚠ 快照与备份是 rollback / restore 的退路，删了就回不去了 —— 所以它们
   不包含在默认行为里。
EOF
                return 0 ;;
            *) warn "clean: 未知选项 $1"; return 2 ;;
        esac
    done

    local -a targets=() labels=()
    local d f

    # 1. 临时残留。排除当前进程自己的 run 目录 —— 那个由 EXIT trap 负责，
    #    这里删掉会让本次运行的 mktemp 全部失效。
    if (( do_tmp )); then
        while IFS= read -r d; do
            [[ -n "$d" && "$d" != "${TMPRUN:-}" ]] || continue
            targets+=("$d"); labels+=("临时残留")
        done < <(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'dotfiles-install.*' 2>/dev/null | sort)
    fi

    # 2. 自举缓存（install / update 反复用它，删了下次要重新 clone 几十 MB）
    if (( do_cache )) && [[ -d "$REPO_CACHE" ]]; then
        targets+=("$REPO_CACHE"); labels+=("自举缓存")
    fi

    # 3. 旧快照：按 mtime 倒序，跳过前 N 份，其余删
    if (( do_snaps )) && [[ -d "$SNAP_ROOT" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" ]] || continue
            targets+=("$f"); labels+=("旧快照")
        done < <(find "$SNAP_ROOT" -maxdepth 1 -name '*.tar.gz' -printf '%T@\t%p\n' 2>/dev/null \
                 | sort -rn | tail -n +"$((keep_snaps + 1))" | cut -f2-)
    fi

    # 4. 旧升级备份目录
    if (( do_updates )) && [[ -d "$BACKUP_ROOT" ]]; then
        while IFS= read -r d; do
            [[ -n "$d" ]] || continue
            targets+=("$d"); labels+=("旧备份")
        done < <(find "$BACKUP_ROOT" -maxdepth 1 -type d -name 'update-*' 2>/dev/null | sort)
    fi

    if (( ${#targets[@]} == 0 )); then
        say "没有需要清理的东西"
        return 0
    fi

    echo "将删除以下 ${#targets[@]} 项："
    local i sz
    for i in "${!targets[@]}"; do
        sz="$(du -sh "${targets[$i]}" 2>/dev/null | cut -f1)"
        printf '  [%s] %-7s %s\n' "${labels[$i]}" "${sz:-?}" "${targets[$i]}"
    done

    if (( dry )); then
        echo
        say "--dry-run：什么都没删"
        return 0
    fi

    confirm "确认删除以上 ${#targets[@]} 项？" || return $?
    local failed=0
    for i in "${!targets[@]}"; do
        rm -rf -- "${targets[$i]}" || { warn "删不掉：${targets[$i]}"; failed=$((failed + 1)); }
    done
    say "已清理 $(( ${#targets[@]} - failed )) 项"
    (( failed == 0 )) || return 1
    return 0
}
