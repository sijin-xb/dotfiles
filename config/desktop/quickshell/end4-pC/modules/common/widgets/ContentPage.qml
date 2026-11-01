import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import qs.modules.common

/**
 * Scrollable page container for settings panels.
 *
 * Uses a MouseArea overlay (z=1) to intercept wheel events before the
 * inner Flickable's C++ handler. Inertial scroll physics are implemented
 * inline using a NumberAnimation + Timer to avoid cross-component issues.
 */
Item {
    id: root
    clip: true

    property real baseWidth: 600
    property bool forceWidth: false
    property real bottomContentPadding: Config.options.settings.style === "minimal" ? 40 : 90

    // Children placed in ContentPage appear inside the ColumnLayout
    default property alias data: contentColumn.data

    implicitWidth: contentColumn.implicitWidth

    // =========================================================
    // Inner Flickable
    // =========================================================
    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: contentColumn.implicitHeight + root.bottomContentPadding
        boundsBehavior: Flickable.DragOverBounds
        maximumFlickVelocity: 3500

        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: contentColumn
            width: root.forceWidth ? root.baseWidth : Math.max(root.baseWidth, implicitWidth)
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
                margins: 20
            }
            spacing: 30
        }

        ClippingRectangle {
            id: highlight
            z: 10
            radius: Appearance.rounding.small
            color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.12)
            opacity: 0
            visible: opacity > 0

            property real sweep: 0

            Rectangle {
                width: highlight.width * 0.45
                height: highlight.height
                x: highlight.sweep * (highlight.width - width)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.4) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            ParallelAnimation {
                id: flash

                SequentialAnimation {
                    NumberAnimation { target: highlight; property: "opacity"; to: 1; duration: 150 }
                    PauseAnimation { duration: 1500 }
                    NumberAnimation { target: highlight; property: "opacity"; to: 0; duration: 500 }
                }

                SequentialAnimation {
                    PropertyAction { target: highlight; property: "sweep"; value: 0 }
                    SequentialAnimation {
                        loops: 2
                        NumberAnimation { target: highlight; property: "sweep"; to: 1; duration: 450; easing.type: Easing.InOutSine }
                        NumberAnimation { target: highlight; property: "sweep"; to: 0; duration: 450; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
    }

    // =========================================================
    // Scroll physics — inline, no external engine component
    // =========================================================
    property real _targetY: 0
    property real _flingVelocity: 0
    property var  _samples: []
    property real _lastT: 0

    // Mouse wheel: smooth Bezier animation to target
    NumberAnimation {
        id: _wheelAnim
        target: flickable
        property: "contentY"
        duration: 200
        easing.type: Easing.OutCubic
    }

    // Touchpad fling & overscroll spring: physics loop
    Timer {
        id: _flingTimer
        interval: 16
        repeat: true
        onTriggered: {
            var maxY = Math.max(0, flickable.contentHeight - flickable.height)
            var y = flickable.contentY
            var step = 0
            
            if (y < 0) {
                if (root._flingVelocity < -0.1) {
                    root._flingVelocity *= 0.65       // Stop quickly when pushing out
                    step = root._flingVelocity * 16
                } else {
                    root._flingVelocity = 0
                    step = (0 - y) * 0.2              // Smooth glide back to 0
                }
            } else if (y > maxY) {
                if (root._flingVelocity > 0.1) {
                    root._flingVelocity *= 0.65       // Stop quickly when pushing out
                    step = root._flingVelocity * 16
                } else {
                    root._flingVelocity = 0
                    step = (maxY - y) * 0.2           // Smooth glide back to maxY
                }
            } else {
                root._flingVelocity *= 0.96           // Normal friction inside bounds
                step = root._flingVelocity * 16
            }
            
            flickable.contentY = y + step
            
            // Stop condition: low velocity AND we are safely inside/at bounds
            if (Math.abs(step) < 0.5) {
                var finalY = flickable.contentY
                if (finalY < 0.5 && finalY > -0.5) flickable.contentY = 0
                else if (finalY > maxY - 0.5 && finalY < maxY + 0.5) flickable.contentY = maxY
                
                if (flickable.contentY >= 0 && flickable.contentY <= maxY) {
                    _flingTimer.stop()
                    root._flingVelocity = 0
                }
            }
        }
    }

    // Lift detection: finger-lift → start fling
    Timer {
        id: _liftTimer
        interval: 80
        onTriggered: {
            if (root._samples.length > 0) {
                var total = 0, ws = 0
                for (var i = 0; i < root._samples.length; i++) {
                    var w = i + 1; total += root._samples[i] * w; ws += w
                }
                root._flingVelocity = total / ws  // result in px/ms
                root._samples = []
            }
            
            var maxY = Math.max(0, flickable.contentHeight - flickable.height)
            var outOfBounds = (flickable.contentY < 0 || flickable.contentY > maxY)
            
            if (Math.abs(root._flingVelocity * 16) >= 1.0 || outOfBounds) {
                _flingTimer.restart()
            }
        }
    }

    function _clampY(y) {
        return Math.max(0, Math.min(y, Math.max(0, flickable.contentHeight - flickable.height)))
    }

    function _handleTouchpad(event) {
        var dy = event.angleDelta.y
        if (dy === 0) return
        _wheelAnim.stop()
        _flingTimer.stop()
        // Prefer pixelDelta from compositor (exact pixels), fall back to angleDelta * multiplier
        var px = event.pixelDelta.y
        var deltaPx = (px !== 0) ? -px : -dy * 1.2
        var maxY = Math.max(0, flickable.contentHeight - flickable.height)
        
        // Resistance when dragging out of bounds
        if (flickable.contentY < 0 && deltaPx < 0) deltaPx *= 0.3
        if (flickable.contentY > maxY && deltaPx > 0) deltaPx *= 0.3
        
        var now = Date.now()
        var dt = now - root._lastT
        if (dt > 0 && dt < 150) {
            root._samples.push(deltaPx / dt)
            if (root._samples.length > 6) root._samples.shift()
        } else if (dt >= 150) {
            root._samples = []
        }
        root._lastT = now
        flickable.contentY = flickable.contentY + deltaPx
        _liftTimer.restart()
    }

    function _findItem(rootItem, predicate) {
        for (let i = 0; i < rootItem.children.length; i++) {
            const child = rootItem.children[i]
            if (predicate(child)) return child
        }
        for (let i = 0; i < rootItem.children.length; i++) {
            const found = _findItem(rootItem.children[i], predicate)
            if (found) return found
        }
        return null
    }

    function _ownLabel(item) {
        const value = item.title ?? item.text
        return typeof value === "string" ? value.toLowerCase().trim() : ""
    }

    function goTo(label, section, subsection) {
        const wantedLabel = (label ?? "").toLowerCase().trim()
        const wantedSection = (section ?? "").toLowerCase().trim()

        const sectionItem = wantedSection === "" ? null
            : _findItem(contentColumn, item => item.sectionId !== undefined && _ownLabel(item) === wantedSection)
        const wantedSubsection = (subsection ?? "").toLowerCase().trim()
        const subsectionItem = wantedSubsection === "" ? null
            : _findItem(sectionItem ?? contentColumn, item => item.sectionId === undefined && typeof item.title === "string" && _ownLabel(item) === wantedSubsection)
        const scope = subsectionItem ?? sectionItem ?? contentColumn

        let target = sectionItem && (wantedLabel === "" || wantedLabel === wantedSection) ? sectionItem : null
        if (!target) target = _findItem(scope, item => _ownLabel(item) === wantedLabel)
        if (!target) target = _findItem(scope, item => _ownLabel(item).includes(wantedLabel))
        if (!target) return

        let expanded = false
        for (let parent = target; parent; parent = parent.parent) {
            if (parent.collapsed === true && typeof parent.toggleCollapsed === "function") {
                parent.toggleCollapsed()
                expanded = true
            }
        }
        _pendingTarget = target
        _goToPass = 0
        _syncHighlight()
        _goToTimer.interval = expanded ? 300 : 60
        _goToTimer.restart()
    }

    property Item _pendingTarget: null
    property int _goToPass: 0

    function _syncHighlight() {
        const target = root._pendingTarget
        if (!target) return
        if (typeof target.flashTitle === "function") return
        const pos = target.mapToItem(flickable.contentItem, 0, 0)
        highlight.x = pos.x
        highlight.y = pos.y
        highlight.width = target.width
        highlight.height = target.height
    }

    function _scrollToPending() {
        const target = root._pendingTarget
        if (!target) return
        const pos = target.mapToItem(flickable.contentItem, 0, 0)
        const wanted = root._clampY(pos.y - 24)
        if (root._goToPass > 0 && Math.abs(wanted - flickable.contentY) < 4) return
        _flingTimer.stop()
        root._targetY = wanted
        _wheelAnim.stop()
        _wheelAnim.from = flickable.contentY
        _wheelAnim.to = wanted
        _wheelAnim.duration = 350
        _wheelAnim.start()
    }

    Timer {
        id: _goToTimer
        onTriggered: {
            root._scrollToPending()
            if (root._goToPass === 0) {
                root._goToPass = 1
                interval = 450
                restart()
                if (typeof root._pendingTarget.flashTitle === "function") root._pendingTarget.flashTitle()
                else flash.restart()
            }
        }
    }

    Timer {
        id: _followTimer
        interval: 33
        repeat: true
        running: highlight.visible
        onTriggered: root._syncHighlight()
    }

    function _handleMouseWheel(dy) {
        _flingTimer.stop()
        _liftTimer.stop()
        root._samples = []
        var dir = dy > 0 ? -1 : 1
        var base = _wheelAnim.running ? root._targetY : flickable.contentY
        root._targetY = _clampY(base + dir * 120)    // 120 px per wheel click
        var dist = Math.abs(root._targetY - flickable.contentY)
        _wheelAnim.stop()
        _wheelAnim.from = flickable.contentY
        _wheelAnim.to   = root._targetY
        _wheelAnim.duration = Math.max(80, Math.min(200, dist * 1.5))
        _wheelAnim.start()
    }

    // =========================================================
    // MouseArea overlay — intercepts wheel before Flickable
    // acceptedButtons: Qt.NoButton → press/drag pass through to Flickable
    // =========================================================
    MouseArea {
        anchors.fill: parent
        z: 1
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
            var dy = wheel.angleDelta.y
            if (dy === 0) { wheel.accepted = true; return }
            // Mouse wheel: exact multiples of 120
            // Touchpad: non-multiples (high-res Wayland scroll)
            if (Math.abs(dy) % 120 === 0) {
                root._handleMouseWheel(dy)
            } else {
                root._handleTouchpad(wheel)
            }
            wheel.accepted = true
        }
    }
}
