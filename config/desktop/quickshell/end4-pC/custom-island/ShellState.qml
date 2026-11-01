// ─────────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 移植：src/state/ShellState.qml（shim，非逐字照搬）
//
// 改动：
//   1. 删除 `import "../."` 与 Quickshell.Services.UPower（改用 end4-pC 的
//      Battery 服务），根类型 QtObject → Singleton。
//   2. 删掉 Brain_Shell 专属的内部实现（KeybindService 拦截 / hyprctl submap、
//      读 src/user_data/config_Provider.json）。这两个东西在 end4-pC 里没有
//      对应物，且不是仪表盘需要的公开 API。
//   3. 能转接到 end4-pC 现有服务的字段就转接（见下），其余自己持有。
//
// 字段来源一览（"转接" = 绑定到 end4-pC 的权威服务；"自持" = GlobalStates
// 和 services/ 里都没有等价物，由本 shim 自己维护最小状态）：
//   screenRecord  自持 —— 语义与上游一致：「录屏捕获条已展开」的 UI 状态，
//     由 QuickSettings 置 true、ScreenRecService.cancelSetup() 置 false。
//     注意它**不是**真实录制状态；真实录制状态看 ScreenRecService.recording
//     （那个才是转接 Persistent.states.record.enable 的）。
//   dnd           双向转接 Notifications.silent（见下方 onDndChanged / Connections）
//   wifiOn        转接 Network.wifiEnabled
//   btPowered     转接 BluetoothStatus.enabled
//   btConnected   转接 BluetoothStatus.connected
//   hasBattery    转接 Battery.available
//   focusMode     自持（end4-pC 无"专注模式"概念）
//   vpnActive / vpnConnecting / vpnName  自持（Network 服务没有 VPN 字段）
//   hotspot / airplane                   自持
//   topBarLWidth / topBarCWidth / topBarRWidth  自持（end4-pC 的 bar 宽度由
//     bar 模块自己算，GlobalStates 里没有这三个字段；岛屿宿主也不读它们）
//   configProvider 自持（上游用于 hyprctl 的 lua/conf 分支；QuickSettings 会读它，
//     这里默认 "conf"，即走 hyprctl keyword 分支）
//
// 注意：除 dnd 是双向转接外，其余"转接"字段都是「可写 + 绑定」。
// 如果移植过来的组件直接给它们赋值，QML 会打断绑定（不报错），
// 此后该字段就不再跟随真实服务。QuickSettings 确实会写 wifiOn / btPowered /
// btConnected / hotspot / focusMode —— 这与上游 Brain_Shell 的写法一致，
// 那几个字段本来就以 QuickSettings 为准。
// ─────────────────────────────────────────────────────────────────────────────

pragma Singleton
import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    // ── 布局宽度（自持）───────────────────────────────────────────────────────
    property int topBarLWidth: 0
    property int topBarCWidth: 0
    property int topBarRWidth: 0

    // ── 开关状态 ──────────────────────────────────────────────────────────────
    property bool focusMode:    false
    // 捕获条展开状态（UI 态，非录制态；录制态见 ScreenRecService.recording）
    property bool screenRecord: false
    property bool hotspot:      false
    property bool airplane:     false

    // DND：end4-pC 的权威状态是 Notifications.silent（它决定 popupInhibited）。
    // 这里做双向转接：本属性变化时写回 Notifications.silent，
    // Notifications.silent 被别处改动时同步回本属性。
    // 只写单向绑定的话，QuickSettings 的 `ShellState.dnd = !ShellState.dnd`
    // 会打断绑定，按钮看起来能点、实际不会真的静音通知。
    property bool dnd: Notifications.silent
    onDndChanged: {
        if (Notifications.silent !== root.dnd)
            Notifications.silent = root.dnd
    }
    property var _dndConn: Connections {
        target: Notifications
        function onSilentChanged() {
            if (root.dnd !== Notifications.silent)
                root.dnd = Notifications.silent
        }
    }

    // WiFi — false when radio is off OR hotspot is using the interface
    property bool wifiOn:       Network.wifiEnabled

    // VPN — 自持：end4-pC 的 Network 服务没有 VPN 相关字段
    property bool   vpnActive:     false
    property bool   vpnConnecting: false
    property string vpnName:       ""

    // Bluetooth — 转接 BluetoothStatus（比上游的 5s 轮询更实时）
    property bool btPowered:   BluetoothStatus.enabled
    property bool btConnected: BluetoothStatus.connected

    // ── Hardware Detection ──────────────────────────────────────────────────
    property bool hasBattery: Battery.available

    // ── Config provider（自持，仅为兼容上层引用）────────────────────────────
    property string configProvider: "conf"
}
