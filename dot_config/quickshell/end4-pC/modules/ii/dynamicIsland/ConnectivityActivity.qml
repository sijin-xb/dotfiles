import QtQuick
import QtQuick.Layouts

// 连接状态活动：蓝牙 / WiFi 的连接与断开提示。
// 瞬态，无展开态——只在切换瞬间给一个确认。
Item {
    id: root

    property bool expanded: false
    property var payload: ({})

    readonly property string iconName: payload.icon !== undefined ? payload.icon : "bluetooth"
    readonly property string label: payload.label !== undefined ? payload.label : ""

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 14
        spacing: 8

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.iconName
            font.family: IslandTheme.iconFontFamily
            font.pixelSize: 16
            color: IslandTheme.text
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            text: root.label
            color: IslandTheme.text
            font.family: IslandTheme.fontFamily
            font.pixelSize: IslandTheme.fontBody
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }
}
