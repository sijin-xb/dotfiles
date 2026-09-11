import QtQuick
import qs

// 音频可视化：bar 样式频谱竖条，自动缩放。
// 采样策略：把 cava 的低频段（能量主要集中区）分段取平均映射到各 bar。
Item {
    id: root

    property int barCount: 6
    property real barWidth: 3
    property real barSpacing: 3
    property real maxBarHeight: 18
    property real minBarHeight: 3
    property bool active: false
    property list<real> points: []

    // 只取 cava 输出的前 freqFraction 部分（低频到中频），能量最集中
    property real freqFraction: 0.5

    property real runningMax: 1

    implicitWidth: barCount * barWidth + (barCount - 1) * barSpacing
    implicitHeight: maxBarHeight

    // 分段平均：把 [0, usable) 均匀分成 barCount 段，每段取平均
    readonly property var bars: {
        if (!active || !points || points.length === 0)
            return Array(barCount).fill(0)
        const usable = Math.max(barCount, Math.floor(points.length * freqFraction))
        const segSize = usable / barCount
        const out = new Array(barCount)
        for (let b = 0; b < barCount; b++) {
            const start = Math.floor(b * segSize)
            const end = Math.max(start + 1, Math.floor((b + 1) * segSize))
            let sum = 0, cnt = 0
            for (let i = start; i < end && i < points.length; i++) {
                sum += points[i]; cnt++
            }
            out[b] = cnt > 0 ? sum / cnt : 0
        }
        return out
    }

    onBarsChanged: {
        let m = 0
        for (let i = 0; i < bars.length; i++) if (bars[i] > m) m = bars[i]
        if (m > runningMax) runningMax = m
        else runningMax = Math.max(m, runningMax * 0.96, 1)
    }

    onActiveChanged: {
        if (!active) runningMax = 1
    }

    Row {
        anchors.centerIn: parent
        spacing: root.barSpacing

        Repeater {
            model: root.barCount
            Rectangle {
                required property int index
                width: root.barWidth
                property real norm: {
                    if (!root.active) return 0
                    return Math.min(1, (root.bars[index] ?? 0) / root.runningMax)
                }
                height: Math.max(root.minBarHeight, norm * root.maxBarHeight)
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: IslandTheme.text
                opacity: root.active ? 0.9 : 0.35
                Behavior on height {
                    NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 300 }
                }
            }
        }
    }
}
