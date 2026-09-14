import QtQuick
import QtQuick.Layouts

// 电池活动：图标 + 文案 + 百分比。瞬态活动。
// 之前没有展开态（声明了 expanded 但没渲染内容），补一个电量条 +
// 充电/低电量状态说明，让展开后有信息可看。
Item {
    id: root

    property bool expanded: false
    property var payload: ({})

    readonly property string iconName: payload.icon !== undefined ? payload.icon : "battery_full"
    readonly property string label: payload.label !== undefined ? payload.label : ""
    readonly property int percent: payload.percent !== undefined ? payload.percent : 0

    // ===================== Compact =====================
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

    // ===================== Expanded =====================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14
        visible: root.expanded

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.iconName
                font.family: IslandTheme.iconFontFamily
                font.pixelSize: 22
                color: root.iconName === "battery_alert" ? IslandTheme.danger : IslandTheme.text
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                text: root.label.length > 0 ? root.label : "电池"
                color: IslandTheme.text
                font.family: IslandTheme.fontFamily
                font.pixelSize: IslandTheme.fontBody
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.percent + "%"
                color: root.percent <= 20 ? IslandTheme.danger : IslandTheme.text
                font.family: IslandTheme.fontFamily
                font.pixelSize: IslandTheme.fontBody + 2
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
            }
        }

        // 电量条
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 10
            radius: 5
            color: IslandTheme.track
            clip: true

            Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.max(0, Math.min(100, root.percent)) / 100
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.percent <= 20 ? IslandTheme.danger : IslandPalette.progressStart }
                    GradientStop { position: 1.0; color: root.percent <= 20 ? IslandTheme.danger : IslandPalette.progressEnd }
                }
                Behavior on width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
