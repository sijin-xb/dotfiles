// ─────────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 移植：src/services/ScreenRecService.qml（shim，刻意只做最小实现）
//
// 为什么要 shim 而不是照搬：Brain_Shell 这个服务自己拥有整条录屏流水线
// （wf-recorder 参数、pactl 虚拟 sink 混音、通知按钮、丢弃删除文件……）。
// end4-pC 的录屏是另一套：由 scripts/videos/record.sh 触发，
// 状态写在 ~/.local/state/quickshell/states.json 的 record.enable，
// 灵动岛通过 Persistent / RecordSource 读它。两套流水线没有共同点，
// 照搬会得到一个永远录不到东西的假服务，所以这里只做转接 + 诚实降级。
//
// 真实的部分（不是伪造）：
//   recording  ← Persistent.states.record.enable（record.sh 写入的真实状态）
//   elapsed    由本地计时器在 recording 为 true 时累加（与 RecordSource 同法）
//   start/stop ← Quickshell.execDetached 调用 record.sh（真实触发录屏）
//     · captureTarget = "screen"  → 加 --fullscreen
//     · audioMic / audioSystem    → 加 --sound（record.sh 只支持"系统声"一种）
//
// 诚实的降级：
//   · captureTarget = "window"：record.sh 没有窗口录制模式，退化为区域选择
//   · discardRecording()：record.sh 没有"丢弃并删除文件"的能力，
//     这里只做停止，不会删文件（不要期待它真的删掉）
//   · audioBars：上游由录屏期间的 cava 填充，这里恒为 0（不伪造波形）
//   · captureTarget / audioMic / audioSystem 不持久化（上游写 screenrec.json，
//     这里不写盘，因为 record.sh 不读这个文件）
//
// 与同目录 ShellState 的配合（上游也有这层配合，不是新增依赖）：
//   ShellState.screenRecord 表示「捕获条已展开」，QuickSettings 置 true 后会调
//   本服务的 startRecording()；录制结束或 cancelSetup() 时由本服务把它清回 false。
// ─────────────────────────────────────────────────────────────────────────────

pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

Singleton {
    id: root

    // ── Persisted options（自持，不写盘；见文件头说明）──────────────────────
    property string captureTarget: "screen"
    property bool   audioMic:      false
    property bool   audioSystem:   false

    // ── Display helpers ───────────────────────────────────────────────────────
    readonly property var _captureIcons:  ({ screen: "󰍹", window: "󱂬", region: "󰩭" })
    readonly property var _captureLabels: ({ screen: "Screen", window: "Window", region: "Region" })
    readonly property string captureIcon:  _captureIcons[captureTarget]  ?? "󰍹"
    readonly property string captureLabel: _captureLabels[captureTarget] ?? "Screen"

    readonly property string audioLabel: {
        if (audioMic && audioSystem) return "Mic + Sys"
        if (audioMic)                return "Mic"
        if (audioSystem)             return "Sys"
        return "Non"
    }

    // ── Strip hover (open = "capture" | "audio" | "") ─────────────────────────
    property string openStrip: ""
    property real popupTargetX: 0
    property real popupTargetWidth: 0

    property var _stripTimer: Timer {
        interval: 280
        onTriggered: root.openStrip = ""
    }
    function keepStripOpen()      { _stripTimer.stop()    }
    function scheduleStripClose() { _stripTimer.restart() }

    // ── Recording state — 真实状态来源：end4-pC 的持久化状态 ─────────────────
    readonly property bool recording: Persistent.states.record.enable

    property int elapsed: 0
    property var audioBars: [0, 0, 0, 0, 0, 0]

    readonly property string elapsedDisplay: {
        var m = Math.floor(elapsed / 60)
        var s = elapsed % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    property var _elapsedTimer: Timer {
        interval: 1000
        running:  root.recording
        repeat:   true
        onTriggered: root.elapsed++
    }

    // 录屏结束后把计时归零，并收起「捕获条展开」标志
    // （上游是在 wf-recorder 退出的 onExited 里做这两件事的；
    //   这里没有 wf-recorder 进程可监听，改成跟随真实录制状态回落）
    onRecordingChanged: {
        if (!root.recording) {
            root.elapsed = 0
            ShellState.screenRecord = false
        }
    }

    // ── 控制入口 —— 全部转接到 record.sh ──────────────────────────────────────
    function startRecording() {
        if (root.recording) return
        root._toggleRecordScript()
    }

    function stopRecording() {
        if (!root.recording) return
        root._toggleRecordScript()
    }

    function discardRecording() {
        // 诚实降级：record.sh 只能"停止"，不能"停止并删除"，
        // 所以这里等价于 stopRecording()，文件会留在录像目录里。
        if (!root.recording) return
        root._toggleRecordScript()
    }

    function cancelSetup() {
        root.openStrip = ""
        // 与上游一致：取消时收起「捕获条展开」标志（QuickSettings 靠它判断
        // 录屏按钮的 on/off，不清掉的话按钮会一直停在 ON）
        ShellState.screenRecord = false
    }

    function _toggleRecordScript() {
        if (Directories.recordScriptPath === "") return
        var args = [Directories.recordScriptPath]
        // record.sh 默认是 slurp 区域选择；"screen" 对应它的 --fullscreen
        if (root.captureTarget === "screen")
            args.push("--fullscreen")
        if (root.audioMic || root.audioSystem)
            args.push("--sound")
        Quickshell.execDetached(args)
    }
}
