/**
 * 从 Brain_Shell 的 src/modules/Center/FanPanel.qml 移植，但做的是**只读降级版**。
 *
 * ── 为什么要降级 ─────────────────────────────────────────────────────────────
 * 原版 FanPanel 依赖 FanControl 服务：`service.mode` 读当前档位，`service.setMode()`
 * 往 hwmon 的 pwm 通道写值来切 Quiet / Auto / Max。本次移植不含 FanControl
 * （用户是 AMD 独显机器，没有可写的风扇调速通道，写 pwm 只会拿到权限错误），
 * 所以那三个档位按钮被移除 —— 没有后端却留着按钮，就是三个点了没反应的假按钮。
 *
 * ── 降级后的行为 ─────────────────────────────────────────────────────────────
 *   1) 保留对外属性 `service`（默认 null），DashStats 传或不传都不影响显示；
 *      本组件当前不读取它，保留只为兼容 Brain_Shell 的调用写法。
 *   2) 转速改成直接读 sysfs：/sys/class/hwmon/hwmon1/fan1_input（用户机器上
 *      存在的只读节点）。sysfs 属性变化不触发 inotify，所以不用 watchChanges，
 *      改用 FileView + 1 秒轮询 Timer 调 reload()。
 *   3) 显示沿用 Brain_Shell 自己的仪表语言：一个 size 0.60 的 Speedometer，
 *      参数与 TempPanel 里那颗 "Fan 1" 表盘完全一致（同样是 rpm/5500 的百分比、
 *      >999 显示成 "1.2k"、rpm 为 0 时置灰显示 Off）。不另造新样式。
 *   4) 原版顶部的 "Fan Control" 标题不再保留：已经不能控制了，标题留着是误导。
 */
import QtQuick
import Quickshell.Io

Item {
    id: root

    // 兼容 Brain_Shell 的调用方式；当前实现不消费它（见文件头降级说明）
    property var    service:    null
    // 转速来源，按用户机器上的实际节点写死
    property string fanPath:    "/sys/class/hwmon/hwmon1/fan1_input"
    // 只用于把 rpm 换算成表盘百分比，沿用 Brain_Shell 的 5500
    property int    maxFanRpm:  5500

    // 当前转速（rpm），由下面的 FileView 刷新
    property int    rpm:        0

    readonly property real s: 0.60

    function parseRpm(raw) {
        const v = parseInt(String(raw).trim())
        return (isNaN(v) || v < 0) ? 0 : v
    }

    FileView {
        id: fanFile
        path: root.fanPath
        // 故意不开 watchChanges：sysfs 属性变化不走 inotify，
        // 开了只会拿到一个永远不触发的 watch（还可能在日志里刷错误），
        // 刷新完全交给下面的 pollTimer。
        onLoaded: root.rpm = root.parseRpm(fanFile.text())
        // 节点不存在 / 读不到时按 0 处理，表盘自动置灰，不报错刷屏
        onLoadFailed: root.rpm = 0
    }

    Timer {
        id: pollTimer
        interval: 1000
        running:  true
        repeat:   true
        onTriggered: fanFile.reload()
    }

    Speedometer {
        anchors.centerIn: parent
        size:        root.s
        label:       ""
        percent:     Math.min(100, root.rpm / root.maxFanRpm * 100)
        centerText:  root.rpm > 999
                         ? (root.rpm / 1000).toFixed(1) + "k"
                         : root.rpm + ""
        bottomText:  "Fan 1"
        active:      root.rpm > 0
        accentColor: "#89dceb"
    }
}
