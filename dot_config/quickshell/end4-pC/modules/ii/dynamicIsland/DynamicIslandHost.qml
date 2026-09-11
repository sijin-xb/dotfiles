import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// 灵动岛宿主：负责窗口、数据源与信号连接。
// shell.qml 只需一行 `DynamicIslandHost {}`。
Item {
    id: root

    property bool expanded: false
    property var lyricsProvider: null

    // ---- 数据源 ----
    MprisSource { id: mprisSource }
    VolumeSource { id: volumeSource }
    RecordSource { id: recordSource }
    PackageSource { id: packageSource }
    DownloadSource { id: downloadSource }
    NotificationSource { id: notificationSource }

    // 封面取色：量化当前歌曲封面，得到主色供灵动岛着色。
    ArtColorSource {
        id: artColor
        artUrl: (ActivityManager.currentType === "music")
            ? (ActivityManager.currentPayload.artUrl ?? "") : ""
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

        WlrLayershell.namespace: "quickshell:dynamicIsland"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors { top: true }
        margins { top: 62 }

        // 加宽以容纳主岛两侧的伴随指示器（左：录屏；右：包管理）
        implicitWidth: 640
        implicitHeight: 180

        mask: Region { item: island.contentMaskItem }

        DynamicIsland {
            id: island
            anchors.fill: parent
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
            return "当前: " + ActivityManager.currentType + " | 队列: " + ActivityManager.debugList()
        }

        // 通用任务进度上报。taskId 取数据源 id（"package" / "download"）：
        //   qs -c end4-pC ipc call island task_begin "下载 foo.iso" download
        //   qs -c end4-pC ipc call island task_progress 42 download
        //   qs -c end4-pC ipc call island task_end download
        function taskSourceFor(id) {
            switch (id) {
            case "package":  return packageSource
            case "download": return downloadSource
            default:         return null
            }
        }

        function task_begin(label: string, taskId: string): string {
            const s = taskSourceFor(taskId)
            if (!s) return "未知任务类型: " + taskId
            s.begin(label)
            return taskId + " 任务已开始: " + label
        }
        function task_progress(percent: int, taskId: string): string {
            const s = taskSourceFor(taskId)
            if (!s) return "未知任务类型: " + taskId
            s.progress(percent)
            return taskId + " 任务进度: " + percent + "%"
        }
        function task_end(taskId: string): string {
            const s = taskSourceFor(taskId)
            if (!s) return "未知任务类型: " + taskId
            s.finish()
            return taskId + " 任务已结束"
        }

        // 包管理旧接口（保留兼容）
        function pkg_begin(label: string): string { return task_begin(label, "package") }
        function pkg_progress(percent: int): string { return task_progress(percent, "package") }
        function pkg_end(): string { return task_end("package") }
    }
}
