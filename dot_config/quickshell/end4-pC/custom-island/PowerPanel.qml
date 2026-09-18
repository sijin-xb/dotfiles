/**
 * 从 Brain_Shell 的 src/modules/Center/PowerPanel.qml 移植。
 *
 * 改动（envy / 独显模式切换全部移除）：
 *   1) 删掉 `import "../../"`、`import "../../components"`。
 *   2) 删掉 `required property var envyService` —— EnvyControlService 不在本次
 *      移植范围内（用户是 AMD 独显，没有 NVIDIA / envycontrol）。
 *   3) 整个「GPU Mode」区块（Integrated / Hybrid 两个按钮 + "requires a reboot"
 *      提示）以及中间那条 200×1 分隔线一并移除，因为这两个按钮的唯一作用就是
 *      调 `envyService.switchMode()`，没有服务就是死按钮。剩下的「Power Profile」
 *      区块原样保留。
 *   4) 原来「Power Profile」按钮用的是 Brain_Shell 的 ProfileButton 组件。ProfileButton
 *      不在本次移植的文件清单里（qmldir 也没有它），而这里只用到它的一个静态形态
 *      （label + active:true + enabled:true，且原文件根本没接 onClicked），所以就地
 *      展开成等价的静态胶囊：尺寸 = 文本宽度 + 24、高 28、radius = 高/2、
 *      底色与描边都是 Theme.active、文字 Theme.background / 11px / Font.Medium。
 *      像素结果与 ProfileButton 完全一致。
 */
import QtQuick

Item {
    id: root

    required property var cpuFreqService

    Column {
        anchors.centerIn: parent
        spacing:          16

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8

            // Label + lock icon hinting auto-cpufreq manages this
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 5

                Text {
                    text:           "󰌾"
                    font.family:    Theme.nerdFontFamily
                    font.pixelSize: 11
                    color:          Qt.rgba(1, 1, 1, 0.25)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text:           "Power Profile"
                    font.pixelSize: 11
                    font.weight:    Font.Medium
                    color:          Qt.rgba(1, 1, 1, 0.4)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6

                // ProfileButton 的静态展开（见文件头第 4 条）
                Item {
                    implicitWidth:  profileLabel.implicitWidth + 24
                    implicitHeight: 28

                    Rectangle {
                        anchors.fill: parent
                        radius:       height / 2

                        color:        Theme.active
                        border.color: Theme.active
                        border.width: 1

                        Text {
                            id: profileLabel
                            anchors.centerIn: parent
                            text:           root.cpuFreqService.activeProfile === "performance" ? "Performance" : "Power Saver"
                            font.pixelSize: 11
                            font.weight:    Font.Medium
                            color:          Theme.background
                        }
                    }
                }
            }
        }
    }
}
