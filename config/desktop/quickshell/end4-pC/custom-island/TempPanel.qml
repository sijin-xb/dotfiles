/**
 * 从 Brain_Shell 的 src/modules/Center/TempPanel.qml 移植。
 * 改动：仅删掉 `import "../../"` 与 `import "../../components"`；其余逐字保留。
 *       service 由 ThermalService 提供（并行移植，保持 Brain_Shell 的属性形状：
 *       cpuTemp / cpuTempStr / gpuTemp / gpuTempStr / fanCount / fan1Rpm / fan2Rpm）。
 */
import QtQuick

Item {
    id: root

    required property var  service
    property bool          dgpuActive: false
    property string        fanMode:    "quiet"
    property int           maxFanRpm:  5500

    // ⚠ 与上游的差异（必要新增）：
    // Brain_Shell 里 FanPanel 是「风扇控制器」，温度卡顺带显示 Fan1/Fan2 转速
    // 不重复。end4-pC 这边 FanPanel 降级成只读转速表（见 FanPanel.qml 文件头），
    // 于是同一个 Fan1 会在温度卡和风扇卡里各画一遍。
    // 而且 4 个表盘并排要 241px 宽，系统页加了进程卡之后温度卡只有 ~190px，
    // 内部 Row 用 horizontalCenter 居中，塞不下就向两侧溢出、压到邻居卡上。
    // 所以给 DashStats 一个开关，让它把风扇表盘关掉，只留 CPU/GPU。
    // 默认 true —— 保持与上游完全一致的行为，只有显式传 false 才变。
    property bool          showFans:   true

    function tempColor(t) {
        if (t >= 90) return "#f38ba8"
        if (t >= 75) return "#f5c47a"
        if (t >= 60) return "#fab387"
        return Theme.active
    }

    readonly property real s: 0.60

    // ── Speedometers — anchored left ──────────────────────────────────────────
    Row {
        id: speedoRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: parent.width * 0.05

        Speedometer {
            size:        root.s
            label:       ""
            percent:     Math.min(100, service.cpuTemp)
            centerText:  service.cpuTempStr
            bottomText:  "CPU"
            active:      true
            accentColor: root.tempColor(service.cpuTemp)
        }

        Speedometer {
            size:        root.s
            label:       ""
            percent:     root.dgpuActive ? Math.min(100, service.gpuTemp) : 0
            centerText:  root.dgpuActive ? service.gpuTempStr : "—"
            bottomText:  "GPU"
            active:      root.dgpuActive
            accentColor: root.tempColor(service.gpuTemp)
        }

        Rectangle {
            width:  1
            height: parent.height * 0.7
            anchors.verticalCenter: parent.verticalCenter
            color:  Qt.rgba(1, 1, 1, 0.08)
        }

        Speedometer {
            visible:     root.showFans && service.fanCount >= 1
            size:        root.s
            label:       ""
            percent:     Math.min(100, service.fan1Rpm / root.maxFanRpm * 100)
            centerText:  service.fan1Rpm > 999
                             ? (service.fan1Rpm / 1000).toFixed(1) + "k"
                             : service.fan1Rpm + ""
            bottomText:  "Fan 1"
            active:      service.fan1Rpm > 0
            accentColor: "#89dceb"
        }

        Speedometer {
            visible:     root.showFans && service.fanCount >= 2
            size:        root.s
            label:       ""
            percent:     Math.min(100, service.fan2Rpm / root.maxFanRpm * 100)
            centerText:  service.fan2Rpm > 999
                             ? (service.fan2Rpm / 1000).toFixed(1) + "k"
                             : service.fan2Rpm + ""
            bottomText:  "Fan 2"
            active:      service.fan2Rpm > 0
            accentColor: "#89dceb"
        }
    }
}
