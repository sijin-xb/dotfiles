# ============================================================
# 自举与其他基础动作（原 §1 尾部）
# ensure_repo：让「只下一个 install.sh」也能跑；其余是安装期的公共前置。
# ============================================================
# ============================================================
# 自举：让「只下一个 install.sh」也能跑
# ============================================================
#
# 本脚本的部署源是仓库里的 dot_config/**、.chezmoiignore、check-qml-deps.py，
# 所以它平时必须和仓库在一起。但也可以只捞这一个文件就跑：
#
#     curl -fsSL https://raw.githubusercontent.com/sijin-xb/dotfiles/main/install.sh \
#         | bash -s -- update
#
# 这时 $SRC 指向的不是仓库（`curl | bash` 下 BASH_SOURCE 是空的，$SRC 会落到
# 当前目录），ensure_repo() 负责把它补上：clone 到 $REPO_CACHE，或者已经 clone
# 过就 git pull。
#
# ⚠ 补完之后**必须 exec 重跑**，而不是就地改 $SRC 继续跑。原因：刚 clone 下来的
#   install.sh 才是最新的那一份，手上这个可能是几天前的；就地继续跑等于用旧脚本
#   配新配置。exec 之后 $SRC 变成 $REPO_CACHE，一切照旧。
#
# ⚠ 只在「$SRC 不是可用仓库」时才动网络。仓库里正常执行时这一步是 0 开销的
#   一次文件存在性判断。
repo_is_usable() {
    [[ -f "$SRC/.chezmoiignore" && -d "$SRC/dot_config" ]]
}

ensure_repo() {
    repo_is_usable && return 0

    have git || die "需要 git 才能自举拉取仓库（sudo pacman -S git）。"
    ensure_dirs
    say "当前目录不是本仓库（$SRC），进入自举模式"

    if [[ -d "$REPO_CACHE/.git" ]]; then
        say "    更新仓库缓存 $REPO_CACHE"
        git -C "$REPO_CACHE" fetch --depth=1 origin \
            || die "拉取 $REPO_URL 失败（检查网络 / 代理后重试）。"
        local branch
        branch="$(git -C "$REPO_CACHE" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
        # --ff-only：缓存目录里可能有本脚本的产物（清单等不在这里，但用户可能手改过），
        # 用 ff-only 保证绝不产生合并冲突、绝不丢本地提交。
        git -C "$REPO_CACHE" merge --ff-only "origin/$branch" \
            || warn "仓库缓存不是 fast-forward，保持现状继续（想强制对齐：rm -rf $REPO_CACHE 后重跑）"
    else
        say "    克隆 $REPO_URL → $REPO_CACHE"
        rm -rf "$REPO_CACHE"
        git clone --depth=1 "$REPO_URL" "$REPO_CACHE" \
            || die "克隆 $REPO_URL 失败（检查网络 / 代理；或手动 git clone 到 $REPO_CACHE 后重跑）。"
    fi

    [[ -x "$REPO_CACHE/install.sh" ]] || chmod +x "$REPO_CACHE/install.sh" 2>/dev/null || true
    say "    改用仓库里的脚本继续：$REPO_CACHE/install.sh"
    exec bash "$REPO_CACHE/install.sh" "$@"
}

aur_install() {
    local helper; helper=$(aur_helper)
    case "$helper" in
        paru) paru -S --needed --noconfirm "$1" ;;
        yay)  yay -S --needed --noconfirm "$1" ;;
        *)    return 1 ;;
    esac
}


ensure_dirs() {
    mkdir -p "$BACKUP_ROOT" "$SNAP_ROOT" "$STATE_DIR"
}

session_warning_if_running() {
    # Hyprland 与 niri 都查：文件覆盖发生在两套合成器共用配置的机器上，
    # 正跑着的哪个会话都可能被覆盖到。
    if have hyprctl && [[ -n $(hyprctl instances 2>/dev/null || true) ]]; then
        warn "检测到 Hyprland 会话正在运行，建议在 TTY 或其他 Wayland 会话下执行文件覆盖操作，避免进程同时写入导致不一致。继续执行，但后果自负。"
    elif pgrep -x niri >/dev/null 2>&1; then
        warn "检测到 niri 会话正在运行，建议在 TTY 或其他 Wayland 会话下执行文件覆盖操作，避免进程同时写入导致不一致。继续执行，但后果自负。"
    fi
}

# 安全输入：把「读一行」收敛到一个地方，避免裸 read 挂死。
#
# 交互终端下正常等待（用户想看多久看多久）；非交互下最多等 $2 秒
# （默认 3s），拿不到输入就留空串让调用方走默认值。
#
# ⚠ 必要性：以前 confirm 与三处菜单是裸 `read`。stdin 若是**打开着但一直
#   不给数据**的管道 —— 测试台继承工具链的管道、IDE 托管的 shell、某些 CI
#   ——read 会永久阻塞。实测 `bash tests/install-sh-cli-test.sh` 卡死 10 分钟
#   无任何输出（`read` 无 tty 时并不会自动 EOF，这点常被误解）。
#
# 用法：read_answer <变量名> [超时秒数]
read_answer() {
    local __var="$1" __tmo="${2:-3}" __rc=0
    if [[ -t 0 ]]; then
        IFS= read -r "$__var" || true
        return 0
    fi
    IFS= read -r -t "$__tmo" "$__var" || __rc=$?
    printf '\n'
    if (( __rc > 128 )); then
        warn "非交互环境，${__tmo} 秒内无输入，按默认值处理。"
    fi
    return 0
}

# 通用交互确认：返回 0=yes, 1=no, 2=back（调用方决定 back 语义）
# 用法：if confirm "继续？"; then ... fi
#       或：confirm "继续？" "允许返回(b键)" && case $? in 2) return;; esac
confirm() {
    local prompt="${1:-是否继续？}" allow_back="${2:-}"
    local ans=""
    local opts="[y/N]"
    [[ -n $allow_back ]] && opts="[y/N/b(返回)]"
    printf '%s %s ' "$prompt" "$opts"
    read_answer ans
    case "$ans" in
        y|Y|yes|YES|Yes) return 0 ;;
        b|B) [[ -n $allow_back ]] && return 2 ;;
        *) return 1 ;;
    esac
}

now_ts() { date '+%Y%m%d-%H%M%S'; }

# 从 state 文件读取快照绝对路径；读不到返回 1
read_state() {
    local key="$1"
    local f="$STATE_DIR/$key"
    [[ -f $f ]] && {
        local line; line="$(<"$f")"
        [[ -n $line && -f "$line" ]] && { echo "$line"; return 0; }
    }
    return 1
}

write_state() {
    local key="$1" snap_path="$2"
    ensure_dirs
    # 只写这一个文件：read_state 读的就是它。
    # （以前还写一个 ${key}.withtime，里面是「# 时间戳 + 路径」两行 —— 全脚本
    #   搜不到读者，而 detail_rollback 展示时间用的是 stat 快照文件本身。）
    echo "$snap_path" > "$STATE_DIR/$key"
}

