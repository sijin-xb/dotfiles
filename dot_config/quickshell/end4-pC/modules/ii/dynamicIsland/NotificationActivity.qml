import QtQuick
import QtQuick.Layouts

// 通知活动：来消息时的轻量提示。
// 通常作为主岛右侧的伴随指示器出现；
// 若通知到达时没有其它活动，则短暂占用主岛。
Item {
    id: root

    property bool expanded: false
    property var payload: ({})

    readonly property string summary: payload.summary !== undefined ? payload.summary : ""
    readonly property string appName: payload.appName !== undefined ? payload.appName : ""
    readonly property string body: payload.body !== undefined ? payload.body : ""

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
            text: "notifications"
            font.family: IslandTheme.iconFontFamily
            font.pixelSize: 16
            color: IslandTheme.text
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            text: root.summary.length > 0 ? root.summary
                : (root.appName.length > 0 ? root.appName : "新通知")
            color: IslandTheme.text
            font.family: IslandTheme.fontFamily
            font.pixelSize: IslandTheme.fontBody
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
    }

    // ===================== Expanded =====================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10
        visible: root.expanded

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "notifications"
                font.family: IslandTheme.iconFontFamily
                font.pixelSize: 20
                color: IslandTheme.text
            }
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.appName.length > 0 ? root.appName : "通知"
                color: IslandTheme.textSecondary
                font.family: IslandTheme.fontFamily
                font.pixelSize: IslandTheme.fontSmall
            }
            Item { Layout.fillWidth: true }
        }

        Text {
            Layout.fillWidth: true
            text: root.summary
            color: IslandTheme.text
            font.family: IslandTheme.fontFamily
            font.pixelSize: IslandTheme.fontBody + 1
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            visible: root.body.length > 0
            text: root.body
            color: IslandTheme.textSecondary
            font.family: IslandTheme.fontFamily
            font.pixelSize: IslandTheme.fontSmall
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }
    }
}
