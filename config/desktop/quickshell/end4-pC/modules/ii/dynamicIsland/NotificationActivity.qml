import QtQuick
import QtQuick.Layouts
import qs.modules.common.widgets
import Quickshell.Services.Notifications

// 通知活动：来消息时的轻量提示。
// 通常作为主岛右侧的伴随指示器出现；
// 若通知到达时没有其它活动，则短暂占用主岛。
//
// 头像直接复用原生 NotificationPopup 的 NotificationAppIcon，
// 保证与弹出通知的显示逻辑 100% 一致（避免自己写 Image 导致差异）。
Item {
    id: root

    property bool expanded: false
    property var payload: ({})

    readonly property string summary: payload.summary !== undefined ? payload.summary : ""
    readonly property string appName: payload.appName !== undefined ? payload.appName : ""
    readonly property string body: payload.body !== undefined ? payload.body : ""
    readonly property string image: payload.image !== undefined ? payload.image : ""
    readonly property string appIcon: payload.appIcon !== undefined ? payload.appIcon : ""

    // 头像尺寸：compact 用 22，expanded 用 44
    readonly property int avatarSizeCompact: 22
    readonly property int avatarSizeExpanded: 44

    // ===================== Compact =====================
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 14
        spacing: 8
        visible: !root.expanded

        // 头像：与弹出通知共用组件，image/appIcon fallback 行为完全一致
        // 直接设 implicitSize 而非 scale，避免 scale 双重缩放（布局+视觉）
        NotificationAppIcon {
            id: compactAvatar
            Layout.alignment: Qt.AlignVCenter
            implicitSize: root.avatarSizeCompact
            image: root.image
            appIcon: root.appIcon
            summary: root.summary
            urgency: NotificationUrgency.Normal
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
    // 参考 macOS Dynamic Island「展开态是紧凑态的放大版」原则：
    // 头像放大、文字展开，相对位置保持一致。
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10
        visible: root.expanded

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // 大头像：与弹出通知共用组件
            NotificationAppIcon {
                id: expandedAvatar
                Layout.alignment: Qt.AlignVCenter
                implicitSize: root.avatarSizeExpanded
                image: root.image
                appIcon: root.appIcon
                summary: root.summary
                urgency: NotificationUrgency.Normal
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: root.appName.length > 0 ? root.appName : "通知"
                    color: IslandTheme.textSecondary
                    font.family: IslandTheme.fontFamily
                    font.pixelSize: IslandTheme.fontSmall
                    elide: Text.ElideRight
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
            }
            Item { Layout.fillWidth: true }
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
