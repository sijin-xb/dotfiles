import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * 录屏灵动岛。
 *
 * 状态来源：Persistent.states.record.enable
 *   - scripts/videos/record.sh 在录制开始/结束时写入该字段。
 *   - Persistent 单例通过 FileView 监听 states.json，变更后自动刷新。
 *
 * 交互：录制期间在顶部中央显示一枚胶囊（脉冲红点 + 时长 + 停止按钮）。
 *   整枚胶囊任意处均可点击以结束录制，右侧按钮为视觉提示。
 *   这样避免了按钮与外层点击区的事件竞争，行为始终一致。
 *
 * 也提供 IPC：qs -c end4-pC ipc call recordIndicator stop
 */
Scope {
    id: root

    readonly property bool recording: Persistent.states.record.enable
    property int elapsedSeconds: 0

    function fmtTime(totalSeconds) {
        const m = Math.floor(totalSeconds / 60);
        const s = totalSeconds % 60;
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    function stopRecording() {
        Quickshell.execDetached([Directories.recordScriptPath]);
    }

    IpcHandler {
        target: "recordIndicator"

        function stop(): void {
            root.stopRecording();
        }
    }

    onRecordingChanged: {
        if (root.recording)
            root.elapsedSeconds = 0;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.elapsedSeconds += 1
    }

    Loader {
        active: root.recording

        sourceComponent: PanelWindow {
            id: island
            screen: Quickshell.screens[0] ?? null
            color: "transparent"

            WlrLayershell.namespace: "quickshell:recordIndicator"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            anchors {
                top: true
            }
            margins {
                top: Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
            }

            implicitWidth: pill.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: pill.height + Appearance.sizes.elevationMargin * 2

            StyledRectangularShadow {
                target: pill
            }

            Rectangle {
                id: pill
                anchors.centerIn: parent
                implicitWidth: contentRow.implicitWidth + 28
                implicitHeight: 34
                width: implicitWidth
                height: implicitHeight
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                // 出现动画：轻微放大 + 淡入
                property real enterProgress: 0
                opacity: enterProgress
                scale: 0.94 + 0.06 * enterProgress
                property bool hovered: false

                Component.onCompleted: enterAnim.start()

                NumberAnimation {
                    id: enterAnim
                    target: pill
                    property: "enterProgress"
                    to: 1
                    duration: 280
                    easing.type: Easing.OutCubic
                }

                // 整岛统一点击区：声明在内容之前，z 序更低，只负责接收点击。
                // 子项均为纯视觉元素，不争夺事件，因此点岛上任意处行为一致。
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: pill.hovered = true
                    onExited: pill.hovered = false
                    onClicked: root.stopRecording()
                }

                RowLayout {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: 9

                    // 脉冲红点：实心点 + 向外扩散的光晕
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 8
                        implicitHeight: 8

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height
                            radius: width / 2
                            color: Appearance.m3colors.m3error
                            opacity: 0.0

                            SequentialAnimation on scale {
                                running: true
                                loops: Animation.Infinite
                                NumberAnimation {
                                    from: 1.0
                                    to: 2.2
                                    duration: 1100
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    to: 1.0
                                    duration: 0
                                }
                            }
                            SequentialAnimation on opacity {
                                running: true
                                loops: Animation.Infinite
                                NumberAnimation {
                                    from: 0.4
                                    to: 0.0
                                    duration: 1100
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    to: 0.4
                                    duration: 0
                                }
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.height
                            radius: width / 2
                            color: Appearance.m3colors.m3error
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.fmtTime(root.elapsedSeconds)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        font.features: {
                            "tnum": 1
                        }
                        color: Appearance.colors.colOnSurface
                    }

                    // 停止按钮：纯视觉提示，实际点击由整岛 MouseArea 处理。
                    // 直接居中图标，避免 Button 内边距导致的对齐偏移。
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: width / 2
                        color: Appearance.colors.colLayer2
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        opacity: pill.hovered ? 1.0 : 0.92

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "stop"
                            iconSize: 13
                            color: Appearance.m3colors.m3error
                        }
                    }
                }
            }
        }
    }
}
