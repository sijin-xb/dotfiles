import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
// Persistent 单例在 modules/common 下，不导入的话持久化会静默抛
// ReferenceError（ActivityManager 等同目录文件靠 QML 隐式目录导入才可用）
import qs.modules.common

// 灵动岛宿主：负责窗口、数据源与信号连接。
// shell.qml 只需一行 `DynamicIslandHost {}`。
Item {
    id: root

    property bool expanded: false
    property var lyricsProvider: null

    // 任务 id → 数据源的映射。放在 root 层而不是 IpcHandler 内部：
    // IpcHandler 会检查自身所有成员，var/QVariant 无法跨 IPC 会报解析错误。
    readonly property var taskSources: ({
        "package":  packageSource,
        "download": downloadSource
    })

    // ---- 数据源 ----
    MprisSource { id: mprisSource }
    VolumeSource { id: volumeSource }
    BrightnessSource { id: brightnessSource }
    RecordSource { id: recordSource }
    PackageSource { id: packageSource }
    DownloadSource { id: downloadSource }
    NotificationSource { id: notificationSource }
    PrivacySource { id: privacySource }

    // 封面取色：量化当前歌曲封面，得到主色供灵动岛着色。
    // 结果同时写入 IslandPalette，使主色成为全局共享状态。
    ArtColorSource {
        id: artColor
        artUrl: (ActivityManager.currentType === "music")
            ? (ActivityManager.currentPayload.artUrl ?? "") : ""
        onDominantColorChanged: IslandPalette.mediaAccent = dominantColor
    }

    // 音量 / 通知活动展开时暂停它们的自动隐藏，否则展开态还没看清就消失了。
    // 用 renderType 而不是 currentType：点副岛胶囊会聚焦到该活动，但
    // currentType 仍是优先级最高的那个（比如音乐），两者并不相同。
    Binding {
        target: volumeSource
        property: "holdOpen"
        value: (island.renderType === "volume" && root.expanded)
    }
    Binding {
        target: brightnessSource
        property: "holdOpen"
        value: (island.renderType === "brightness" && root.expanded)
    }
    Binding {
        target: notificationSource
        property: "holdOpen"
        value: (island.renderType === "notification" && root.expanded)
    }

    // cava 可视化数据：仅音乐活动且播放中时运行
    CavaSource {
        id: cavaSource
        active: ActivityManager.currentType === "music"
            && (ActivityManager.currentPayload.isPlaying ?? false)
    }

    PanelWindow {
        id: window
        screen: Quickshell.screens[0] ?? null
        color: "transparent"

        // 右键拖动偏移：持久化保存，重启后保持位置。
        // 窗口不直接绑定 Persistent（拖动时要写它），改为就绪后一次性恢复。
        property real xOffset: 0
        property real yOffset: 0

        readonly property real screenW: screen ? screen.width : 1920
        readonly property real screenH: screen ? screen.height : 1080

        // 拖动范围按岛（含副岛）的当前实际尺寸动态限制，避免拖出屏幕后找不回来。
        readonly property real contentW: island.contentMaskItem ? island.contentMaskItem.width : 0
        readonly property real contentH: island.contentMaskItem ? island.contentMaskItem.height : 0
        readonly property real maxXOffset: Math.max(0, (screenW - contentW) / 2)
        readonly property real maxYOffset: Math.max(0, screenH - contentH - island.baseTop)
        readonly property real clampedX: Math.max(-maxXOffset, Math.min(maxXOffset, xOffset))
        readonly property real clampedY: Math.max(-island.baseTop, Math.min(maxYOffset, yOffset))

        function restoreOffset() {
            window.xOffset = Persistent.states.island.xOffset ?? 0
            window.yOffset = Persistent.states.island.yOffset ?? 0
        }

        Component.onCompleted: if (Persistent.ready) restoreOffset()
        Connections {
            target: Persistent
            function onReadyChanged() {
                if (Persistent.ready) window.restoreOffset()
            }
        }

        WlrLayershell.namespace: "quickshell:dynamicIsland"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        // 全屏透明窗口，输入只留给岛本身（mask）。拖动只移动窗口内的岛，
        // 不动 layer-shell 窗口本身：改 margins 会让 Hyprland 反复重配 surface，
        // 指针事件坐标系跟着窗口跳变，拖动会抖甚至乱飞（桌宠同款方案）。
        anchors { top: true; left: true; right: true; bottom: true }

        mask: Region { item: island.contentMaskItem }

        DynamicIsland {
            id: island
            anchors.fill: parent
            offsetX: window.clampedX
            offsetY: window.clampedY
            activityType: ActivityManager.currentType
            expanded: root.expanded
            payload: ActivityManager.currentPayload
            visualizerPoints: cavaSource.points
            lyricsProvider: root.lyricsProvider
            accentColor: artColor.dominantColor
            onActivated: {
                if (ActivityManager.currentType === "recording") {
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.config/quickshell/end4-pC/scripts/videos/record.sh"])
                } else {
                    root.expanded = !root.expanded
                }
            }
            onMusicPrev: mprisSource.previous()
            onMusicPlayPause: mprisSource.togglePlay()
            onMusicNext: mprisSource.next()
            // 点击左侧录屏伴随指示器：再跑一次 record.sh（其内部 pgrep 到 wf-recorder 就会停止并写回状态）
            onRecordingStopRequested: {
                Quickshell.execDetached([Quickshell.env("HOME") + "/.config/quickshell/end4-pC/scripts/videos/record.sh"])
            }
            // 点击歌词页某一行：跳到该行时间点（绝对定位）
            onSeekRequested: (seconds) => mprisSource.seekTo(seconds)
            // 点击副岛胶囊：展开主岛，让该活动的展开态可见
            onExpandRequested: root.expanded = true
            // 右键拖动：增量位移累加到当前偏移（贴屏幕边缘拖动时以 clamped
            // 值为基准，避免把 offset 累加到边界之外），并写回持久化。
            onDragMoveRequested: (dx, dy) => {
                window.xOffset = window.clampedX + dx
                window.yOffset = window.clampedY + dy
                Persistent.states.island.xOffset = window.xOffset
                Persistent.states.island.yOffset = window.yOffset
            }
        }
    }

    // 活动切换时收起展开态
    Connections {
        target: ActivityManager
        function onCurrentTypeChanged() {
            root.expanded = false
        }
    }

    // ---- IPC：调试 + 包管理进度上报 ----
    IpcHandler {
        target: "island"
        function status(): string {
            return "当前: " + ActivityManager.currentType
                + " | 场景: " + ActivityManager.scene
                + " | 静默: " + (IslandContext.silentMode ? "开" : "关")
                + " | 队列: " + ActivityManager.debugList()
        }

        // 专注模式：静默音量 / 亮度 / 通知等瞬态活动。
        //   qs -c end4-pC ipc call island silent_on
        //   qs -c end4-pC ipc call island silent_off
        //   qs -c end4-pC ipc call island silent_toggle
        function silent_on(): string {
            IslandContext.setSilentMode(true)
            return "专注模式已开启"
        }
        function silent_off(): string {
            IslandContext.setSilentMode(false)
            return "专注模式已关闭"
        }
        function silent_toggle(): string {
            IslandContext.setSilentMode(!IslandContext.silentMode)
            return "专注模式: " + (IslandContext.silentMode ? "开" : "关")
        }

        // 通用任务进度上报。taskId 取数据源 id（"package" / "download"）：
        //   qs -c end4-pC ipc call island task_begin "下载 foo.iso" download
        //   qs -c end4-pC ipc call island task_progress 42 download
        //   qs -c end4-pC ipc call island task_end download
        function task_begin(label: string, taskId: string): string {
            const s = root.taskSources[taskId] ?? null
            if (!s) return "未知任务类型: " + taskId
            s.begin(label)
            return taskId + " 任务已开始: " + label
        }
        function task_progress(percent: int, taskId: string): string {
            const s = root.taskSources[taskId] ?? null
            if (!s) return "未知任务类型: " + taskId
            s.progress(percent)
            return taskId + " 任务进度: " + percent + "%"
        }
        function task_end(taskId: string): string {
            const s = root.taskSources[taskId] ?? null
            if (!s) return "未知任务类型: " + taskId
            s.finish()
            return taskId + " 任务已结束"
        }

        // 重置灵动岛位置（拖出屏幕后可用）：
        //   qs -c end4-pC ipc call island reset_position
        function reset_position(): string {
            try {
                window.xOffset = 0
                window.yOffset = 0
                Persistent.states.island.xOffset = 0
                Persistent.states.island.yOffset = 0
                return "灵动岛位置已重置"
            } catch (e) {
                return "重置失败: " + e
            }
        }

        // 包管理旧接口（保留兼容）
        function pkg_begin(label: string): string { return task_begin(label, "package") }
        function pkg_progress(percent: int): string { return task_progress(percent, "package") }
        function pkg_end(): string { return task_end("package") }
    }
}
