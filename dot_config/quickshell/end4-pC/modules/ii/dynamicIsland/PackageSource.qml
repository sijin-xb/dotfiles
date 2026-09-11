import QtQuick
import Quickshell
import Quickshell.Io

// 包管理活动源：跟踪 pacman / yay / paru / makepkg 的下载与 AUR 构建。
//
// 两种来源：
//  1) 自动：定时探测包管理进程，检测到即注册活动（不确定进度，进度条走固定 35%）
//  2) 手动：脚本通过 IPC 上报精确百分比
//     qs -c end4-pC ipc call island pkg_begin "安装 foo"
//     qs -c end4-pC ipc call island pkg_progress 45
//     qs -c end4-pC ipc call island pkg_end
//
// 手动模式下显示真实百分比；手动结束或未介入时退回自动探测。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    // ---- 手动上报状态 ----
    property bool manualActive: false
    property int manualPercent: 0
    property string manualLabel: ""

    // ---- 自动探测状态 ----
    property bool autoActive: false
    property string autoLabel: ""

    readonly property bool active: manualActive || autoActive
    readonly property int percent: manualActive ? manualPercent : -1
    readonly property string label: manualActive ? manualLabel : autoLabel

    function publish() {
        if (active) {
            ActivityManager.set("package", {
                percent: percent,
                label: label,
                indeterminate: percent < 0
            }, 8)
        } else {
            ActivityManager.clear("package")
        }
    }

    // ---- 手动接口（由 IPC 调用）----
    function begin(label) {
        manualActive = true
        manualPercent = 0
        manualLabel = (label && label.length > 0) ? label : "软件包"
        publish()
    }

    function progress(p) {
        if (!manualActive) {
            manualActive = true
            manualLabel = "软件包"
        }
        manualPercent = Math.max(0, Math.min(100, Math.round(p)))
        publish()
    }

    function finish() {
        if (!manualActive) return
        manualActive = false
        manualPercent = 0
        manualLabel = ""
        publish()
    }

    // ---- 自动探测 ----
    // ps 比 pgrep 更容易做「精确进程名」匹配；grep -m1 命中首个即返回。
    Process {
        id: probe
        command: ["bash", "-c",
            "ps -eo comm= 2>/dev/null | grep -m1 -E '^(pacman|yay|paru|pikaur|makepkg)$' || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim()
                const on = name.length > 0
                if (on === root.autoActive && (!on || name === root.autoLabel))
                    return
                root.autoActive = on
                root.autoLabel = on ? name : ""
                root.publish()
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!probe.running)
                probe.running = true
        }
    }
}
