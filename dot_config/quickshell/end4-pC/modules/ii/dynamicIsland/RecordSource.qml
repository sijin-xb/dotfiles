import QtQuick
import Quickshell
import Quickshell.Io

// 录屏数据源：读取 states.json 的 record.enable，注册 recording 活动。
// 计时用本地累加器，从检测到 enable=true 的那一刻起每秒 +1，
// 避免依赖系统时钟差值（那会在初始状态异常时算出天文数字）。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property bool recording: false
    property int elapsed: 0

    // 优先级低于 music(10)：录屏与音乐并存时主岛留给音乐，
    // 录屏改由 DynamicIsland 的左侧伴随指示器呈现（便于演示/录屏）。
    // 单独录屏时仍是最高优先活动，主岛正常显示录屏计时。
    function publish() {
        if (recording) {
            ActivityManager.set("recording", { elapsed: elapsed }, 5)
        } else {
            ActivityManager.clear("recording")
        }
    }

    FileView {
        id: stateFile
        path: `${Quickshell.env("HOME")}/.local/state/quickshell/states.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.setRecording(false)
    }

    function setRecording(on) {
        if (on && !recording) {
            elapsed = 0            // 开始新的计时
        }
        recording = on
        publish()
    }

    function parse(txt) {
        try {
            const j = JSON.parse(txt)
            setRecording(j?.record?.enable === true)
        } catch (e) {
            setRecording(false)
        }
    }

    // 每秒累加
    Timer {
        interval: 1000
        running: root.recording
        repeat: true
        onTriggered: {
            root.elapsed += 1
            root.publish()
        }
    }
}
