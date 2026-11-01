pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * 桌面右键菜单「默认打开」子面板：
 * 按类别列出系统里可设为默认打开方式的应用（来自 scripts/menu/default-apps.py），
 * 点击应用即用 xdg-mime 设为该类别默认，勾选标记随重新扫描自动移动。
 */
Rectangle {
    id: root

    implicitWidth: 284
    implicitHeight: contentCol.implicitHeight + 16
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer0

    property var model: null
    property bool loading: true
    property string expandedKey: ""

    function setDefault(appId, mimes) {
        setProc.command = ["xdg-mime", "default", appId].concat(mimes);
        setProc.running = true;
    }

    Process {
        id: queryProc
        command: [`${Directories.scriptPath}/menu/default-apps.py`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.model = JSON.parse(text);
                } catch (e) {
                    root.model = null;
                }
                root.loading = false;
            }
        }
    }

    Process {
        id: setProc
        command: []
        onExited: queryProc.running = true // 设置完成后重新扫描，勾选自动移动
    }

    Component.onCompleted: queryProc.running = true

    ColumnLayout {
        id: contentCol
        anchors { fill: parent; margins: 8 }
        spacing: 4

        StyledText {
            Layout.fillWidth: true
            text: root.loading ? "正在扫描应用…" : "点击应用设为各类别的默认打开方式"
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: root.loading ? [] : (root.model?.categories ?? [])

            delegate: ColumnLayout {
                id: catBlock

                required property var modelData
                readonly property var defaultApp: modelData.apps.find(a => a.id === modelData.default) ?? null
                readonly property bool expanded: root.expandedKey === modelData.key

                Layout.fillWidth: true
                spacing: 2

                RippleButton {
                    id: catRow
                    Layout.fillWidth: true
                    implicitHeight: 40
                    colBackground: catBlock.expanded ? Appearance.colors.colLayer2 : "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2
                    contentItem: RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 10
                        MaterialSymbol {
                            text: catBlock.modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: catBlock.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: catBlock.defaultApp ? `当前：${catBlock.defaultApp.name}` : "未设置"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        MaterialSymbol {
                            text: "chevron_right"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.4
                            rotation: catBlock.expanded ? 90 : 0
                            Behavior on rotation {
                                NumberAnimation { duration: 120 }
                            }
                        }
                    }
                    onClicked: root.expandedKey = catBlock.expanded ? "" : catBlock.modelData.key
                }

                ColumnLayout {
                    visible: catBlock.expanded
                    Layout.fillWidth: true
                    spacing: 0

                    Repeater {
                        model: catBlock.modelData.apps

                        delegate: RippleButton {
                            id: appRow

                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: 34
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2
                            contentItem: RowLayout {
                                anchors { fill: parent; leftMargin: 28; rightMargin: 10 }
                                spacing: 10
                                Image {
                                    visible: appRow.modelData.icon.length > 0
                                    source: appRow.modelData.icon.length > 0 ? Quickshell.iconPath(appRow.modelData.icon, "") : ""
                                    sourceSize: Qt.size(18, 18)
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: appRow.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }
                                MaterialSymbol {
                                    visible: appRow.modelData.id === catBlock.modelData.default
                                    text: "check_circle"
                                    iconSize: 16
                                    fill: 1
                                    color: Appearance.colors.colPrimary
                                }
                            }
                            onClicked: root.setDefault(appRow.modelData.id, catBlock.modelData.mimes)
                        }
                    }
                }
            }
        }
    }
}
