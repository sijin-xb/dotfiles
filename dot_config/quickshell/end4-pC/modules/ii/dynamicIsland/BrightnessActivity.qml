import QtQuick
import QtQuick.Layouts
import qs.services

// 亮度活动：形态与音量对称，compact 两端对齐，展开一条进度。
Item {
    id: root

    property bool expanded: false
    property var payload: ({})

    readonly property int level: payload.level !== undefined ? payload.level : 0
    readonly property string iconName: level < 34 ? "brightness_low"
        : (level < 67 ? "brightness_medium" : "brightness_high")

    // ===================== Compact（两端对齐）=====================
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 14
        spacing: 8
        visible: !root.expanded

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.iconName
            font.family: IslandTheme.iconFontFamily
            font.pixelSize: 16
            color: IslandTheme.text
        }

        Item { Layout.fillWidth: true }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.level + "%"
            color: IslandTheme.text
            font.family: IslandTheme.fontFamily
            font.pixelSize: IslandTheme.fontBody
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }

    // ===================== Expanded =====================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
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
                text: Translation.tr("Brightness")
                color: IslandTheme.text
                font.family: IslandTheme.fontFamily
                font.pixelSize: IslandTheme.fontBody
                font.weight: Font.DemiBold
            }
            Item { Layout.fillWidth: true }
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.level + "%"
                color: IslandTheme.text
                font.family: IslandTheme.fontFamily
                font.pixelSize: IslandTheme.fontBody
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "brightness_low"
                font.family: IslandTheme.iconFontFamily
                font.pixelSize: 14
                color: IslandTheme.textDisabled
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 8
                radius: 4
                color: IslandTheme.track
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    // 有封面主色时跟随，否则纯白
                    color: IslandPalette.accentOr(IslandTheme.text)
                    width: parent.width * root.level / 100
                    Behavior on width { NumberAnimation { duration: IslandTheme.durationQuick; easing.type: Easing.OutCubic } }
                }
            }
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "brightness_high"
                font.family: IslandTheme.iconFontFamily
                font.pixelSize: 14
                color: IslandTheme.textDisabled
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: 16
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 20
                    radius: 2
                    color: index < Math.round(root.level / 6.25) ? IslandTheme.text : IslandTheme.track
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }
    }
}
