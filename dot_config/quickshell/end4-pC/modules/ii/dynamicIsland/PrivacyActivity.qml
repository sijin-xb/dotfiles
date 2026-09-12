import QtQuick
import QtQuick.Layouts
import qs.services

// 隐私指示：麦克风 / 摄像头占用。
// 常驻活动，无展开态——只做状态提示，不需要细节页。
Item {
    id: root

    property bool expanded: false
    property var payload: ({})

    readonly property bool mic: payload.mic !== undefined ? payload.mic : false
    readonly property bool camera: payload.camera !== undefined ? payload.camera : false

    readonly property string iconName: (root.mic && root.camera) ? "devices"
        : (root.camera ? "videocam" : "mic")

    readonly property string label: {
        if (root.mic && root.camera)
            return Translation.tr("Mic & camera in use")
        return root.camera ? Translation.tr("Camera in use") : Translation.tr("Mic in use")
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 14
        spacing: 8

        // 脉冲圆点：与录屏指示器同一视觉语言，但用警示色
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 9
            implicitHeight: 9

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: IslandTheme.warning
                opacity: 0.0
                SequentialAnimation on scale {
                    running: true
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 2.2; duration: 1400; easing.type: Easing.OutCubic }
                    NumberAnimation { to: 1.0; duration: 0 }
                }
                SequentialAnimation on opacity {
                    running: true
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.4; to: 0.0; duration: 1400; easing.type: Easing.OutCubic }
                    NumberAnimation { to: 0.4; duration: 0 }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: IslandTheme.warning
            }
        }

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
