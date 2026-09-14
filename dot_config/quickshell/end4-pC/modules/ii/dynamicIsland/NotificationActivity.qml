import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

// 通知活动：来消息时的轻量提示。
// 通常作为主岛右侧的伴随指示器出现；
// 若通知到达时没有其它活动，则短暂占用主岛。
//
// 头像策略（与原生 NotificationPopup 一致）：
//   1. notif.image 有值（QQ 头像等）→ 显示圆形头像，右下角叠小 appIcon
//   2. 否则有 appIcon → 显示应用图标
//   3. 都没有 → 通知铃铛 Material Symbol
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

        // 头像 / 图标
        Item {
            id: compactAvatar
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.avatarSizeCompact
            Layout.preferredHeight: root.avatarSizeCompact

            // image 优先：圆形头像
            Image {
                anchors.fill: parent
                visible: root.image.length > 0
                source: root.image
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: true
                sourceSize.width: root.avatarSizeCompact
                sourceSize.height: root.avatarSizeCompact
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: root.avatarSizeCompact
                        height: root.avatarSizeCompact
                        radius: width / 2
                    }
                }
            }

            // appIcon fallback
            IconImage {
                anchors.fill: parent
                visible: root.image.length === 0 && root.appIcon.length > 0
                source: Quickshell.iconPath(root.appIcon, "image-missing")
                asynchronous: true
            }

            // 都没有：铃铛
            Text {
                anchors.fill: parent
                visible: root.image.length === 0 && root.appIcon.length === 0
                text: "notifications"
                font.family: IslandTheme.iconFontFamily
                font.pixelSize: 16
                color: IslandTheme.text
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
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

            // 头像（大）+ 右下角叠加小 appIcon
            Item {
                id: expandedAvatar
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: root.avatarSizeExpanded
                Layout.preferredHeight: root.avatarSizeExpanded

                Image {
                    anchors.fill: parent
                    visible: root.image.length > 0
                    source: root.image
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    asynchronous: true
                    sourceSize.width: root.avatarSizeExpanded
                    sourceSize.height: root.avatarSizeExpanded
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: root.avatarSizeExpanded
                            height: root.avatarSizeExpanded
                            radius: width / 2
                        }
                    }
                }

                IconImage {
                    anchors.fill: parent
                    visible: root.image.length === 0 && root.appIcon.length > 0
                    source: Quickshell.iconPath(root.appIcon, "image-missing")
                    asynchronous: true
                }

                Text {
                    anchors.fill: parent
                    visible: root.image.length === 0 && root.appIcon.length === 0
                    text: "notifications"
                    font.family: IslandTheme.iconFontFamily
                    font.pixelSize: 28
                    color: IslandTheme.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                // image 有值时右下角叠小 appIcon（标识来源应用）
                IconImage {
                    visible: root.image.length > 0 && root.appIcon.length > 0
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.bottomMargin: -2
                    anchors.rightMargin: -2
                    implicitSize: root.avatarSizeExpanded * 0.42
                    asynchronous: true
                    source: Quickshell.iconPath(root.appIcon, "image-missing")
                }
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
