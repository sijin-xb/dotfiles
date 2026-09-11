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

        implicitWidth: 360
        implicitHeight: 180

        mask: Region { item: island.pillItem }

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
        }
    }

    // 活动切换时收起展开态
    Connections {
        target: ActivityManager
        function onCurrentTypeChanged() {
            root.expanded = false
        }
    }

    // ---- IPC：调试 ----
    IpcHandler {
        target: "island"
        function status(): string {
            return "当前: " + ActivityManager.currentType + " | 队列: " + ActivityManager.debugList()
        }
    }
}
