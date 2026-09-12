import QtQuick
import qs.services

// 电池数据源：插拔电源、低电量、充满。
//
// Battery 服务本身已经发系统通知与提示音，这里不重复它的所有事件，
// 只挑三个「用户需要立刻知道」的时刻做视觉强化：
//   - 插上 / 拔掉电源：即时反馈，无需等待
//   - 进入低电量：需要用户做决定
//   - 充满：可以拔线了
//
// 优先级压到 3（低于 privacy 4）：多数时候桌面上有音乐或任务活动，
// 这时电池提示不会抢主岛，避免与系统通知同时轰炸。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property bool primed: false

    readonly property int visibleDuration: 2500

    // 上一帧快照
    property bool lastPluggedIn: false
    property bool lastLow: false
    property bool lastFull: false

    readonly property int percent: Math.round((Battery.percentage ?? 0) * 100)
    readonly property string iconName: {
        if (Battery.isCharging)
            return "battery_charging_full"
        const level = root.percent
        if (level >= 90) return "battery_full"
        if (level >= 60) return "battery_5_bar"
        if (level >= 40) return "battery_4_bar"
        if (level >= 20) return "battery_3_bar"
        return "battery_1_bar"
    }

    function publish(icon, label) {
        if (!IslandContext.allowTransient())
            return
        ActivityManager.pulse("battery", {
            icon: icon,
            label: label,
            percent: root.percent
        }, 3, visibleDuration, { transient: true })
    }

    function handleState() {
        // 非笔记本（台式机）没有电池，整体跳过
        if (!Battery.available)
            return

        const plugged = Battery.isPluggedIn
        const low = Battery.isLowAndNotCharging
        const full = Battery.isFullAndCharging

        const pluggedChanged = plugged !== lastPluggedIn
        const lowChanged = low !== lastLow
        const fullChanged = full !== lastFull

        lastPluggedIn = plugged
        lastLow = low
        lastFull = full

        // 启动时的初始填充不算事件
        if (!primed)
            return

        // 低电量优先于插拔：同一帧里两者都可能为真时，用户更需要知道电量告急
        if (lowChanged && low) {
            publish("battery_alert", Translation.tr("Low battery"))
            return
        }
        if (fullChanged && full) {
            publish("battery_full", Translation.tr("Battery full"))
            return
        }
        if (pluggedChanged) {
            publish(root.iconName,
                    plugged ? Translation.tr("Charger connected")
                            : Translation.tr("Charger disconnected"))
        }
    }

    Connections {
        target: Battery
        function onIsPluggedInChanged() { root.handleState() }
        function onIsLowAndNotChargingChanged() { root.handleState() }
        function onIsFullAndChargingChanged() { root.handleState() }
    }

    Component.onCompleted: {
        lastPluggedIn = Battery.isPluggedIn
        lastLow = Battery.isLowAndNotCharging
        lastFull = Battery.isFullAndCharging
        primeTimer.start()
    }

    Timer {
        id: primeTimer
        interval: 1000
        onTriggered: root.primed = true
    }
}
