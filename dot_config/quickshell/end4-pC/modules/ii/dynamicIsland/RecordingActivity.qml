import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property bool expanded: false
    property var payload: ({})

    readonly property int elapsed: payload.elapsed !== undefined ? payload.elapsed : 0

    function fmt(sec) {
        const m = Math.floor(sec / 60)
        const s = sec % 60
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    // ===================== Compact（两端对齐）=====================
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 14
        spacing: 8
        visible: !root.expanded

        // 左：脉冲红点
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 9
            implicitHeight: 9

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: IslandTheme.danger
                opacity: 0.0
                scale: 1.0
                SequentialAnimation on scale {
                    running: true
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 2.2; duration: 1100; easing.type: Easing.OutCubic }
                    NumberAnimation { to: 1.0; duration: 0 }
                }
                SequentialAnimation on opacity {
                    running: true
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.4; to: 0.0; duration: 1100; easing.type: Easing.OutCubic }
                    NumberAnimation { to: 0.4; duration: 0 }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: IslandTheme.danger
            }
        }

        Item { Layout.fillWidth: true }

        // 右：计时
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.fmt(root.elapsed)
            color: IslandTheme.text
            font.family: IslandTheme.fontFamily
            font.pixelSize: IslandTheme.fontBody
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
    }

    // ===================== Expanded =====================
    // 参考 macOS Dynamic Island「展开态是紧凑态放大版」：脉冲点 + 图标
    // 拉到左侧，右侧放大计时 + 录制提示文案。
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14
        visible: root.expanded

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // 脉冲红点（放大版）
            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 12
                implicitHeight: 12

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    radius: width / 2
                    color: IslandTheme.danger
                    opacity: 0.0
                    SequentialAnimation on scale {
                        running: true
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 2.4; duration: 1100; easing.type: Easing.OutCubic }
                        NumberAnimation { to: 1.0; duration: 0 }
                    }
                    SequentialAnimation on opacity {
                        running: true
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.5; to: 0.0; duration: 1100; easing.type: Easing.OutCubic }
                        NumberAnimation { to: 0.5; duration: 0 }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    radius: width / 2
                    color: IslandTheme.danger
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "videocam"
                font.family: IslandTheme.iconFontFamily
                font.pixelSize: 20
                color: IslandTheme.text
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                text: qsTr("正在录制")
                color: IslandTheme.text
                font.family: IslandTheme.fontFamily
                font.pixelSize: IslandTheme.fontBody
                font.weight: Font.DemiBold
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.fmt(root.elapsed)
                color: IslandTheme.text
                font.family: IslandTheme.fontFamily
                font.pixelSize: IslandTheme.fontBody + 2
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }
        }

        Text {
            Layout.fillWidth: true
            text: qsTr("屏幕内容正在被捕获到 OBS / 录屏工具")
            color: IslandTheme.textSecondary
            font.family: IslandTheme.fontFamily
            font.pixelSize: IslandTheme.fontSmall
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }
    }
}
