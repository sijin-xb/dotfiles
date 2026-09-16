pragma Singleton
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * System updates service. Currently only supports Arch.
 */
Singleton {
    id: root

    property bool available: false
    property alias checking: checkUpdatesProc.running
    property int count: 0
    
    readonly property bool updateAdvised: available && count > Config.options.updates.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > Config.options.updates.stronglyAdviseUpdateThreshold

    function load() {}
    function refresh() {
        if (!available) return;
        print("[Updates] Checking for system updates")
        checkUpdatesProc.running = true;
    }

    Timer {
        interval: Config.options.updates.checkInterval * 60 * 1000
        repeat: true
        running: Config.ready && Config.options.updates.enableCheck
        onTriggered: {
            print("[Updates] Periodic update check due")
            root.refresh();
        }
    }

    Process {
        id: checkAvailabilityProc
        running: Config.ready && Config.options.updates.enableCheck
        command: ["which", "checkupdates"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            root.refresh();
        }
    }

    Process {
        id: checkUpdatesProc
        // 这段 shell 有三个必须点：
        //  1) pacman 正在装包时它持有 /var/lib/pacman/db.lck，checkupdates 和
        //     AUR helper 会一起阻塞在锁上 —— 一个检查能挂满整轮安装，
        //     期间白占进程和 IO，正是「后台装软件时桌面发卡」的来源之一。
        //     锁存在就直接沿用上次结果，不去抢锁。
        //  2) timeout 兜底：helper 卡住时不要留一个进程常驻。
        //  3) paru 优先：paru -Qua 比 yay 快不少（用户侧装的是 paru）。
        command: ["bash", "-c", `
            cache="\${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/updates-count"
            if [[ -e /var/lib/pacman/db.lck ]]; then
                cat "$cache" 2>/dev/null || echo 0
                exit 0
            fi
            pacman_n=$(timeout 30 checkupdates 2>/dev/null | wc -l)
            aur_n=0
            if command -v paru >/dev/null 2>&1; then
                aur_n=$(timeout 20 paru -Qua 2>/dev/null | wc -l)
            elif command -v yay >/dev/null 2>&1; then
                aur_n=$(timeout 20 yay -Qua 2>/dev/null | wc -l)
            fi
            total=$((pacman_n + aur_n))
            mkdir -p "$(dirname "$cache")" 2>/dev/null
            printf '%s' "$total" > "$cache" 2>/dev/null
            echo "$total"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                root.count = parseInt(text.trim())
            }
        }
    }
}
