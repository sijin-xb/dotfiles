import QtQuick
import Quickshell.Hyprland
import qs.services

// 亮度数据源：复用 end4-pC 的 Brightness 服务（brightnessctl / ddcutil）。
// 与音量对称——跟随焦点显示器，短暂注册 brightness 活动。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property bool primed: false
    property bool holdOpen: false

    readonly property int visibleDuration: 1500

    // 跟随 Hyprland 焦点显示器。monitors 会随屏幕增减重建，
    // 所以每次按名字现查，不缓存引用。
    readonly property var focusedMonitor: {
        const name = Hyprland.focusedMonitor?.name ?? ""
        return Brightness.monitors.find(m => m.screen?.name === name) ?? null
    }
    readonly property real level: focusedMonitor?.multipliedBrightness ?? 0

    function showBrightness() {
        // 场景静默（录屏 / 专注模式）时不打扰
        if (!IslandContext.allowTransient())
            return
        ActivityManager.pulse("brightness", {
            level: Math.round(level * 100)
        }, 28, visibleDuration, { transient: true })
    }

    onHoldOpenChanged: {
        if (holdOpen)
            ActivityManager.hold("brightness")
        else if (ActivityManager.entries["brightness"] !== undefined)
            ActivityManager.release("brightness", visibleDuration)
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            // 初始化时显示器亮度从 0 填充为实际值，不该弹提示
            if (!root.primed) {
                root.primed = true
                return
            }
            root.showBrightness()
        }
    }

    Component.onCompleted: primeTimer.start()

    Timer {
        id: primeTimer
        interval: 1000
        onTriggered: root.primed = true
    }
}
