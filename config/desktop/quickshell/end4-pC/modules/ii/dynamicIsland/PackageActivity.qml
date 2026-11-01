import QtQuick
import QtQuick.Layouts

// 包管理活动：下载 / AUR 构建进度。
// 通常以「右侧副岛」形式出现（与录屏的左侧副岛对称）；
// 没有音乐等更高优先级活动时也会占用主岛，此时可用展开态看细节。
Item {
    id: root

    property bool expanded: false
    property var payload: ({})

    readonly property int percent: payload.percent !== undefined ? payload.percent : -1
    readonly property bool indeterminate: payload.indeterminate !== undefined
        ? payload.indeterminate : (percent < 0)
    readonly property string label: payload.label !== undefined ? payload.label : ""

    // 任务图标由数据源指定（payload.icon），未指定时回退到下载图标。
    // 这样 PackageActivity 能直接复用给 download 等其它任务类型。
    readonly property string iconName: payload.icon !== undefined ? payload.icon : "download"

    // ===================== Compact =====================
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 14
        spacing: 7
        visible: !root.expanded

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.iconName
            font.family: IslandTheme.iconFontFamily
            font.pixelSize: 16
            color: IslandTheme.text
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 40
            implicitHeight: 4
            radius: 2
            color: IslandTheme.track
            clip: true

            Rectangle {
                visible: !root.indeterminate
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0, Math.min(100, root.percent)) / 100
                gradient: Gradient {
                    GradientStop { position: 0.0; color: IslandPalette.progressStart }
                    GradientStop { position: 1.0; color: IslandPalette.progressEnd }
                }
                Behavior on width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }

            Rectangle {
                id: compactIndetBlock
                visible: root.indeterminate
                width: 16
                height: parent.height
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: IslandPalette.progressStart }
                    GradientStop { position: 1.0; color: IslandPalette.progressEnd }
                }
                SequentialAnimation on x {
                    running: compactIndetBlock.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: -16; to: 40; duration: 850; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 40; to: -16; duration: 850; easing.type: Easing.InOutSine }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: root.indeterminate
            text: "progress_activity"
            font.family: IslandTheme.iconFontFamily
            font.pixelSize: 14
            color: IslandTheme.text
            transformOrigin: Item.Center
            RotationAnimation on rotation {
                running: parent.visible
                from: 0; to: 360
                duration: 1000
                loops: Animation.Infinite
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: !root.indeterminate
            text: root.percent + "%"
            color: IslandTheme.text
            font.family: IslandTheme.fontFamily
            font.pixelSize: IslandTheme.fontBody
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }

    // ===================== Expanded =====================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14
        visible: root.expanded

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.iconName
                font.family: IslandTheme.iconFontFamily
                font.pixelSize: 20
                color: IslandTheme.text
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                text: root.label.length > 0 ? root.label : "软件包任务"
                color: IslandTheme.text
                font.family: IslandTheme.fontFamily
                font.pixelSize: IslandTheme.fontBody
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: !root.indeterminate
                text: root.percent + "%"
                color: IslandTheme.text
                font.family: IslandTheme.fontFamily
                font.pixelSize: IslandTheme.fontBody
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: root.indeterminate
                text: "progress_activity"
                font.family: IslandTheme.iconFontFamily
                font.pixelSize: 18
                color: IslandTheme.text
                transformOrigin: Item.Center
                RotationAnimation on rotation {
                    running: parent.visible
                    from: 0; to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 10
            radius: 5
            color: IslandTheme.track
            clip: true

            Rectangle {
                visible: !root.indeterminate
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0, Math.min(100, root.percent)) / 100
                gradient: Gradient {
                    GradientStop { position: 0.0; color: IslandPalette.progressStart }
                    GradientStop { position: 1.0; color: IslandPalette.progressEnd }
                }
                Behavior on width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }

            Rectangle {
                id: expandedIndetBlock
                visible: root.indeterminate
                width: parent.width * 0.3
                height: parent.height
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: IslandPalette.progressStart }
                    GradientStop { position: 1.0; color: IslandPalette.progressEnd }
                }
                SequentialAnimation on x {
                    running: expandedIndetBlock.visible
                    loops: Animation.Infinite
                    NumberAnimation {
                        from: -expandedIndetBlock.width
                        to: expandedIndetBlock.parent.width
                        duration: 1100
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: expandedIndetBlock.parent.width
                        to: -expandedIndetBlock.width
                        duration: 1100
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
