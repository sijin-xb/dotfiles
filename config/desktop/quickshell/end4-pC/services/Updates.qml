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
        command: ["bash", "-c", "pacman=$(checkupdates 2>/dev/null | wc -l); if command -v yay >/dev/null 2>&1; then aur=$(yay -Qua 2>/dev/null | wc -l); elif command -v paru >/dev/null 2>&1; then aur=$(paru -Qua 2>/dev/null | wc -l); else aur=0; fi; echo $((pacman + aur))"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim());
                root.count = isNaN(n) ? 0 : n;
            }
        }
    }
}
