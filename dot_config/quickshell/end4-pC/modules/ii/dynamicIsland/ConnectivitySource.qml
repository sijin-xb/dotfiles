import QtQuick
import qs.services

// 连接状态数据源：蓝牙设备与 WiFi 的连接 / 断开。
//
// 只关注「连接建立」和「连接断开」两个方向，不响应扫描等中间状态——
// 后者在 WiFi 场景下会高频抖动，弹提示会变成噪音。
//
// 启动时的初始值填充不算变化：蓝牙适配器与 Network 服务在加载后会从
// 默认值写入真实值，不加 prime 保护会在每次启动时误报一次。
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property bool primed: false

    readonly property int visibleDuration: 2000

    // 上一帧快照，用于判断变化方向
    property bool lastBluetoothConnected: false
    property bool lastWifiConnected: false

    readonly property bool wifiConnected: Network.wifiStatus === "connected"

    function publish(icon, label) {
        if (!IslandContext.allowTransient())
            return
        ActivityManager.pulse("connectivity", {
            icon: icon,
            label: label
        }, 25, visibleDuration, { transient: true })
    }

    function handleBluetooth() {
        const connected = BluetoothStatus.connected
        if (connected === lastBluetoothConnected)
            return
        lastBluetoothConnected = connected
        if (!primed)
            return
        const device = BluetoothStatus.primaryConnectedDevice
        const name = device?.name ?? ""
        publish(connected ? "bluetooth_connected" : "bluetooth_disabled",
                name.length > 0 ? name : Translation.tr("Bluetooth"))
    }

    function handleWifi() {
        const connected = wifiConnected
        if (connected === lastWifiConnected)
            return
        lastWifiConnected = connected
        if (!primed)
            return
        const name = Network.networkName ?? ""
        publish(connected ? "wifi" : "wifi_off",
                name.length > 0 ? name : Translation.tr("Wi-Fi"))
    }

    Connections {
        target: BluetoothStatus
        function onConnectedChanged() { root.handleBluetooth() }
    }

    Connections {
        target: Network
        function onWifiStatusChanged() { root.handleWifi() }
    }

    // 启动时先记下基线，1 秒后才开始响应变化
    Component.onCompleted: {
        lastBluetoothConnected = BluetoothStatus.connected
        lastWifiConnected = wifiConnected
        primeTimer.start()
    }

    Timer {
        id: primeTimer
        interval: 1000
        onTriggered: root.primed = true
    }
}
