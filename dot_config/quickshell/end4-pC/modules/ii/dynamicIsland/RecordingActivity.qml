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
}
