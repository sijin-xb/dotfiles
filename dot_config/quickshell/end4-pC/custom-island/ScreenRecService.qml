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
//
// 录屏选项（captureTarget / audioMic / audioSystem）的单一数据源：
//   Config.options.screenRecord（见 modules/common/Config.qml），不再是本文件
//   自持的内存状态。写入方是灵动岛的两个入口 —— 展开面板的「录屏」设置区
//   （QuickSettings.qml）和收起态捕获条上的循环切换（CenterContent.qml）；
//   scripts/videos/record.sh 也用 jq 直接读同一个 config.json。
//
// 与同目录 ShellState 的配合（上游也有这层配合，不是新增依赖）：
//   ShellState.screenRecord 表示「捕获条已展开」，QuickSettings 置 true 后会调
//   本服务的 startRecording()；录制结束或 cancelSetup() 时由本服务把它清回 false。
// ─────────────────────────────────────────────────────────────────────────────

pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common
// ⚠ Translation（下面几个 label 函数要用）住在 qs.services 下，不在
// qs.modules.common 里 —— 少了这行会在启动日志里抛
// "ReferenceError: Translation is not defined"，而且因为是在属性初始化阶段，
// 报错之后值会静默变成空字符串，界面上只表现为「文字凭空不见了」。
import qs.services

Singleton {
    id: root

    // ── 录屏选项 —— 单一数据源：Config.options.screenRecord ──────────────────
    // 只读派生属性：**不要给它们赋值**，那样只会打断绑定、配置不会变。
    // 要改就写 Config.options.screenRecord.*（下面的 cycle* 函数就是这么做的）。
    readonly property string captureTarget: Config.options.screenRecord.captureTarget
    readonly property bool   audioMic:      Config.options.screenRecord.audioMic
    readonly property bool   audioSystem:   Config.options.screenRecord.audioSystem
    readonly property string quality:       Config.options.screenRecord.quality

    // ── Display helpers ───────────────────────────────────────────────────────
    readonly property var _captureIcons:  ({ screen: "󰍹", window: "󱂬", region: "󰩭" })
    readonly property string captureIcon:  _captureIcons[captureTarget]  ?? "󰍹"

    // ── 文案 ─────────────────────────────────────────────────────────────────
    // 用**函数**而不是属性：Translation.tr() 读的是 Translation 单例的
    // translations 属性，放在函数体里同样能被 QML 的依赖追踪覆盖到，语言一变
    // 就会重算；而写成属性的话，只在初始化时求值一次，热切语言不会跟着刷新。
    // （真正踩过的坑是上面那条 import —— 少了 qs.services 时这里会抛
    //   ReferenceError，属性初始化阶段报错会静默退化成空字符串，
    //   表现就是捕获条上只剩图标和 ▾，文字整段消失。）
    function captureLabel() {
        return ({ screen: Translation.tr("Screen"),
                  window: Translation.tr("Window"),
                  region: Translation.tr("Region") })[root.captureTarget]
               ?? Translation.tr("Screen")
    }

    function audioLabel() {
        if (root.audioMic && root.audioSystem) return Translation.tr("Microphone + System")
        if (root.audioMic)                     return Translation.tr("Microphone")
        if (root.audioSystem)                  return Translation.tr("System Audio")
        return Translation.tr("No Audio")
    }

    // ── 捕获条上的循环切换 ───────────────────────────────────────────────────
    // 上游这里配的是一对 hover 展开的下拉弹层（openStrip + popupTargetX…）。
    // 移植时弹层没做，于是按钮悬停只会变个色、点下去什么都不发生 ——
    // captureTarget / audioMic / audioSystem 三项因此在界面上完全没有入口。
    // 现在改成点击直接切下一项：三项以内循环比弹层更快，也省掉一整套浮层定位。
    readonly property var _captureOrder: ["screen", "region", "window"]
    function cycleCaptureTarget() {
        var i = root._captureOrder.indexOf(root.captureTarget)
        Config.options.screenRecord.captureTarget =
            root._captureOrder[(i + 1) % root._captureOrder.length]
    }

    // 无 → 系统声 → 麦克风 → 无
    function cycleAudio() {
        var mic = root.audioMic, sys = root.audioSystem
        if (!mic && !sys)     { Config.options.screenRecord.audioSystem = true }
        else if (sys && !mic) { Config.options.screenRecord.audioSystem = false
                                Config.options.screenRecord.audioMic    = true }
        else if (mic && !sys) { Config.options.screenRecord.audioMic    = false }
        else                  { Config.options.screenRecord.audioSystem = false }
    }

    // ── 画质 ─────────────────────────────────────────────────────────────────
    // 本文件只负责"改"，真正的映射在 record.sh 里 —— 它读 config.json 的
    // screenRecord.quality，翻成 libx264 的 crf / preset（见 record.sh 的
    // QUALITY 段）。这里不重复定义一遍数值，避免两处漂移。
    // 同 captureLabel()：函数式求值，语言热切换时能跟着刷新
    function qualityLabel() {
        return ({ high:   Translation.tr("High"),
                  medium: Translation.tr("Medium"),
                  low:    Translation.tr("Low") })[root.quality]
               ?? Translation.tr("Medium")
    }

    readonly property var _qualityOrder: ["low", "medium", "high"]
    function cycleQuality() {
        var i = root._qualityOrder.indexOf(root.quality)
        Config.options.screenRecord.quality =
            root._qualityOrder[(i + 1) % root._qualityOrder.length]
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
        // record.sh 默认是 slurp 区域选择；"screen" 对应它的 --fullscreen。
        // "window" 没有对应参数 —— record.sh 没有窗口录制模式，会退化成区域选择。
        if (root.captureTarget === "screen")
            args.push("--fullscreen")
        // 音频：两者都开时优先系统声（wf-recorder 只吃一个 --audio，见 record.sh）
        if (root.audioSystem)
            args.push("--sound")
        else if (root.audioMic)
            args.push("--mic")
        Quickshell.execDetached(args)
    }
}
