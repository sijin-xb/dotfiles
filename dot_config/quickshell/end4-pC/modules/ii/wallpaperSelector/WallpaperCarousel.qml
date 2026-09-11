pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * Horizontal wallpaper carousel with the signature skewed-card look:
 * the selected item sits centred and enlarged, neighbours shrink and tilt
 * away along a shared shear axis.
 */
Item {
    id: root

    property var model: null
    property int currentIndex: 0
    property bool ready: false
    property string activePath: Config.options.background.wallpaperPath

    readonly property real skewFactor: -0.35
    readonly property real itemHeight: Math.max(180, height * 0.58)
    readonly property real itemWidth: itemHeight * 0.92
    readonly property real enlargedWidth: itemWidth * 1.5
    readonly property real enlargedHeight: itemHeight + 24
    readonly property real selectedCenterOffset: (skewFactor * itemHeight) / 2

    signal wallpaperSelected(string filePath, bool isVideo)

    function moveSelection(delta) {
        if (!model || model.count === 0) return;
        const next = Math.max(0, Math.min(model.count - 1, view.currentIndex + delta));
        if (next === view.currentIndex) return;
        view.currentIndex = next;
        view.positionViewAtIndex(next, ListView.Center);
    }

    function activateCurrent() {
        if (!model || currentIndex < 0 || currentIndex >= model.count) return;
        const item = model.get(currentIndex);
        if (item && item.filePath) root.wallpaperSelected(item.filePath, !!item.isVideo);
    }

    function positionOn(filePath) {
        if (!model || !filePath) return;
        for (let i = 0; i < model.count; i++) {
            if (model.get(i).filePath === filePath) {
                view.currentIndex = i;
                view.positionViewAtIndex(i, ListView.Center);
                return;
            }
        }
    }

    ListView {
        id: view
        anchors.fill: parent
        orientation: ListView.Horizontal
        clip: false
        reuseItems: true
        cacheBuffer: root.itemWidth * 3
        interactive: true
        model: root.model

        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width / 2) - (root.enlargedWidth / 2) + root.selectedCenterOffset
        preferredHighlightEnd: (width / 2) + (root.enlargedWidth / 2) + root.selectedCenterOffset
        highlightMoveDuration: 400

        header: Item {
            width: Math.max(0, (view.width / 2) - (root.enlargedWidth / 2) + root.selectedCenterOffset)
        }
        footer: Item {
            width: Math.max(0, (view.width / 2) - (root.enlargedWidth / 2) - root.selectedCenterOffset)
        }

        onCurrentIndexChanged: root.currentIndex = currentIndex

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                const delta = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)
                    ? wheel.angleDelta.x : wheel.angleDelta.y;
                if (Math.abs(delta) < 30) { wheel.accepted = true; return; }
                root.moveSelection(delta > 0 ? -1 : 1);
                wheel.accepted = true;
            }
        }

        delegate: Item {
            id: card

            required property int index
            required property string fileName
            required property string filePath
            required property bool isVideo
            required property string bucket

            readonly property bool isCurrent: ListView.isCurrentItem
            readonly property int distance: Math.abs(index - view.currentIndex)
            readonly property real sideScale: Math.max(0.58, Math.pow(0.88, Math.max(0, distance - 1)))
            readonly property real dynamicRadius: {
                const base = Appearance.rounding.large;
                const k = Math.min(1.0, Math.pow(base / 48, 2));
                const decay = Math.max(0.45, Math.pow(0.85, distance));
                return base * (1.0 - k * (1.0 - decay));
            }

            width: isCurrent ? root.enlargedWidth : (root.itemWidth * 0.48 * sideScale)
            height: isCurrent ? root.enlargedHeight
                              : root.itemHeight * Math.max(0.62, Math.pow(0.90, Math.max(0, distance - 1)))
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            anchors.verticalCenterOffset: 16
            z: isCurrent ? 100 : Math.max(1, 50 - distance)
            opacity: root.ready ? 1.0 : 0.0

            Behavior on width {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }
            Behavior on height {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            Item {
                id: skewedFrame
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -(root.skewFactor * height) / 2
                width: parent.width
                height: parent.height
                transform: Matrix4x4 {
                    property real s: root.skewFactor
                    matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                }

                Item {
                    id: paperFrame
                    anchors.fill: parent
                    anchors.margins: 3
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: paperFrame.width
                            height: paperFrame.height
                            radius: card.dynamicRadius
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Appearance.colors.colLayer2
                    }

                    ThumbnailImage {
                        id: paperImage
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -24
                        width: parent.width + (parent.height * Math.abs(root.skewFactor)) + 48
                        height: parent.height
                        fillMode: Image.PreserveAspectCrop
                        sourcePath: card.filePath
                        generateThumbnail: true
                        sourceSize.width: Math.round(root.enlargedWidth)
                        sourceSize.height: Math.round(root.enlargedHeight)
                        transform: Matrix4x4 {
                            property real s: -root.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Appearance.colors.colPrimary
                        opacity: card.isCurrent ? 0 : 0.18
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: card.dynamicRadius
                    color: "transparent"
                    border.width: card.isCurrent ? 2 : 1
                    border.color: card.filePath === root.activePath
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer0Border
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: card.isVideo
                    text: "play_circle"
                    iconSize: 36
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.9
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        view.currentIndex = card.index;
                        root.wallpaperSelected(card.filePath, card.isVideo);
                    }
                    onEntered: view.currentIndex = card.index
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: !root.model || root.model.count === 0
        text: Translation.tr("No wallpapers found")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.large
    }
}
