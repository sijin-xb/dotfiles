# ============================================================
# 入口分发（原 §7）
# 引导在加载完全部模块后调用 main。
# ============================================================
# ============================================================
# 7. 入口：CLI 参数 → 分发
# ============================================================
main() {
    if (($#==0)); then
        enter_tui
        return 0
    fi
    case "$1" in
        --tui)       enter_tui ;;
        -h|--help)   print_help ;;
        install)     shift; cmd_install "$@" ;;
        update)      shift; cmd_update "$@" ;;
        rollback)    shift; cmd_rollback "$@" ;;
        restore)     shift; cmd_restore "$@" ;;
        archive)     shift; cmd_archive "$@" ;;
        uninstall)   shift; cmd_uninstall "$@" ;;
        status)      shift; cmd_status "$@" ;;
        doctor)      shift; cmd_doctor "$@" ;;
        deps)        shift; cmd_deps "$@" ;;
        theme)       shift; cmd_theme "$@" ;;
        clean)       shift; cmd_clean "$@" ;;
        *)           printf '\033[1;31m错误:\033[0m 未知子命令: %s\n' "$1" >&2
                     echo "运行 $0 --help 查看用法。" >&2
                     exit 2 ;;
    esac
}

