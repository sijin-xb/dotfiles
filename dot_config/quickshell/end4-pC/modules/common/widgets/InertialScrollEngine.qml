import QtQuick
import qs.modules.common

/**
 * Inertial scroll engine.
 *
 * ARCHITECTURE: This item is placed INSIDE the Flickable (as a child).
 * It does NOT handle events itself — instead, it exposes handleWheel()
 * which is called by a WheelHandler dynamically created on the Flickable's
 * parent (an ancestor). Ancestor WheelHandlers intercept events BEFORE
 * the Flickable's C++ wheelEvent handler in Qt 6.
 *
 * Implements two scrolling paths:
 * 1. TOUCHPAD: Direct delta tracking + exponential decay fling after lift.
 * 2. MOUSE WHEEL: Animated target using an OutCubic curve.
 */
Item {
    id: root

    required property var flickable

    // === Touchpad physics ===
    property real flingFriction: Config?.options.interactions.scrolling.flingFriction ?? 0.002
    property real flingStopThreshold: Config?.options.interactions.scrolling.flingStopThreshold ?? 0.01
    readonly property real flingMinVelocity: 0.5
    property real touchpadSensitivity: (Config?.options.interactions.scrolling.touchpadSensitivity ?? 3.5)
                                       * (Config?.options.interactions.scrolling.touchpadScrollFactor ?? 1.0)
    property real bounceDamping: Config?.options.interactions.scrolling.bounceDamping ?? 0.3

    // === Mouse wheel physics ===
    property int wheelScrollAmount: Math.round(
        (Config?.options.interactions.scrolling.wheelScrollAmount ?? 100)
        * (Config?.options.interactions.scrolling.mouseScrollFactor ?? 1.0))
    property int wheelDurationMin: Config?.options.interactions.scrolling.wheelDurationMin ?? 200
    property int wheelDurationMax: Config?.options.interactions.scrolling.wheelDurationMax ?? 400
    property int mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

    // === Internal state ===
    property real _velocity: 0
    property real _wheelTargetY: 0
    property real _lastEventTime: 0
    property var  _velocitySamples: []

    Timer {
        id: liftTimer
        interval: 80
        repeat: false
        onTriggered: root._computeAndStartFling()
    }

    FrameAnimation {
        id: physicsLoop
        running: false
        onTriggered: {
            var dt = frameTime * 1000
            if (dt <= 0) dt = 16.67
            root._velocity *= Math.pow(1.0 - root.flingFriction, dt)
            var maxY = Math.max(0, root.flickable.contentHeight - root.flickable.height)
            var newY = root.flickable.contentY - root._velocity * dt
            if (maxY > 0) {
                if (newY < 0) { newY = 0; root._velocity = -root._velocity * root.bounceDamping }
                else if (newY > maxY) { newY = maxY; root._velocity = -root._velocity * root.bounceDamping }
            } else { newY = 0 }
            root.flickable.contentY = newY
            if (Math.abs(root._velocity) < root.flingStopThreshold) { root._velocity = 0; running = false }
        }
    }

    NumberAnimation {
        id: wheelAnim
        target: root.flickable
        property: "contentY"
        easing.type: Easing.OutCubic
    }

    // =========================================================
    // Public API: called by MouseArea.onWheel in ContentPage/other wrappers
    //
    // Device distinction:
    //   Mouse wheel  → angleDelta.y is an exact non-zero multiple of 120
    //   Touchpad     → angleDelta.y is NOT a multiple of 120 (high-res inertia)
    //   Phase end    → angleDelta.y == 0  (Wayland scroll phase separator)
    // =========================================================
    function handleWheel(event) {
        var dy = event.angleDelta.y
        if (dy === 0) return
        var enabled = Config?.options?.interactions?.scrolling?.fasterTouchpadScroll
        if (enabled === false) return
        var isMouseWheel = (Math.abs(dy) % 120 === 0)
        console.log("[ISE] handleWheel dy=" + dy + " isMouseWheel=" + isMouseWheel + " flickable=" + root.flickable + " contentH=" + root.flickable.contentHeight + " h=" + root.flickable.height)
        if (isMouseWheel) {
            root._handleMouseWheel(event)
        } else {
            root._handleTouchpad(event)
        }
        event.accepted = true
    }

    function _handleTouchpad(event) {
        var dy = event.angleDelta.y
        if (dy === 0) return
        if (wheelAnim.running) { wheelAnim.stop(); root._wheelTargetY = root.flickable.contentY }
        physicsLoop.running = false
        // Prefer pixelDelta from compositor (exact pixels), fall back to angleDelta * multiplier
        var px = event.pixelDelta.y
        var deltaPx = (px !== 0) ? -px : -dy * root.touchpadSensitivity
        var now = Date.now()
        var dt = now - root._lastEventTime
        if (dt > 0 && dt < 150) {
            root._velocitySamples.push(deltaPx / dt)
            if (root._velocitySamples.length > 6) root._velocitySamples.shift()
        } else if (dt >= 150) {
            root._velocitySamples = []
        }
        root._lastEventTime = now
        var maxY = Math.max(0, root.flickable.contentHeight - root.flickable.height)
        var newY = Math.max(0, Math.min(root.flickable.contentY + deltaPx, maxY))
        console.log("[ISE-TP] deltaPx=" + deltaPx.toFixed(0) + " contentY=" + root.flickable.contentY.toFixed(0) + " -> " + newY.toFixed(0) + " maxY=" + maxY.toFixed(0))
        root.flickable.contentY = newY
        liftTimer.restart()
    }

    function _computeAndStartFling() {
        if (root._velocitySamples.length === 0) { root._velocity = 0; return }
        var total = 0, weightSum = 0
        for (var i = 0; i < root._velocitySamples.length; i++) {
            var w = i + 1; total += root._velocitySamples[i] * w; weightSum += w
        }
        root._velocity = total / weightSum
        root._velocitySamples = []
        if (Math.abs(root._velocity) >= root.flingMinVelocity) { physicsLoop.running = true }
        else { root._velocity = 0 }
    }

    function _handleMouseWheel(event) {
        physicsLoop.running = false; liftTimer.stop(); root._velocity = 0; root._velocitySamples = []
        var direction = event.angleDelta.y > 0 ? -1 : 1
        var maxY = Math.max(0, root.flickable.contentHeight - root.flickable.height)
        var base = wheelAnim.running ? root._wheelTargetY : root.flickable.contentY
        root._wheelTargetY = Math.max(0, Math.min(base + direction * root.wheelScrollAmount, maxY))
        var distance = Math.abs(root._wheelTargetY - root.flickable.contentY)
        var duration = Math.max(root.wheelDurationMin, Math.min(root.wheelDurationMax, distance * 2))
        wheelAnim.stop(); wheelAnim.from = root.flickable.contentY
        wheelAnim.to = root._wheelTargetY; wheelAnim.duration = duration; wheelAnim.start()
    }
}
