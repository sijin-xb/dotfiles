import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    // ---------------------------------------------------------------
    // Settings
    // ---------------------------------------------------------------
    readonly property string vizMode:       pluginData.vizMode       ?? "bars"
    readonly property int    barCount:      pluginData.barCount      ?? 20
    readonly property int    curvePoints:   pluginData.curvePoints   ?? 32
    readonly property int    barSpacing:    pluginData.barSpacing     ?? 4
    readonly property int    barWidth:      pluginData.barWidth       ?? 0       // 0 = auto
    readonly property int    curveLineWidth: pluginData.curveLineWidth ?? 2
    readonly property int    sensitivity:   pluginData.sensitivity    ?? 100
    readonly property string channels:      pluginData.channels       ?? "mono"  // "mono" | "stereo"
    readonly property string orientation:   pluginData.orientation    ?? "bottom"
    readonly property real   bgOpacity:     (pluginData.bgOpacity     ?? 0) / 100

    // "opacity" is the new unified key; fall back to old "barOpacity" for existing configs.
    readonly property real   fgOpacity:     (pluginData.opacity ?? pluginData.barOpacity ?? 100) / 100

    readonly property color barColor: {
        const choice = pluginData.colorChoice ?? "primary"
        if (choice === "secondary") return Theme.secondary
        if (choice === "surface")   return Theme.surfaceVariantText
        return Theme.primary
    }

    readonly property bool useGradient: (pluginData.colorChoice ?? "primary") === "gradient"

    // In curve mode the "bar count" cava sees is controlled by curvePoints;
    // the barCount setting is only surfaced in the UI when vizMode === "bars".
    readonly property int effectiveBars: vizMode === "bars" ? barCount : curvePoints

    implicitWidth:  400
    implicitHeight: 120

    // ---------------------------------------------------------------
    // Internal state
    // ---------------------------------------------------------------
    property var  barValues:     []
    property bool isSilent:      true
    property bool fadedOut:      true
    property bool hasPlayedOnce: false

    readonly property int silenceTimeout: (pluginData.silenceTimeout ?? 5) * 1000

    onIsSilentChanged: {
        if (isSilent) {
            if (hasPlayedOnce) silenceTimer.restart()
        } else {
            hasPlayedOnce = true
            silenceTimer.stop()
            fadedOut = false
        }
    }

    Timer {
        id: silenceTimer
        repeat: false
        interval: root.silenceTimeout
        onTriggered: root.fadedOut = true
    }

    opacity: fadedOut ? 0.0 : 1.0
    Behavior on opacity { NumberAnimation { duration: 1000; easing.type: Easing.InOutQuad } }

    // ---------------------------------------------------------------
    // Config writer + cava process
    // Rebuilds and restarts cava whenever effectiveBars, sensitivity,
    // or channels changes — these all affect the cava config file.
    //
    // Restart loop protection: if cava fails to start (e.g. binary not
    // found), the process exits immediately. Without a cap this creates
    // a tight infinite loop. retryCount tracks consecutive fast exits;
    // after maxRetries the widget gives up until the next settings change
    // triggers a manual rebuildConfig().
    // ---------------------------------------------------------------
    property int retryCount: 0
    readonly property int maxRetries: 3

    Timer {
        id: rebuildTimer
        interval: 50
        repeat: false
        onTriggered: {
            root.retryCount = 0          // intentional rebuild resets the cap
            if (cavaProcess.running) {
                cavaProcess.running = false
            } else if (!configWriter.running) {
                configWriter.running = true
            }
        }
    }

    Timer {
        id: retryTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (!configWriter.running && !cavaProcess.running)
                configWriter.running = true
        }
    }

    function rebuildConfig() {
        rebuildTimer.restart()
    }

    Process {
        id: configWriter
        command: [
            "bash", "-c",
            "mkdir -p /tmp/.dankshell && cat > /tmp/.dankshell/cava-widget.cfg << 'CAVAEOF'\n" +
            "[general]\n" +
            "bars = "        + root.effectiveBars + "\n" +
            "framerate = 60\n" +
            "sensitivity = " + root.sensitivity   + "\n" +
            "channels = "    + root.channels      + "\n" +
            "\n" +
            "[output]\n" +
            "method = raw\n" +
            "channels = "    + root.channels      + "\n" +
            "raw_target = /dev/stdout\n" +
            "data_format = ascii\n" +
            "ascii_max_range = 1000\n" +
            "bar_delimiter = 59\n" +
            "frame_delimiter = 10\n" +
            "CAVAEOF"
        ]
        running: false
        onRunningChanged: {
            if (!running) cavaProcess.running = true
        }
    }

    Process {
        id: cavaProcess
        command: ["cava", "-p", "/tmp/.dankshell/cava-widget.cfg"]
        running: false
        onRunningChanged: {
            if (!running && !configWriter.running) {
                if (root.retryCount < root.maxRetries) {
                    root.retryCount++
                    retryTimer.restart()
                }
                // else: give up silently; next rebuildConfig() resets the cap
            }
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                if (!line || line.length === 0) return
                const parts = line.split(";")
                const vals = []
                let silent = true
                for (let i = 0; i < parts.length; i++) {
                    const n = parseInt(parts[i], 10)
                    if (!isNaN(n)) {
                        const v = Math.min(1.0, n / 1000.0)
                        vals.push(v)
                        if (v > 0.01) silent = false
                    }
                }
                if (vals.length > 0) {
                    root.barValues = vals
                    root.isSilent  = silent
                }
            }
        }
    }

    Component.onCompleted:      rebuildConfig()
    onEffectiveBarsChanged:     rebuildConfig()
    onSensitivityChanged:       rebuildConfig()
    onChannelsChanged:          rebuildConfig()
    // Switching mode may change effectiveBars, but also forces a repaint.
    onVizModeChanged:           rebuildConfig()

    // ---------------------------------------------------------------
    // Background
    // ---------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color:   Theme.surface
        opacity: root.bgOpacity
        radius:  Theme.cornerRadius
    }

    // ---------------------------------------------------------------
    // Visualisation container
    // ---------------------------------------------------------------
    Item {
        id: vis
        anchors.fill:    parent
        anchors.margins: 0
        clip:            true

        readonly property real effectiveBarW: root.barWidth > 0
            ? root.barWidth
            : Math.max(1, (width  - (root.effectiveBars - 1) * root.barSpacing) / root.effectiveBars)

        readonly property real effectiveBarH: root.barWidth > 0
            ? root.barWidth
            : Math.max(1, (height - (root.effectiveBars - 1) * root.barSpacing) / root.effectiveBars)

        // ---- BARS: BOTTOM / TOP / HORIZONTAL ----
        Row {
            visible: root.vizMode === "bars"
                  && (root.orientation === "bottom"
                   || root.orientation === "top"
                   || root.orientation === "horizontal")
            width:   parent.width
            height:  parent.height
            spacing: root.barSpacing

            Repeater {
                model: root.vizMode === "bars" ? root.barCount : 0
                delegate: Rectangle {
                    required property int  index
                    readonly property real norm: root.barValues[index] ?? 0.0

                    width:  vis.effectiveBarW
                    height: Math.max(1, norm * vis.height)
                    y:      root.orientation === "bottom"     ? vis.height - height
                          : root.orientation === "horizontal" ? vis.height / 2 - height / 2
                          :                                     0

                    Behavior on height { SmoothedAnimation { velocity: vis.height * 4 } }

                    radius: 2
                    color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b,
                                   root.fgOpacity * (0.85 + norm * 0.15))
                    gradient: root.useGradient ? rowBarGrad : null

                    Gradient {
                        id: rowBarGrad
                        orientation: Gradient.Vertical
                        GradientStop {
                            position: 0.0
                            color: root.orientation === "top"
                                ? Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, root.fgOpacity)
                                : Qt.rgba(Theme.primary.r,   Theme.primary.g,   Theme.primary.b,   root.fgOpacity)
                        }
                        GradientStop {
                            position: 1.0
                            color: root.orientation === "top"
                                ? Qt.rgba(Theme.primary.r,   Theme.primary.g,   Theme.primary.b,   root.fgOpacity)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, root.fgOpacity)
                        }
                    }
                }
            }
        }

        // ---- BARS: LEFT / RIGHT ----
        Column {
            visible: root.vizMode === "bars"
                  && (root.orientation === "left"
                   || root.orientation === "right"
                   || root.orientation === "vertical")
            width:   parent.width
            height:  parent.height
            spacing: root.barSpacing

            Repeater {
                model: root.vizMode === "bars" ? root.barCount : 0
                delegate: Rectangle {
                    required property int  index
                    readonly property real norm: root.barValues[index] ?? 0.0

                    height: vis.effectiveBarH
                    width:  Math.max(1, norm * vis.width)
                    x:      root.orientation === "right"    ? vis.width - width
                          : root.orientation === "vertical" ? vis.width / 2 - width / 2
                          :                                   0

                    Behavior on width { SmoothedAnimation { velocity: vis.width * 4 } }

                    radius: 2
                    color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b,
                                   root.fgOpacity * (0.85 + norm * 0.15))
                    gradient: root.useGradient ? colBarGrad : null

                    Gradient {
                        id: colBarGrad
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: root.orientation === "left"
                                ? Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, root.fgOpacity)
                                : Qt.rgba(Theme.primary.r,   Theme.primary.g,   Theme.primary.b,   root.fgOpacity)
                        }
                        GradientStop {
                            position: 1.0
                            color: root.orientation === "left"
                                ? Qt.rgba(Theme.primary.r,   Theme.primary.g,   Theme.primary.b,   root.fgOpacity)
                                : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, root.fgOpacity)
                        }
                    }
                }
            }
        }

        // ---- CURVE: OUTLINE / FILLED ----
        // Drawn on a Canvas using a Catmull-Rom spline, which passes through
        // every data point — giving an accurate frequency envelope without the
        // jagged look of linear segments.
        Canvas {
            id: curveCanvas

            visible: root.vizMode === "curve-outline"
                  || root.vizMode === "curve-filled"

            anchors.fill: parent

            // Trigger a repaint every time new data arrives.
            Connections {
                target: root
                function onBarValuesChanged()   { if (curveCanvas.visible) curveCanvas.requestPaint() }
                function onVizModeChanged()     { if (curveCanvas.visible) curveCanvas.requestPaint() }
                function onOrientationChanged() { if (curveCanvas.visible) curveCanvas.requestPaint() }
                function onBarColorChanged()    { if (curveCanvas.visible) curveCanvas.requestPaint() }
                function onFgOpacityChanged()   { if (curveCanvas.visible) curveCanvas.requestPaint() }
                function onUseGradientChanged() { if (curveCanvas.visible) curveCanvas.requestPaint() }
            }

            onPaint: {
                const ctx  = getContext("2d")
                const w    = width
                const h    = height
                const vals = root.barValues
                const n    = vals.length

                ctx.clearRect(0, 0, w, h)

                if (n < 2) return

                // --------------------------------------------------
                // Build screen-space point array based on orientation.
                // "horizontal" mirrors the curve around the centre axis.
                // "top" / "bottom" are reflections of each other.
                // Left/Right are not handled here (bars take over).
                // --------------------------------------------------
                const orient = root.orientation
                const points = []

                for (let i = 0; i < n; i++) {
                    const t   = i / (n - 1)   // 0 → 1 along the frequency axis
                    const amp = vals[i]         // 0 → 1 amplitude

                    let px, py
                    if (orient === "top") {
                        px = t * w
                        py = amp * h
                    } else if (orient === "horizontal") {
                        // Grows symmetrically outward from the horizontal centre.
                        // Use the upper half; we'll mirror it below.
                        px = t * w
                        py = h / 2 - amp * (h / 2)
                    } else if (orient === "vertical") {
                        // Grows symmetrically outward from the vertical centre.
                        // Use the left half; we'll mirror it below.
                        px = w / 2 - amp * (w / 2)
                        py = t * h
                    } else if (orient === "left") {
                        // Bands distributed top → bottom; amplitude grows rightward.
                        px = amp * w
                        py = t * h
                    } else if (orient === "right") {
                        // Bands distributed top → bottom; amplitude grows leftward.
                        px = w - amp * w
                        py = t * h
                    } else {
                        // bottom (default)
                        px = t * w
                        py = h - amp * h
                    }
                    points.push({ x: px, y: py })
                }

                // --------------------------------------------------
                // Draw the Catmull-Rom spline.
                // For each segment [i, i+1] the two Bézier control
                // points are derived from the neighbouring points:
                //   cp1 = P[i]   + (P[i+1] − P[i−1]) / 6
                //   cp2 = P[i+1] − (P[i+2] − P[i]  ) / 6
                // This ensures C1 continuity (matching tangents) at
                // every knot with no overshoot on quiet passages.
                // --------------------------------------------------
                function drawSpline(pts) {
                    const len = pts.length
                    ctx.beginPath()
                    ctx.moveTo(pts[0].x, pts[0].y)
                    for (let i = 0; i < len - 1; i++) {
                        const p0 = pts[Math.max(0, i - 1)]
                        const p1 = pts[i]
                        const p2 = pts[i + 1]
                        const p3 = pts[Math.min(len - 1, i + 2)]

                        const cp1x = p1.x + (p2.x - p0.x) / 6
                        const cp1y = p1.y + (p2.y - p0.y) / 6
                        const cp2x = p2.x - (p3.x - p1.x) / 6
                        const cp2y = p2.y - (p3.y - p1.y) / 6

                        ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y)
                    }
                }

                const r = root.barColor.r
                const g = root.barColor.g
                const b = root.barColor.b
                const a = root.fgOpacity

                // Build a linear gradient covering the canvas in the direction
                // that matches the amplitude axis (or frequency axis for symmetric
                // modes), primary at the tip/low-freq end, secondary at the base.
                function makeGradient() {
                    let grad
                    const c1 = Qt.rgba(Theme.primary.r,   Theme.primary.g,   Theme.primary.b,   a)
                    const c2 = Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, a)
                    if (orient === "top") {
                        grad = ctx.createLinearGradient(0, h, 0, 0)  // bottom(tip)→top(base)
                    } else if (orient === "left") {
                        grad = ctx.createLinearGradient(w, 0, 0, 0)  // right(tip)→left(base)
                    } else if (orient === "right") {
                        grad = ctx.createLinearGradient(0, 0, w, 0)  // left(tip)→right(base)
                    } else if (orient === "horizontal") {
                        grad = ctx.createLinearGradient(0, 0, w, 0)  // left(low-freq)→right(high-freq)
                    } else {
                        grad = ctx.createLinearGradient(0, 0, 0, h)  // top(tip/low-freq)→bottom(base)
                        // covers: bottom, vertical
                    }
                    grad.addColorStop(0, c1)
                    grad.addColorStop(1, c2)
                    return grad
                }

                const paintColor = root.useGradient ? makeGradient() : Qt.rgba(r, g, b, a)

                const isFilled = root.vizMode === "curve-filled"

                if (orient === "horizontal") {
                    // Upper half
                    drawSpline(points)
                    // Mirror for the lower half: reflect y around centre.
                    const mirrorH = points.map(p => ({ x: p.x, y: h - p.y }))
                    // Continue the path to close over the mirrored curve.
                    for (let i = mirrorH.length - 2; i >= 0; i--) {
                        const p0 = mirrorH[Math.min(mirrorH.length - 1, i + 2)]
                        const p1 = mirrorH[i + 1]
                        const p2 = mirrorH[i]
                        const p3 = mirrorH[Math.max(0, i - 1)]

                        const cp1x = p1.x + (p2.x - p0.x) / 6
                        const cp1y = p1.y + (p2.y - p0.y) / 6
                        const cp2x = p2.x - (p3.x - p1.x) / 6
                        const cp2y = p2.y - (p3.y - p1.y) / 6

                        ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y)
                    }
                    ctx.closePath()

                    if (isFilled) {
                        ctx.fillStyle = paintColor
                        ctx.fill()
                        // Stroke both curve edges on top of the fill.
                        if (root.curveLineWidth > 0) {
                            drawSpline(points)
                            ctx.strokeStyle = paintColor
                            ctx.lineWidth   = root.curveLineWidth
                            ctx.lineJoin    = "round"
                            ctx.lineCap     = "round"
                            ctx.stroke()
                            drawSpline(mirrorH)
                            ctx.stroke()
                        }
                    } else {
                        ctx.strokeStyle = paintColor
                        ctx.lineWidth   = root.curveLineWidth
                        ctx.lineJoin    = "round"
                        ctx.lineCap     = "round"
                        ctx.stroke()
                    }

                } else if (orient === "vertical") {
                    // Left half
                    drawSpline(points)
                    // Mirror for the right half: reflect x around centre.
                    const mirrorV = points.map(p => ({ x: w - p.x, y: p.y }))
                    // Continue the path backwards over the mirrored curve to close the shape.
                    for (let i = mirrorV.length - 2; i >= 0; i--) {
                        const p0 = mirrorV[Math.min(mirrorV.length - 1, i + 2)]
                        const p1 = mirrorV[i + 1]
                        const p2 = mirrorV[i]
                        const p3 = mirrorV[Math.max(0, i - 1)]

                        const cp1x = p1.x + (p2.x - p0.x) / 6
                        const cp1y = p1.y + (p2.y - p0.y) / 6
                        const cp2x = p2.x - (p3.x - p1.x) / 6
                        const cp2y = p2.y - (p3.y - p1.y) / 6

                        ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y)
                    }
                    ctx.closePath()

                    if (isFilled) {
                        ctx.fillStyle = paintColor
                        ctx.fill()
                        // Stroke both curve edges on top of the fill.
                        if (root.curveLineWidth > 0) {
                            drawSpline(points)
                            ctx.strokeStyle = paintColor
                            ctx.lineWidth   = root.curveLineWidth
                            ctx.lineJoin    = "round"
                            ctx.lineCap     = "round"
                            ctx.stroke()
                            drawSpline(mirrorV)
                            ctx.stroke()
                        }
                    } else {
                        ctx.strokeStyle = paintColor
                        ctx.lineWidth   = root.curveLineWidth
                        ctx.lineJoin    = "round"
                        ctx.lineCap     = "round"
                        ctx.stroke()
                    }

                } else if (isFilled) {
                    // Filled: draw the spline, close back to the baseline edge, fill.
                    drawSpline(points)
                    if (orient === "left") {
                        ctx.lineTo(0, points[n - 1].y)
                        ctx.lineTo(0, points[0].y)
                    } else if (orient === "right") {
                        ctx.lineTo(w, points[n - 1].y)
                        ctx.lineTo(w, points[0].y)
                    } else {
                        const baselineY = orient === "top" ? 0 : h
                        ctx.lineTo(points[n - 1].x, baselineY)
                        ctx.lineTo(points[0].x,     baselineY)
                    }
                    ctx.closePath()
                    ctx.fillStyle = paintColor
                    ctx.fill()
                    // Stroke the curve edge on top of the fill.
                    if (root.curveLineWidth > 0) {
                        drawSpline(points)
                        ctx.strokeStyle = paintColor
                        ctx.lineWidth   = root.curveLineWidth
                        ctx.lineJoin    = "round"
                        ctx.lineCap     = "round"
                        ctx.stroke()
                    }

                } else {
                    // Outline only.
                    drawSpline(points)
                    ctx.strokeStyle = paintColor
                    ctx.lineWidth   = root.curveLineWidth
                    ctx.lineJoin    = "round"
                    ctx.lineCap     = "round"
                    ctx.stroke()
                }
            }
        }

    } // vis
}
