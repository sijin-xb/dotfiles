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

        // 下载 / AUR 构建脚本可调用以下接口在灵动岛右侧显示进度：
        //   qs -c end4-pC ipc call island pkg_begin "安装 foo"
        //   qs -c end4-pC ipc call island pkg_progress 45
        //   qs -c end4-pC ipc call island pkg_end
        function pkg_begin(label: string): string {
            packageSource.begin(label)
            return "包任务已开始: " + label
        }
        function pkg_progress(percent: int): string {
            packageSource.progress(percent)
            return "包任务进度: " + percent + "%"
        }
        function pkg_end(): string {
            packageSource.finish()
            return "包任务已结束"
        }
    }
}
