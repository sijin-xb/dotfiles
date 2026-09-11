import QtQuick
import qs.services

// 音量数据源：复用 end4-pC 的 Audio 服务（Pipewire）。
// 监听音量/静音变化，短暂注册 volume 活动，2 秒后清除。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property bool primed: false
    property real lastLevel: -1
    property bool lastMuted: false

    // 展开音量活动时置 true：暂停自动隐藏，否则用户还没看清就消失了。
    property bool holdOpen: false

    function showVolume() {
        ActivityManager.set("volume", {
            level: Math.round((Audio.value ?? 0) * 100),
            isMuted: Audio.sink?.audio?.muted ?? false
        }, 30)
        hideTimer.restart()
    }

    // 展开期间不隐藏；收起时重新起计时。
    onHoldOpenChanged: {
        if (holdOpen)
            hideTimer.stop()
        else if (ActivityManager.entries["volume"] !== undefined)
            hideTimer.restart()
    }

    Connections {
        target: Audio.sink?.audio ?? null
        ignoreUnknownSignals: true
        function onVolumeChanged() {
            if (!Audio.ready) return
            if (!root.primed) {
                root.primed = true
                return
            }
            root.showVolume()
        }
        function onMutedChanged() {
            if (!Audio.ready) return
            if (!root.primed) {
                root.primed = true
                return
            }
            root.showVolume()
        }
    }

    Component.onCompleted: {
        // 启动后延迟一秒再标记为就绪，避免初始化时误弹
        primeTimer.start()
    }

    Timer {
        id: primeTimer
        interval: 1000
        onTriggered: root.primed = true
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: {
            if (!root.holdOpen)
                ActivityManager.clear("volume")
        }
    }
}
