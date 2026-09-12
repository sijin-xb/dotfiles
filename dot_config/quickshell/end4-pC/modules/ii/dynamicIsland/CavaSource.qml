import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

// 频谱数据源。
// 优先复用底盘 MediaControls 维护的 GlobalStates.visualizerPoints
//（当 bar 配了 visualizer 时它会一直运行），避免重复启动 cava。
// 若该数据为空（例如 bar 未配 visualizer），则自己兜底启动一个 cava。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property bool active: false

    readonly property list<real> sharedPoints: GlobalStates.visualizerPoints
    property list<real> ownPoints: []

    // 共享数据非空则用共享，否则用自己兜底的
    readonly property list<real> points: sharedPoints.length > 0 ? sharedPoints : ownPoints

    // 仅在“激活 且 共享数据为空”时才自开 cava
    readonly property bool needOwnCava: active && sharedPoints.length === 0

    // cava 启动失败（二进制缺失 / 配置错误）后置位。
    // 不加这个的话，running 绑定会在进程退出后立刻把它重新拉起，
    // 形成「启动 → 秒退 → 再启动」的死循环。
    property bool cavaFailed: false

    // 不再需要自开 cava 时清除失败标记，下次激活允许重试
    onNeedOwnCavaChanged: {
        if (!needOwnCava)
            cavaFailed = false
    }

    Process {
        id: cavaProc
        running: root.needOwnCava && !root.cavaFailed
        onRunningChanged: {
            if (!running) root.ownPoints = []
        }
        onExited: (exitCode, exitStatus) => {
            // 非零退出说明 cava 有问题；标记后不再自动重启
            if (exitCode !== 0)
                root.cavaFailed = true
        }
        command: ["cava", "-p", `${Directories.scriptPath}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                const pts = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p))
                root.ownPoints = pts
            }
        }
    }
}
