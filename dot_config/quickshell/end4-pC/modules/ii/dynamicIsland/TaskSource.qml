import QtQuick
import Quickshell
import Quickshell.Io

// 通用长任务数据源：把「进程自动探测」和「脚本主动上报进度」两套机制收在一起。
//
// 使用方只需声明 taskId / processNames / priority / icon，就能得到一个活动源：
//   - 检测到列表里的进程在跑 → 自动显示（进度未知，走不确定态动画）
//   - 脚本用 IPC 上报 → 显示精确百分比
//
// 活动以 taskId 注册到 ActivityManager，UI 侧按同一 id 渲染。
// 具体任务类型见 PackageSource / DownloadSource。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    // ---- 配置（由使用方覆盖）----
    property string taskId: ""
    property var processNames: []
    property int priority: 8
    property string defaultLabel: "任务"
    property string icon: "download"
    property bool autoProbeEnabled: true
    // 任务分组：同组任务在副岛合并渲染（多个下载 → 一个胶囊）。
    // 留空则不参与合并。
    property string group: "task"

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
        if (taskId.length === 0)
            return
        if (active) {
            ActivityManager.set(taskId, {
                percent: percent,
                label: label,
                icon: icon,
                indeterminate: percent < 0
            }, priority, { group: group })
        } else {
            ActivityManager.clear(taskId)
        }
    }

    // ---- 手动接口（由 IPC 调用）----
    function begin(label) {
        manualActive = true
        manualPercent = 0
        manualLabel = (label && label.length > 0) ? label : defaultLabel
        publish()
    }

    function progress(p) {
        if (!manualActive) {
            manualActive = true
            manualLabel = defaultLabel
        }
        manualPercent = Math.max(0, Math.min(100, Math.round(p)))
        publish()
    }

    function finish() {
        if (!manualActive)
            return
        manualActive = false
        manualPercent = 0
        manualLabel = ""
        publish()
    }

    // ---- 自动探测 ----
    // 进程表由共享的 ProcessProbe 维护（单次 ps 覆盖所有任务类型），
    // 这里只负责把「本类型关心的进程名」映射成活动状态。
    readonly property bool probeEnabled: autoProbeEnabled && processNames.length > 0

    // 命中列表里第一个在跑的进程名；没命中返回空串。
    readonly property string matchedProcess: {
        if (!probeEnabled)
            return ""
        for (let i = 0; i < processNames.length; i++) {
            const name = processNames[i]
            if (ProcessProbe.isRunning(name))
                return name
        }
        return ""
    }

    onMatchedProcessChanged: {
        const name = matchedProcess
        const on = name.length > 0
        if (on === autoActive && (!on || name === autoLabel))
            return
        autoActive = on
        autoLabel = name
        publish()
    }

    // 订阅共享探测器：组件存活期间保持订阅，销毁时退订。
    Component.onCompleted: {
        if (probeEnabled)
            ProcessProbe.subscribe()
    }
    Component.onDestruction: {
        if (probeEnabled)
            ProcessProbe.unsubscribe()
    }
}
