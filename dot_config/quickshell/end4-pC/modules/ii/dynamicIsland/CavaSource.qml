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

    Process {
        id: cavaProc
        running: root.needOwnCava
        onRunningChanged: {
            if (!running) root.ownPoints = []
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
