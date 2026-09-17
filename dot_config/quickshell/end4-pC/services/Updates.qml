pragma Singleton
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * 系统更新检查服务。支持 Arch / CachyOS / 其他 Arch 衍生版。
 *
 * 设计要点：
 *
 *  1) 检查不发起网络请求。用 pacman -Qu 直接比对「已安装版本 vs 本地 sync db」，
 *     前提是用户自己已经 pacman -Sy 过。pacman -Syu 自会更新 db，
 *     所以 db 一更新，下次检查就是新结果。
 *     旧的实现用 checkupdates，每次会拷贝一份临时库并重新 sync（访问镜像），
 *     实测 2.15s，其中 1.9s 纯属浪费。
 *
 *  2) AUR 走 paru -Qua（读 AUR RPC + 本地缓存），实测 2s 左右。
 *     用带时间戳的缓存把它节流，默认 15 分钟内不重复查；
 *     手动点「检查更新」/ 右键刷新会传 force 绕过缓存。
 *
 *  3) pacman 装包时它持有 /var/lib/pacman/db.lck，此时不去抢锁，直接用缓存，
 *     避免后台装包时桌面发卡的连锁反应。
 */
Singleton {
    id: root

    property bool available: false
    property alias checking: checkUpdatesProc.running
    property int count: 0

    // 缓存有效期（秒）。force 刷新不受此限。
    readonly property int cacheTtlSec: 900

    readonly property bool updateAdvised: available && count > Config.options.updates.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > Config.options.updates.stronglyAdviseUpdateThreshold

    // force 标志通过属性传入 command 模板
    property string forceFlag: "0"

    function load() {}

    // force 默认 false；定时器周期检查传 false，用户手动触发传 true
    function refresh(force) {
        if (!available)
            return;
        forceFlag = force ? "1" : "0";
        print("[Updates] Checking for system updates" + (force ? " (forced)" : ""));
        checkUpdatesProc.running = true;
    }

    Timer {
        interval: Config.options.updates.checkInterval * 60 * 1000
        repeat: true
        running: Config.ready && Config.options.updates.enableCheck
        onTriggered: {
            print("[Updates] Periodic update check due");
            root.refresh(false);
        }
    }

    Process {
        id: checkAvailabilityProc
        running: Config.ready && Config.options.updates.enableCheck
        // 只依赖 pacman；不再硬依赖 checkupdates / pacman-contrib
        command: ["which", "pacman"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            root.refresh(false);
        }
    }

    Process {
        id: checkUpdatesProc
        command: ["bash", "-c", `
            cachedir="\${XDG_CACHE_HOME:-\$HOME/.cache}/quickshell"
            cache="$cachedir/updates-count"
            cache_ts="$cachedir/updates-count.ts"
            force="${root.forceFlag}"
            now=$(date +%s)

            read_cache() {
                if [[ -f "$cache" ]]; then cat "$cache"; else echo 0; fi
            }

            # 1) pacman 在忙：db.lck 存在，不抢锁，直接返回缓存
            if [[ -e /var/lib/pacman/db.lck ]]; then
                read_cache
                exit 0
            fi

            # 2) 缓存未过期且非 force：直接复用
            if [[ "$force" != "1" && -f "$cache" && -f "$cache_ts" ]]; then
                ts=$(cat "$cache_ts" 2>/dev/null || echo 0)
                if (( now - ts < ${root.cacheTtlSec} )); then
                    read_cache
                    exit 0
                fi
            fi

            # 3) 主检查：pacman -Qu 只读本地 sync db（无网络）
            pacman_n=$(pacman -Qu 2>/dev/null | wc -l)

            # 4) AUR：paru / yay -Qua，2s 级别，无法避免
            aur_n=0
            if command -v paru >/dev/null 2>&1; then
                aur_n=$(timeout 20 paru -Qua 2>/dev/null | wc -l)
            elif command -v yay >/dev/null 2>&1; then
                aur_n=$(timeout 20 yay -Qua 2>/dev/null | wc -l)
            fi

            total=$((pacman_n + aur_n))
            mkdir -p "$cachedir" 2>/dev/null
            printf '%s' "$total" > "$cache" 2>/dev/null
            printf '%s' "$now" > "$cache_ts" 2>/dev/null
            echo "$total"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim());
                root.count = isNaN(n) ? 0 : n;
            }
        }
    }
}
