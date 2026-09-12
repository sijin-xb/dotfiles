import QtQuick
import QtQuick.Layouts

// 电池活动：图标 + 文案 + 百分比。瞬态，无展开态。
Item {
    id: root

    property bool expanded: false
    property var payload: ({})

    readonly property string iconName: payload.icon !== undefined ? payload.icon : "battery_full"
    readonly property string label: payload.label !== undefined ? payload.label : ""
    readonly property int percent: payload.percent !== undefined ? payload.percent : 0

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

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.percent + "%"
            color: IslandTheme.text
            font.family: IslandTheme.fontFamily
            font.pixelSize: IslandTheme.fontBody
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }
}
