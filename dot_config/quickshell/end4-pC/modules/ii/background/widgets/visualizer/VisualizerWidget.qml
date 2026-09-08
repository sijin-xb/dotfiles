import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "visualizer"

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool isPlaying: activePlayer?.isPlaying ?? false
    readonly property list<real> points: GlobalStates.visualizerPoints

    // 可视化样式: bars 柱状 / mirror 镜像 / line 折线 / wave 波形 / dots 点阵 / area 填充
    readonly property string style: Config.options.background.widgets.visualizer.style ?? "bars"

    property real barWidth: 4
    property real barSpacing: 8
    property real maxBarHeight: 220
    property real maxVisualizerValue: 1000
    property real smoothingDuration: 150

    readonly property int barCount: Math.max(1, Math.floor(screenWidth / (barWidth + barSpacing)))

    readonly property var smoothedPoints: {
        let raw = points
        if (!raw || raw.length === 0) return Array(barCount).fill(0)
        let count = barCount
        let mapped = new Array(count)
        let rawLenM1 = raw.length - 1

        for (let i = 0; i < count; i++) {
            let progress = i / (count - 1 || 1)
            let relPos = progress * rawLenM1
            let low = Math.floor(relPos)
            let high = Math.ceil(relPos)
            let mix = relPos - low
            mapped[i] = (raw[low] * (1 - mix)) + (raw[high] * (high < raw.length ? mix : 0))
        }

        let smoothed = new Array(count)
        let sW = 0.2
        for (let j = 0; j < count; j++) {
            let p = mapped[Math.max(0, j - 1)]
            let n = mapped[Math.min(count - 1, j + 1)]
            smoothed[j] = (p * sW) + (mapped[j] * (1.0 - 2 * sW)) + (n * sW)
        }
        return smoothed
    }

    property real activityOpacity: 0
    Behavior on activityOpacity {
        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
    }

    Timer {
        id: silenceTimer
        interval: 1000
        onTriggered: root.activityOpacity = 0
    }

    onPointsChanged: {
        if (points.some(p => p > 0)) {
            root.activityOpacity = 1.0
            silenceTimer.restart()
        }
    }

    implicitWidth: screenWidth
    implicitHeight: maxBarHeight + 20

    x: 0
    y: screenHeight - implicitHeight
    draggable: false

    // 样式切换 / 数据更新时重绘 Canvas 样式
    onSmoothedPointsChanged: styleCanvas.requestPaint()
    onStyleChanged: styleCanvas.requestPaint()

    Item {
        anchors.fill: parent
        opacity: root.activityOpacity

        Behavior on opacity {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }

        // 柱状频谱：保留原有 Rectangle 柱实现（带高度动画）
        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.barSpacing
            visible: root.style === "bars"

            Repeater {
                model: root.barCount
                Rectangle {
                    required property int index
                    width: root.barWidth
                    property real pointValue: {
                        const v = root.smoothedPoints[index] ?? 0
                        return Math.max(root.barWidth, (v / root.maxVisualizerValue) * root.maxBarHeight)
                    }
                    height: pointValue
                    topLeftRadius: root.barWidth / 2
                    topRightRadius: root.barWidth / 2
                    anchors.bottom: parent.bottom

                    property real intensity: pointValue / root.maxBarHeight
                    color: Qt.rgba(
                        Appearance.colors.colPrimary.r * intensity + Appearance.colors.colPrimaryContainer.r * (1 - intensity),
                        Appearance.colors.colPrimary.g * intensity + Appearance.colors.colPrimaryContainer.g * (1 - intensity),
                        Appearance.colors.colPrimary.b * intensity + Appearance.colors.colPrimaryContainer.b * (1 - intensity),
                        1
                    )

                    Behavior on height {
                        NumberAnimation { duration: root.smoothingDuration; easing.type: Easing.OutQuad }
                    }
                }
            }
        }

        // 其余样式（mirror / line / wave / dots / area）用 Canvas 绘制
        Canvas {
            id: styleCanvas
            anchors.fill: parent
            visible: root.style !== "bars"

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            function mixColor(t) {
                const a = Appearance.colors.colPrimary
                const b = Appearance.colors.colPrimaryContainer
                return Qt.rgba(
                    a.r * t + b.r * (1 - t),
                    a.g * t + b.g * (1 - t),
                    a.b * t + b.b * (1 - t),
                    1
                ).toString()
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const pts = root.smoothedPoints
                const count = pts.length
                if (count < 2) return
                const w = width
                const h = height
                const maxV = root.maxVisualizerValue
                const maxH = root.maxBarHeight
                const xs = i => (i / (count - 1)) * w
                const ys = i => h - Math.max(2, (pts[i] / maxV) * maxH)

                const grad = ctx.createLinearGradient(0, h, 0, h - maxH)
                grad.addColorStop(0, mixColor(0))
                grad.addColorStop(1, mixColor(1))

                switch (root.style) {
                case "mirror": {
                    // 镜像频谱：以中线为轴上下对称的柱
                    const step = w / count
                    const centerY = h - maxH / 2
                    for (let i = 0; i < count; i++) {
                        const hgt = Math.max(root.barWidth, (pts[i] / maxV) * maxH)
                        ctx.fillStyle = mixColor(hgt / maxH)
                        ctx.fillRect(i * step + (step - root.barWidth) / 2, centerY - hgt / 2, root.barWidth, hgt)
                    }
                    break
                }
                case "line": {
                    // 折线频谱：直线段连接各频点
                    ctx.strokeStyle = grad
                    ctx.lineWidth = 3
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(xs(0), ys(0))
                    for (let i = 1; i < count; i++) ctx.lineTo(xs(i), ys(i))
                    ctx.stroke()
                    break
                }
                case "wave":
                case "area": {
                    // 波形曲线 / 填充波形：平滑贝塞尔曲线
                    const trace = () => {
                        ctx.moveTo(xs(0), ys(0))
                        for (let i = 1; i < count - 1; i++) {
                            const xc = (xs(i) + xs(i + 1)) / 2
                            const yc = (ys(i) + ys(i + 1)) / 2
                            ctx.quadraticCurveTo(xs(i), ys(i), xc, yc)
                        }
                        ctx.lineTo(xs(count - 1), ys(count - 1))
                    }
                    if (root.style === "area") {
                        const c = Appearance.colors.colPrimary
                        const fillGrad = ctx.createLinearGradient(0, h - maxH, 0, h)
                        fillGrad.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.45).toString())
                        fillGrad.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0.03).toString())
                        ctx.beginPath()
                        trace()
                        ctx.lineTo(w, h)
                        ctx.lineTo(0, h)
                        ctx.closePath()
                        ctx.fillStyle = fillGrad
                        ctx.fill()
                    }
                    ctx.beginPath()
                    trace()
                    ctx.strokeStyle = grad
                    ctx.lineWidth = 3
                    ctx.lineJoin = "round"
                    ctx.lineCap = "round"
                    ctx.stroke()
                    break
                }
                case "dots": {
                    // 点阵频谱：每列自下而上点亮的圆点
                    const cols = Math.min(count, 96)
                    const pitch = 12
                    const dotR = 3
                    const maxDots = Math.max(1, Math.floor(maxH / pitch))
                    for (let cIdx = 0; cIdx < cols; cIdx++) {
                        const v = pts[Math.round(cIdx * (count - 1) / (cols - 1))] ?? 0
                        const n = Math.max(1, Math.round((v / maxV) * maxDots))
                        const x = dotR + 4 + (cIdx / (cols - 1)) * (w - 2 * (dotR + 4))
                        for (let d = 0; d < n; d++) {
                            ctx.fillStyle = mixColor(d / maxDots)
                            ctx.beginPath()
                            ctx.arc(x, h - pitch / 2 - d * pitch, dotR, 0, Math.PI * 2)
                            ctx.fill()
                        }
                    }
                    break
                }
                }
            }
        }
    }
}
