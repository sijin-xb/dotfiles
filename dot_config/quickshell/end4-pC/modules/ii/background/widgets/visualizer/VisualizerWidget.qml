pragma ComponentBehavior: Bound

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

    // 来自配置 (bars / mirror / line / wave / dots / area / circular / particles / spectrum / waveSpectrum)
    readonly property string style: Config.options.background.widgets.visualizer.style ?? "bars"

    // ── 灵敏度（0.3 ~ 3.0，1.0 为默认）────────────────────────────────
    readonly property real rawSensitivity: Math.max(0.1, Config.options.background.widgets.visualizer.sensitivity ?? 1.0)
    // 灵敏度越大 → effectiveMaxV 越小 → 同样大小的频点呈现更高的柱形
    readonly property real effectiveMaxV: 1000 / rawSensitivity

    // ── 平滑度（1 ~ 10，越大越平滑）──────────────────────────────────
    readonly property int smoothing: Math.max(1, Config.options.background.widgets.visualizer.smoothing ?? 2)

    // ── 画布尺寸（所有样式统一一个画布，按 style 自行决定怎么用空间）─
    property real maxBarHeight: 220
    property real barWidth: 4
    property real barSpacing: 8

    // 用于 bars / mirror / dots / line / wave / area 这种横向铺开样式
    readonly property int barCount: Math.max(1, Math.floor(screenWidth / (barWidth + barSpacing)))
    // 用于 circular / particles / spectrum / waveSpectrum 这种紧凑样式
    readonly property int extendedBarCount: 64

    implicitWidth: screenWidth
    implicitHeight: maxBarHeight + 80  // 给 spectrum/circular 等居中样式留高度

    // ── 颜色混合工具：从 baseColor(t) 线性插值到 peakColor(0) ──
    readonly property color baseColor: Appearance.colors.colPrimary
    readonly property color peakColor: Appearance.colors.colPrimaryContainer
    function mixColor(t) {
        t = Math.max(0, Math.min(1, t))
        return Qt.rgba(
            baseColor.r * t + peakColor.r * (1 - t),
            baseColor.g * t + peakColor.g * (1 - t),
            baseColor.b * t + peakColor.b * (1 - t),
            1
        )
    }
    function mixRGBA(t, a) {
        t = Math.max(0, Math.min(1, t))
        return Qt.rgba(
            baseColor.r * t + peakColor.r * (1 - t),
            baseColor.g * t + peakColor.g * (1 - t),
            baseColor.b * t + peakColor.b * (1 - t),
            a
        )
    }

    // ── 重采样 + 平滑：返回长度为 count 的数组 ───────────────────
    function resampleAndSmooth(raw, count) {
        if (!raw || raw.length === 0) return Array(count).fill(0)
        const out = new Array(count)
        const rawLenM1 = raw.length - 1
        // 1) 线性插值重采样
        const mapped = new Array(count)
        for (let i = 0; i < count; i++) {
            const progress = i / (count - 1 || 1)
            const relPos = progress * rawLenM1
            const low = Math.floor(relPos)
            const high = Math.min(low + 1, raw.length - 1)
            const mix = relPos - low
            mapped[i] = (raw[low] * (1 - mix)) + (raw[high] * mix)
        }
        // 2) 移动平均平滑（窗口大小 = smoothing）
        const half = Math.floor(smoothing / 2)
        const smoothed = new Array(count)
        for (let j = 0; j < count; j++) {
            let sum = 0
            let cnt = 0
            for (let k = Math.max(0, j - half); k <= Math.min(count - 1, j + half); k++) {
                sum += mapped[k]
                cnt++
            }
            smoothed[j] = cnt > 0 ? sum / cnt : mapped[j]
        }
        return smoothed
    }

    readonly property var smoothedPoints: resampleAndSmooth(points, barCount)
    readonly property var extendedPoints: resampleAndSmooth(points, extendedBarCount)

    // ── 闲置时渐隐 ─────────────────────────────────────────────
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
        if (points && points.some(p => p > 0)) {
            root.activityOpacity = 1.0
            silenceTimer.restart()
        }
    }

    // 颜色/数据变化时主动重绘
    Connections {
        target: root
        function onStyleChanged() { painter.requestPaint() }
        function onRawSensitivityChanged() { painter.requestPaint() }
        function onEffectiveMaxVChanged() { painter.requestPaint() }
        function onSmoothingChanged() { painter.requestPaint() }
        function onBarCountChanged() { painter.requestPaint() }
        function onExtendedBarCountChanged() { painter.requestPaint() }
    }

    // ── Canvas 渲染所有 10 种样式 ─────────────────────────────
    Canvas {
        id: painter
        anchors.fill: parent
        opacity: root.activityOpacity
        renderStrategy: Canvas.Cooperative
        renderTarget: Canvas.Image
        antialiasing: true

        Behavior on opacity {
            NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
        }

        // 数据/尺寸变化 → 重绘
        Connections {
            target: root
            function onPointsChanged() { painter.requestPaint() }
            function onSmoothedPointsChanged() { painter.requestPaint() }
            function onExtendedPointsChanged() { painter.requestPaint() }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const W = width
            const H = height
            const pts = root.smoothedPoints
            const ePts = root.extendedPoints
            const emV = root.effectiveMaxV
            const s = root.style
            const mBH = root.maxBarHeight

            // 公共：把原始强度归一化后映射为像素高度
            function barH(v) {
                if (emV <= 0) return 0
                return Math.max(0, (v / emV) * mBH)
            }
            // 公共：归一化强度 t (0~1)
            function intensity(v) {
                if (emV <= 0) return 0
                return Math.max(0, Math.min(1, v / emV))
            }

            // 底部基线（bars / mirror / line / wave / dots / area 用）
            const baseY = H - 12

            // === BARS ====================================================
            if (s === "bars") {
                const bw = root.barWidth
                const gap = root.barSpacing
                const totalW = pts.length * (bw + gap) - gap
                const startX = (W - totalW) / 2
                for (let i = 0; i < pts.length; i++) {
                    const h = barH(pts[i])
                    const x = startX + i * (bw + gap)
                    const grad = ctx.createLinearGradient(0, baseY - h, 0, baseY)
                    grad.addColorStop(0, root.mixColor(1))
                    grad.addColorStop(1, root.mixColor(0.25))
                    ctx.fillStyle = grad
                    // 圆顶矩形
                    const r = bw / 2
                    ctx.beginPath()
                    ctx.moveTo(x, baseY)
                    ctx.lineTo(x, baseY - h + r)
                    ctx.arc(x + r, baseY - h + r, r, Math.PI, Math.PI * 2)
                    ctx.lineTo(x + bw, baseY)
                    ctx.closePath()
                    ctx.fill()
                }
            }

            // === MIRROR：以中线为对称的实心带 ====================================
            else if (s === "mirror") {
                const bw = Math.max(2, (W * 0.86) / pts.length - 2)
                const gap = 2
                const n = pts.length
                const totalW = n * (bw + gap) - gap
                const startX = (W - totalW) / 2
                const cy = H / 2
                for (let i = 0; i < n; i++) {
                    const h = barH(pts[i]) * 1.0
                    const x = startX + i * (bw + gap)
                    const t = intensity(pts[i])
                    ctx.fillStyle = root.mixColor(0.25 + 0.75 * t)
                    ctx.fillRect(x, cy - h / 2, bw, h)
                }
            }

            // === LINE：折线，从基线向上 ==================================
            else if (s === "line") {
                ctx.lineWidth = 2
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                const grad = ctx.createLinearGradient(0, 0, 0, baseY)
                grad.addColorStop(0, root.mixColor(1))
                grad.addColorStop(1, root.mixColor(0.45))
                ctx.strokeStyle = grad
                ctx.beginPath()
                for (let i = 0; i < pts.length; i++) {
                    const x = (i / (pts.length - 1)) * W
                    const y = baseY - barH(pts[i])
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.stroke()
                // 顶点上方打发光圆点
                for (let i = 0; i < pts.length; i++) {
                    const x = (i / (pts.length - 1)) * W
                    const y = baseY - barH(pts[i])
                    const t = intensity(pts[i])
                    ctx.fillStyle = root.mixColor(1)
                    ctx.beginPath()
                    ctx.arc(x, y, 1.5 + t * 1.5, 0, Math.PI * 2)
                    ctx.fill()
                }
            }

            // === WAVE：双层波浪（基线 + 副本偏移）=========================
            else if (s === "wave") {
                const amp = (H - 24) / 2
                const cy = H / 2
                ctx.lineWidth = 2.5
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                // 主体
                ctx.strokeStyle = root.mixColor(0.95)
                ctx.beginPath()
                for (let i = 0; i < pts.length; i++) {
                    const x = (i / (pts.length - 1)) * W
                    const y = cy - barH(pts[i]) / 2
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.stroke()
                // 镜像（虚化）
                ctx.strokeStyle = root.mixRGBA(0.55, 0.55)
                ctx.beginPath()
                for (let i = 0; i < pts.length; i++) {
                    const x = (i / (pts.length - 1)) * W
                    const y = cy + barH(pts[i]) / 2
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.stroke()
            }

            // === DOTS：点阵，中线对齐 ====================================
            else if (s === "dots") {
                const cy = H / 2
                for (let i = 0; i < pts.length; i++) {
                    const x = (i / (pts.length - 1)) * (W - 8) + 4
                    const r = Math.max(1.4, barH(pts[i]) / 16)
                    const t = intensity(pts[i])
                    ctx.fillStyle = root.mixColor(0.25 + 0.75 * t)
                    ctx.beginPath()
                    ctx.arc(x, cy, r, 0, Math.PI * 2)
                    ctx.fill()
                }
            }

            // === AREA：填充波形 =========================================
            else if (s === "area") {
                const grad = ctx.createLinearGradient(0, 0, 0, baseY)
                grad.addColorStop(0, root.mixColor(0.95))
                grad.addColorStop(1, root.mixColor(0.15))
                ctx.fillStyle = grad
                ctx.beginPath()
                for (let i = 0; i < pts.length; i++) {
                    const x = (i / (pts.length - 1)) * W
                    const y = baseY - barH(pts[i])
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.lineTo(W, baseY)
                ctx.lineTo(0, baseY)
                ctx.closePath()
                ctx.fill()
                // 顶部描边
                ctx.lineWidth = 1.5
                ctx.strokeStyle = root.mixColor(1)
                ctx.beginPath()
                for (let i = 0; i < pts.length; i++) {
                    const x = (i / (pts.length - 1)) * W
                    const y = baseY - barH(pts[i])
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.stroke()
            }

            // === CIRCULAR：以圆心向外的径向频谱条 =========================
            else if (s === "circular") {
                const n = pts.length
                const cx = W / 2
                const cy = baseY
                const baseR = Math.min(W * 0.18, mBH * 0.5)
                // 总弧度 ~ 270°
                const totalArc = Math.PI * 1.5
                const startAngle = Math.PI / 2 + totalArc / 2
                for (let i = 0; i < n; i++) {
                    const t = i / Math.max(1, n - 1)
                    const ang = startAngle - totalArc * t
                    const len = barH(pts[i]) * 0.9
                    const inner = baseR
                    const outer = baseR + Math.max(8, len)
                    const x1 = cx + Math.cos(ang) * inner
                    const y1 = cy - Math.sin(ang) * inner
                    const x2 = cx + Math.cos(ang) * outer
                    const y2 = cy - Math.sin(ang) * outer
                    ctx.lineWidth = 3
                    ctx.lineCap = "round"
                    ctx.strokeStyle = root.mixColor(0.25 + 0.75 * t)
                    ctx.beginPath()
                    ctx.moveTo(x1, y1)
                    ctx.lineTo(x2, y2)
                    ctx.stroke()
                    // 顶端点
                    ctx.fillStyle = root.mixColor(1)
                    ctx.beginPath()
                    ctx.arc(x2, y2, 2.4, 0, Math.PI * 2)
                    ctx.fill()
                }
                // 中心圆环
                ctx.lineWidth = 2
                ctx.strokeStyle = root.mixColor(0.45)
                ctx.beginPath()
                ctx.arc(cx, cy, baseR, 0, Math.PI * 2)
                ctx.stroke()
            }

            // === PARTICLES：以每个频点位置向上散射的粒子柱 =================
            else if (s === "particles") {
                const n = pts.length
                for (let i = 0; i < n; i++) {
                    const t = i / Math.max(1, n - 1)
                    const x = t * W
                    const h = barH(pts[i])
                    // 每个频点散射 5 个粒子，向上飞溅
                    for (let k = 0; k < 5; k++) {
                        const fy = h * (0.18 + 0.18 * k)
                        const sideOff = (k - 2) * 2.2 * (1 + (i % 2))
                        const radius = Math.max(0.8, 2.4 - k * 0.4)
                        const alpha = Math.max(0.1, 0.95 - k * 0.18)
                        ctx.fillStyle = root.mixRGBA(1 - k * 0.12, alpha)
                        ctx.beginPath()
                        ctx.arc(x + sideOff, baseY - fy, radius, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
            }

            // === SPECTRUM：居中对称竖条 =================================
            else if (s === "spectrum") {
                const n = ePts.length
                const targetW = W * 0.78
                const bw = Math.max(2, targetW / n - 2)
                const gap = 2
                const totalW = n * (bw + gap) - gap
                const startX = (W - totalW) / 2
                const cy = H / 2
                const maxH = (H - 30) * 0.95
                for (let i = 0; i < n; i++) {
                    const h = Math.min(maxH, barH(ePts[i]) * 1.1)
                    const x = startX + i * (bw + gap)
                    const t = intensity(ePts[i])
                    const grad = ctx.createLinearGradient(0, cy - h, 0, cy + h)
                    grad.addColorStop(0, root.mixColor(0.3))
                    grad.addColorStop(0.5, root.mixColor(1))
                    grad.addColorStop(1, root.mixColor(0.3))
                    ctx.fillStyle = grad
                    ctx.fillRect(x, cy - h / 2, bw, h)
                }
            }

            // === WAVESPECTRUM：上下镜像的波形 + 中心填充 =================
            else if (s === "waveSpectrum") {
                const n = ePts.length
                const cy = H / 2
                const amp = (H - 30) / 2
                // 顶部波形
                ctx.lineWidth = 2.5
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                ctx.strokeStyle = root.mixColor(1)
                ctx.beginPath()
                for (let i = 0; i < n; i++) {
                    const x = (i / (n - 1)) * W
                    const y = cy - amp * intensity(ePts[i])
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.stroke()
                // 底部镜像
                ctx.strokeStyle = root.mixRGBA(0.6, 0.75)
                ctx.beginPath()
                for (let i = 0; i < n; i++) {
                    const x = (i / (n - 1)) * W
                    const y = cy + amp * intensity(ePts[i])
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.stroke()
                // 中间填充
                ctx.fillStyle = root.mixRGBA(0.65, 0.22)
                ctx.beginPath()
                ctx.moveTo(0, cy)
                for (let i = 0; i < n; i++) {
                    const x = (i / (n - 1)) * W
                    const y = cy - amp * intensity(ePts[i])
                    ctx.lineTo(x, y)
                }
                for (let i = n - 1; i >= 0; i--) {
                    const x = (i / (n - 1)) * W
                    const y = cy + amp * intensity(ePts[i])
                    ctx.lineTo(x, y)
                }
                ctx.closePath()
                ctx.fill()
            }
        }
    }

    // 数据流入时持续触发重绘，让 Canvas 跟随节奏实时变化
    Timer {
        interval: 16
        repeat: true
        running: root.activityOpacity > 0
        onTriggered: painter.requestPaint()
    }
}
