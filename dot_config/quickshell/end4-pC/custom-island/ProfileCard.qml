import QtQuick
import QtQuick.Effects
import Quickshell.Io

// ─────────────────────────────────────────────────────────────────────────
// 从 Brain_Shell 的 src/services/home/ProfileCard.qml 移植。
//
// 改动：
//   1. 删除 import "../../" 与 import "../../components"（同目录隐式导入即可拿到 StatCard）；
//   2. 其余内容逐字保留 —— 头像圆形遮罩（MultiEffect）、用户名 / WM / uptime 三段
//      取数用的 bash Process 与 60s 轮询 Timer 全部原样保留。
//
// 依赖：StatCard（同目录）、Theme（同目录兼容单例）、QtQuick.Effects（MultiEffect）。
// ─────────────────────────────────────────────────────────────────────────

// Profile card — circular avatar, username, window manager, uptime.

StatCard {
    id: root
    padding: 0

    property string avatarPath: ""

    property string _user:   ""
    property string _wm:     ""
    property string _uptime: ""

    Process {
        command: ["bash", "-c", "echo $USER"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim() !== "") root._user = line.trim()
            }
        }
    }

    Process {
        command: ["bash", "-c", "echo ${XDG_CURRENT_DESKTOP:-Hyprland}"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim() !== "") root._wm = line.trim()
            }
        }
    }

    Process {
        id: uptimeProc
        command: ["bash", "-c",
            "uptime -p | sed 's/up //' | sed 's/ hours\\?/h/' | " +
            "sed 's/ minutes\\?/m/' | sed 's/ days\\?/d/' | sed 's/, / /g'"]
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim() !== "") root._uptime = line.trim()
            }
        }
    }

    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: { uptimeProc.running = false; uptimeProc.running = true }
    }

    Component.onCompleted: uptimeProc.running = true

    Row {
        anchors {
            left:           parent.left;  leftMargin:  16
            right:          parent.right; rightMargin: 16
            verticalCenter: parent.verticalCenter
        }
        spacing: 18

        // Circular avatar
        Item {
            width: 72; height: 72
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(166/255,208/255,247/255,0.22) }
                    GradientStop { position: 1.0; color: Qt.rgba(80/255,130/255,190/255,0.14) }
                }
                border.color: Qt.rgba(166/255,208/255,247/255,0.22)
                border.width: 1
            }

            Rectangle {
                id: photoMask
                anchors.fill: parent
                radius: width / 2
                visible: false
                layer.enabled: true
            }

            Image {
                id: avatarImage
                anchors.fill: parent
                source:   root.avatarPath !== "" ? ("file://" + root.avatarPath) : ""
                fillMode: Image.PreserveAspectCrop
                smooth:   true
                visible:  root.avatarPath !== "" && status !== Image.Error
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled:      true
                    maskSource:       photoMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin:  1.0
                }
            }

            Text {
                anchors.centerIn: parent
                text:           "󰀄"
                font.pixelSize: 28
                // 与 end4-pC 既有用法一致：Nerd 字形必须显式指定 Nerd 字体，
                // 否则落到主字体后字库缺失、渲染成豆腐块
                font.family:    Theme.nerdFontFamily
                color:          Theme.active
                // 上游只在「没配头像」时显示占位；这里补上「配了但读不出来」的情况
                visible:        root.avatarPath === "" || avatarImage.status === Image.Error
            }
        }

        // Text stats
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                text:           root._user
                font.pixelSize: 17; font.weight: Font.DemiBold
                color:          Theme.active
            }

            Row {
                spacing: 8
                Text {
                    text: "󰣇"; font.pixelSize: 12; color: Theme.active
                    font.family: Theme.nerdFontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root._wm; font.pixelSize: 12
                    color: Qt.rgba(205/255,214/255,244/255,0.55)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                spacing: 8
                Text {
                    text: "󰔚"; font.pixelSize: 12; color: Theme.active
                    font.family: Theme.nerdFontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root._uptime; font.pixelSize: 12
                    font.family: Theme.monoFontFamily
                    color: Qt.rgba(205/255,214/255,244/255,0.55)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
